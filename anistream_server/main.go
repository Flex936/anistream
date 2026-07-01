// AniStream Server — offloads BitTorrent work from thin clients (Android TV,
// phones) to a more powerful machine on the same LAN.
//
// Build:  go build -o anistream-server .
// Run:    ./anistream-server -port 7878 -data /tmp/anistream
//
// REST API
// ──────────────────────────────────────────────────────────────────────────
//  GET  /api/health                        → health check (used by the app's ping button)
//  POST /api/stream           {magnet, episode_number?}  → {session_id}
//  GET  /api/stream/:id                    → status (state, buffer_pct, stream_url, files …)
//  POST /api/stream/:id/select {file_index}→ pick a file from a batch torrent
//  GET  /api/stream/:id/video              → HTTP range-request video stream (MPV opens this)
// DELETE /api/stream/:id                   → explicit cleanup

package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/anacrolix/torrent"
)

// ── State machine ─────────────────────────────────────────────────────────────

type state string

const (
	stateLoadingMetadata state = "loading_metadata"
	stateNeedsSelection  state = "needs_selection"
	stateBuffering       state = "buffering"
	stateReady           state = "ready"
	stateError           state = "error"
)

// ── Wire types (JSON) ─────────────────────────────────────────────────────────

type startReq struct {
	Magnet        string `json:"magnet"`
	EpisodeNumber *int   `json:"episode_number,omitempty"`
}

type fileInfo struct {
	Index int    `json:"index"`
	Name  string `json:"name"`
	Size  int64  `json:"size"`
}

type statusResp struct {
	State      state      `json:"state"`
	StatusText string     `json:"status_text"`
	BufferPct  float64    `json:"buffer_pct"`
	Peers      int        `json:"peers"`
	StreamURL  string     `json:"stream_url,omitempty"`
	Files      []fileInfo `json:"files,omitempty"`
	Error      string     `json:"error,omitempty"`
}

// ── Session ───────────────────────────────────────────────────────────────────

type session struct {
	mu         sync.RWMutex
	id         string
	t          *torrent.Torrent
	st         state
	statusText string
	bufferPct  float64
	files      []*torrent.File // video files inside the torrent
	active     *torrent.File   // the file currently being streamed
	lastAccess time.Time
}

var videoExts = map[string]bool{
	".mkv": true, ".mp4": true, ".avi": true,
	".webm": true, ".mov": true, ".m4v": true,
}

func isVideo(path string) bool {
	return videoExts[strings.ToLower(filepath.Ext(path))]
}

func (s *session) setState(st state, text string, pct float64) {
	s.mu.Lock()
	s.st = st
	s.statusText = text
	s.bufferPct = pct
	s.mu.Unlock()
}

// run is launched as a goroutine when a session is created.
func (s *session) run() {
	s.setState(stateLoadingMetadata, "Fetching metadata…", 0)

	// Block until the torrent's info dictionary arrives from the swarm.
	select {
	case <-s.t.GotInfo():
	case <-time.After(3 * time.Minute):
		s.setState(stateError, "Timed out waiting for torrent metadata", 0)
		return
	}

	// Collect video files from the torrent.
	var vfs []*torrent.File
	for _, f := range s.t.Files() {
		// f is *torrent.File — append directly, no pin needed in Go 1.22+
		if isVideo(f.DisplayPath()) {
			vfs = append(vfs, f)
		}
	}
	if len(vfs) == 0 {
		s.setState(stateError, "No video files found in this torrent", 0)
		return
	}

	s.mu.Lock()
	s.files = vfs
	s.mu.Unlock()

	// Single-episode torrent: start immediately.
	if len(vfs) == 1 {
		s.activate(0)
		return
	}

	// Batch torrent: surface the file list and wait for the client to choose.
	s.setState(stateNeedsSelection, "Batch torrent – pick an episode", 0)
}

// activate starts downloading and buffering the file at position idx.
func (s *session) activate(idx int) {
	s.mu.RLock()
	files := s.files
	s.mu.RUnlock()

	if idx < 0 || idx >= len(files) {
		s.setState(stateError, fmt.Sprintf("file index %d out of range", idx), 0)
		return
	}

	f := files[idx]

	// Focus bandwidth on the chosen file; deprioritise everything else.
	for i, other := range files {
		if i != idx {
			other.SetPriority(torrent.PiecePriorityNone)
		}
	}
	f.SetPriority(torrent.PiecePriorityNormal)

	s.mu.Lock()
	s.active = f // f is *torrent.File — no & needed
	s.st = stateBuffering
	s.statusText = "Buffering… 0.0%"
	s.bufferPct = 0
	s.mu.Unlock()

	go s.watchBuffer(f)
}

// bufferThreshold is the percentage of the file that must be downloaded
// before we tell the Flutter client that it can open the stream.
// 5 % is roughly 50–100 MB for a typical episode — enough for MPV to
// parse headers and start rendering without stalling immediately.
const bufferThreshold = 5.0

func (s *session) watchBuffer(f *torrent.File) {
	length := f.Length()
	for {
		time.Sleep(300 * time.Millisecond)

		s.mu.RLock()
		st := s.st
		s.mu.RUnlock()
		if st == stateReady || st == stateError {
			return
		}

		var pct float64
		if length > 0 {
			pct = float64(f.BytesCompleted()) / float64(length) * 100.0
		}

		s.mu.Lock()
		s.bufferPct = pct
		s.statusText = fmt.Sprintf("Buffering… %.1f%%", pct)
		if pct >= bufferThreshold {
			s.st = stateReady
			s.statusText = "Ready"
		}
		s.mu.Unlock()

		if pct >= bufferThreshold {
			return
		}
	}
}

func (s *session) status(streamBase string) statusResp {
	s.mu.RLock()
	defer s.mu.RUnlock()

	resp := statusResp{
		State:      s.st,
		StatusText: s.statusText,
		BufferPct:  s.bufferPct,
		Peers:      s.t.Stats().ActivePeers,
	}
	switch s.st {
	case stateReady:
		resp.StreamURL = streamBase + "/api/stream/" + s.id + "/video"
	case stateNeedsSelection:
		for i, f := range s.files {
			resp.Files = append(resp.Files, fileInfo{
				Index: i,
				Name:  filepath.Base(f.DisplayPath()),
				Size:  f.Length(),
			})
		}
	case stateError:
		resp.Error = s.statusText
	}
	return resp
}

// ── HTTP server ───────────────────────────────────────────────────────────────

type srv struct {
	client   *torrent.Client
	mu       sync.RWMutex
	sessions map[string]*session
	port     int
}

func newID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func (sv *srv) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Allow the Flutter app to reach the server from any origin.
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}

	p := r.URL.Path
	switch {
	case p == "/api/health" && r.Method == http.MethodGet:
		sv.health(w)

	case p == "/api/stream" && r.Method == http.MethodPost:
		sv.addStream(w, r)

	case strings.HasPrefix(p, "/api/stream/"):
		parts := strings.SplitN(strings.TrimPrefix(p, "/api/stream/"), "/", 2)
		id := parts[0]
		action := ""
		if len(parts) == 2 {
			action = parts[1]
		}
		switch action {
		case "":
			switch r.Method {
			case http.MethodGet:
				sv.streamStatus(w, r, id)
			case http.MethodDelete:
				sv.dropStream(w, id)
			default:
				http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			}
		case "select":
			sv.selectFile(w, r, id)
		case "video":
			sv.serveVideo(w, r, id)
		default:
			http.NotFound(w, r)
		}

	default:
		http.NotFound(w, r)
	}
}

func (sv *srv) base(r *http.Request) string {
	host := r.Host
	if host == "" {
		host = fmt.Sprintf("localhost:%d", sv.port)
	}
	return "http://" + host
}

// get looks up a session and refreshes its last-access time.
func (sv *srv) get(id string) (*session, bool) {
	sv.mu.RLock()
	s, ok := sv.sessions[id]
	sv.mu.RUnlock()
	if ok {
		s.mu.Lock()
		s.lastAccess = time.Now()
		s.mu.Unlock()
	}
	return s, ok
}

func json200(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

// ── Handlers ──────────────────────────────────────────────────────────────────

func (sv *srv) health(w http.ResponseWriter) {
	json200(w, map[string]string{
		"name":    "AniStream Server",
		"version": "1.0.0",
		"status":  "ok",
	})
}

func (sv *srv) addStream(w http.ResponseWriter, r *http.Request) {
	var req startReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Magnet == "" {
		http.Error(w, "magnet is required", http.StatusBadRequest)
		return
	}

	t, err := sv.client.AddMagnet(req.Magnet)
	if err != nil {
		http.Error(w, "failed to add magnet: "+err.Error(), http.StatusInternalServerError)
		return
	}

	id := newID()
	s := &session{
		id:         id,
		t:          t,
		st:         stateLoadingMetadata,
		statusText: "Fetching metadata…",
		lastAccess: time.Now(),
	}
	sv.mu.Lock()
	sv.sessions[id] = s
	sv.mu.Unlock()

	go s.run()

	json200(w, map[string]string{"session_id": id})
}

func (sv *srv) streamStatus(w http.ResponseWriter, r *http.Request, id string) {
	s, ok := sv.get(id)
	if !ok {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}
	json200(w, s.status(sv.base(r)))
}

func (sv *srv) selectFile(w http.ResponseWriter, r *http.Request, id string) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST required", http.StatusMethodNotAllowed)
		return
	}
	s, ok := sv.get(id)
	if !ok {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}
	var body struct {
		FileIndex int `json:"file_index"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}
	go s.activate(body.FileIndex)
	json200(w, map[string]bool{"ok": true})
}

func (sv *srv) serveVideo(w http.ResponseWriter, r *http.Request, id string) {
	s, ok := sv.get(id)
	if !ok {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}

	s.mu.RLock()
	st := s.st
	f := s.active
	s.mu.RUnlock()

	if st != stateReady {
		http.Error(w, "stream not ready yet", http.StatusServiceUnavailable)
		return
	}
	if f == nil {
		http.Error(w, "no active file", http.StatusInternalServerError)
		return
	}

	// Each HTTP request gets its own independent reader so that multiple range
	// requests (e.g. MPV seeking while another request is in flight) don't
	// interfere with each other.
	reader := f.NewReader()
	defer reader.Close()

	// SetResponsive tells libtorrent to prioritise pieces near the current
	// read position — this is what makes seeking feel instant even at low
	// buffer percentages.
	reader.SetResponsive()
	reader.SetReadahead(10 * 1024 * 1024) // 10 MB look-ahead

	// http.ServeContent handles Accept-Ranges, Content-Range, Content-Length,
	// ETag, and conditional GETs automatically. MPV's range-request seeking
	// works out of the box because torrent.Reader implements io.ReadSeeker.
	http.ServeContent(w, r, filepath.Base(f.DisplayPath()), time.Now(), reader)
}

func (sv *srv) dropStream(w http.ResponseWriter, id string) {
	sv.mu.Lock()
	s, ok := sv.sessions[id]
	if ok {
		s.t.Drop()
		delete(sv.sessions, id)
	}
	sv.mu.Unlock()
	if !ok {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// reap removes sessions that haven't been touched in 30 minutes.
func (sv *srv) reap() {
	for {
		time.Sleep(5 * time.Minute)
		sv.mu.Lock()
		for id, s := range sv.sessions {
			s.mu.RLock()
			idle := time.Since(s.lastAccess)
			s.mu.RUnlock()
			if idle > 30*time.Minute {
				s.t.Drop()
				delete(sv.sessions, id)
				log.Printf("[reap] dropped idle session %s (idle %v)", id, idle.Round(time.Second))
			}
		}
		sv.mu.Unlock()
	}
}

// ── Entry point ───────────────────────────────────────────────────────────────

func main() {
	port := flag.Int("port", 7878, "port to listen on")
	dataDir := flag.String("data", filepath.Join(os.TempDir(), "anistream-server"), "directory for downloaded torrent data")
	flag.Parse()

	if err := os.MkdirAll(*dataDir, 0o755); err != nil {
		log.Fatalf("cannot create data directory %q: %v", *dataDir, err)
	}

	cfg := torrent.NewDefaultClientConfig()
	cfg.DataDir = *dataDir
	// Keep seeding so the swarm stays healthy after we finish downloading.
	cfg.NoUpload = false

	client, err := torrent.NewClient(cfg)
	if err != nil {
		log.Fatalf("cannot start torrent client: %v", err)
	}
	defer client.Close()

	server := &srv{
		client:   client,
		sessions: make(map[string]*session),
		port:     *port,
	}
	go server.reap()

	addr := fmt.Sprintf(":%d", *port)
	log.Printf("AniStream Server  listening on  http://0.0.0.0%s", addr)
	log.Printf("Data directory:   %s", *dataDir)
	log.Fatal(http.ListenAndServe(addr, server))
}
