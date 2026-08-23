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
//  GET  /api/stream/:id/subtitles          → embedded subtitle tracks (once ≥5% downloaded)
//  GET  /api/stream/:id/subtitles/:index   → that track, ?format=vtt|ass|ttml (default vtt)
// DELETE /api/stream/:id                   → explicit cleanup

package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/anacrolix/torrent"
	"golang.org/x/time/rate"
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

	// SubtitlesAvailable: true once it's worth the client even trying —
	// see subtitleProbeEligible's doc comment for why this is a low bar,
	// not "fully downloaded".
	// SubtitlesComplete: true once no further re-fetching will ever
	// return more content — lets the client stop its own re-poll loop.
	SubtitlesAvailable bool `json:"subtitles_available,omitempty"`
	SubtitlesComplete  bool `json:"subtitles_complete,omitempty"`
}

// subtitleTracksResp is the body of GET /api/stream/:id/subtitles.
type subtitleTracksResp struct {
	Tracks []SubtitleTrack `json:"tracks"`
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

	// subtitleTracks caches the last successful probe so repeat polls of
	// /subtitles don't re-shell ffprobe every time. Left nil (not an
	// empty slice) until the first successful probe — a genuinely
	// subtitle-less file gets cached as a non-nil empty slice by
	// ProbeSubtitleTracks itself, which is what lets this same nil check
	// distinguish "haven't probed yet" from "probed, found none".
	subtitleTracks []SubtitleTrack

	// extractedSubtitles caches the last extraction result per (track,
	// format) pair, alongside how much of the file had downloaded when
	// it was produced — lets repeat requests skip re-running ffmpeg/
	// astisub when nothing new has arrived, while still re-extracting
	// (to pick up newly-downloaded cues) once it has. Keyed by format as
	// well as track index — the same track re-requested as ass vs ttml
	// must not be served a stale result cached for the other format. See
	// extractedSubtitle.
	extractedSubtitles map[subtitleCacheKey]*extractedSubtitle
}

// subtitleCacheKey identifies one (track, output format) pair in
// session.extractedSubtitles — see SubtitleFormat in
// subtitle_extractor.go.
type subtitleCacheKey struct {
	index  int
	format SubtitleFormat
}

// extractedSubtitle is one track's cached extraction result.
type extractedSubtitle struct {
	path             string
	extractedAtBytes int64
	// complete is true once this extraction ran against a FULLY
	// downloaded file — permanently final, never re-extracted again.
	complete bool
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

// subtitleProbeEligible reports whether f has enough downloaded to be
// worth attempting a probe/extraction against at all. Deliberately as
// low as bufferThreshold: ffmpeg's Matroska demuxer handles a
// partially-downloaded file gracefully — it reads the Tracks header
// (near the front of the file, not the tail) plus however many complete
// Clusters have arrived, then stops cleanly at the first gap rather than
// hanging or corrupting output. A probe attempted early just returns
// less content, not garbage.
func subtitleProbeEligible(f *torrent.File) bool {
	if f.Length() == 0 {
		return false
	}
	pct := float64(f.BytesCompleted()) / float64(f.Length()) * 100.0
	return pct >= bufferThreshold
}

// subtitlesComplete reports whether f has fully finished downloading —
// i.e. whether an extraction result is FINAL, with no more cues arriving
// later. Used to tell the client when it can stop re-polling for updated
// subtitle content.
func subtitlesComplete(f *torrent.File) bool {
	return f.BytesCompleted() >= f.Length()
}

func (s *session) status(streamBase string, ffmpegReady bool) statusResp {
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
		resp.SubtitlesAvailable = ffmpegReady && s.active != nil && subtitleProbeEligible(s.active)
		resp.SubtitlesComplete = s.active != nil && subtitlesComplete(s.active)
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

// cleanupSubtitleFiles removes any temp subtitle files (vtt/ass/ttml)
// this session extracted, so dropping or reaping a session doesn't leak
// files in os.TempDir().
func (s *session) cleanupSubtitleFiles() {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, entry := range s.extractedSubtitles {
		_ = os.Remove(entry.path)
	}
}

// ── HTTP server ───────────────────────────────────────────────────────────────

type srv struct {
	client   *torrent.Client
	mu       sync.RWMutex
	sessions map[string]*session
	port     int
	dataDir  string // added — needed to resolve a torrent.File's real on-disk path

	// ffmpegReady is resolved once at startup rather than on every
	// request/poll — FFmpegAvailable() shells out to exec.LookPath twice,
	// and the answer can't change during a single run of the server.
	ffmpegReady    bool
	readaheadBytes int64
}

func newID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// filePath resolves f's real location on disk (DataDir + f.Path(), per
// anacrolix/torrent's default storage layout) and defends against a
// maliciously-crafted torrent embedding a path-traversal segment (e.g.
// "../../etc/passwd") in its own file listing. f.Path() ultimately comes
// from tracker/peer-supplied torrent metadata, which this server
// otherwise never has to treat as untrusted filesystem input — video
// serving always goes through torrent.Reader's safe io.ReadSeeker
// interface, never a raw OS path. Shelling out to ffprobe/ffmpeg against
// a literal path is the one place untrusted input reaches the
// filesystem directly, so this containment check exists specifically
// for that exposure.
func (sv *srv) filePath(f *torrent.File) (string, error) {
	full := filepath.Join(sv.dataDir, f.Path())

	absData, err := filepath.Abs(sv.dataDir)
	if err != nil {
		return "", fmt.Errorf("failed to resolve data directory: %w", err)
	}
	absFull, err := filepath.Abs(full)
	if err != nil {
		return "", fmt.Errorf("failed to resolve file path: %w", err)
	}
	if !strings.HasPrefix(absFull, absData+string(filepath.Separator)) {
		return "", fmt.Errorf("resolved file path escapes data directory")
	}

	return full, nil
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
		switch {
		case action == "":
			switch r.Method {
			case http.MethodGet:
				sv.streamStatus(w, r, id)
			case http.MethodDelete:
				sv.dropStream(w, id)
			default:
				http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			}
		case action == "select":
			sv.selectFile(w, r, id)
		case action == "video":
			sv.serveVideo(w, r, id)
		case action == "subtitles":
			sv.listSubtitles(w, r, id)
		case strings.HasPrefix(action, "subtitles/"):
			sv.serveSubtitleTrack(w, r, id, strings.TrimPrefix(action, "subtitles/"))
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
	json200(w, s.status(sv.base(r), sv.ffmpegReady))
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
	reader.SetReadahead(sv.readaheadBytes)

	// http.ServeContent handles Accept-Ranges, Content-Range, Content-Length,
	// ETag, and conditional GETs automatically. MPV's range-request seeking
	// works out of the box because torrent.Reader implements io.ReadSeeker.
	http.ServeContent(w, r, filepath.Base(f.DisplayPath()), time.Now(), reader)
}

// listSubtitles probes the active file for embedded subtitle tracks.
// Only ever reads container metadata (fast) — the actual per-track
// conversion happens lazily in serveSubtitleTrack, so a file with several
// language tracks doesn't pay extraction cost for tracks nobody picks.
func (sv *srv) listSubtitles(w http.ResponseWriter, r *http.Request, id string) {
	s, ok := sv.get(id)
	if !ok {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}

	s.mu.RLock()
	st := s.st
	f := s.active
	cached := s.subtitleTracks
	s.mu.RUnlock()

	if st != stateReady || f == nil {
		http.Error(w, "stream not ready yet", http.StatusServiceUnavailable)
		return
	}

	// nil (not an empty slice) means "haven't successfully probed yet" —
	// see the subtitleTracks field doc comment on session.
	if cached != nil {
		json200(w, subtitleTracksResp{Tracks: cached})
		return
	}

	if !sv.ffmpegReady {
		http.Error(w, "ffmpeg/ffprobe not installed on this server", http.StatusNotImplemented)
		return
	}
	if !subtitleProbeEligible(f) {
		http.Error(w, "file still downloading — not enough of it available to probe subtitles yet", http.StatusServiceUnavailable)
		return
	}

	path, err := sv.filePath(f)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()
	tracks, err := ProbeSubtitleTracks(ctx, path)
	if err != nil {
		http.Error(w, "failed to probe subtitles: "+err.Error(), http.StatusInternalServerError)
		return
	}

	s.mu.Lock()
	s.subtitleTracks = tracks
	s.mu.Unlock()

	json200(w, subtitleTracksResp{Tracks: tracks})
}

// contentTypeFor returns the Content-Type header for a given output
// format. Informational only — the Flutter client already knows which
// format it asked for via the query param, so nothing on that side
// parses this back out.
func contentTypeFor(format SubtitleFormat) string {
	switch format {
	case FormatASS:
		return "text/x-ssa"
	case FormatTTML:
		return "application/ttml+xml"
	default:
		return "text/vtt"
	}
}

// serveSubtitleTrack extracts (or re-extracts, if more has downloaded
// since the last attempt) a single subtitle track in the requested
// format. Sets X-Subtitle-Complete so the client knows whether it's
// worth asking again later for more content, or whether this is final.
func (sv *srv) serveSubtitleTrack(w http.ResponseWriter, r *http.Request, id string, trackIdxStr string) {
	s, ok := sv.get(id)
	if !ok {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}

	streamIndex, err := strconv.Atoi(trackIdxStr)
	if err != nil {
		http.Error(w, "invalid track index", http.StatusBadRequest)
		return
	}

	// Defaults to vtt so a client that never specifies a format —
	// including video_player's Dart-side WebVTT-text path — keeps
	// working unchanged. ass/ttml are the native-parser paths — see
	// native_subtitle_parser.dart / SubtitleParserPlugin.kt on the
	// Flutter side.
	format := SubtitleFormat(r.URL.Query().Get("format"))
	if format == "" {
		format = FormatWebVTT
	}
	if format != FormatWebVTT && format != FormatASS && format != FormatTTML {
		http.Error(w, fmt.Sprintf("unsupported format %q (want vtt, ass, or ttml)", format), http.StatusBadRequest)
		return
	}

	s.mu.RLock()
	st := s.st
	f := s.active
	trackCodec := ""
	for _, t := range s.subtitleTracks {
		if t.StreamIndex == streamIndex {
			trackCodec = t.Codec
			break
		}
	}
	cacheKey := subtitleCacheKey{index: streamIndex, format: format}
	existing := s.extractedSubtitles[cacheKey]
	s.mu.RUnlock()

	if st != stateReady || f == nil {
		http.Error(w, "stream not ready yet", http.StatusServiceUnavailable)
		return
	}

	// ass and ttml both require the source track to actually BE ass/ssa
	// — ass because it's a raw stream copy (forcing -c:s copy against,
	// say, a PGS bitmap track produces a corrupt .ass file, not a valid
	// one), ttml because its conversion step reads that same raw copy as
	// input. vtt has no such restriction — ffmpeg's webvtt encoder
	// accepts any text-based subtitle codec it understands.
	if (format == FormatASS || format == FormatTTML) && !FormatASS.IsNativeCodec(trackCodec) {
		http.Error(w, fmt.Sprintf("track %d is %q, not ass/ssa — %s requires an ass/ssa source track", streamIndex, trackCodec, format), http.StatusUnprocessableEntity)
		return
	}

	// Unconditional, fires for every valid request regardless of
	// cache-hit/fresh-extraction below — the one line to watch in this
	// server's own terminal output to confirm which format a given
	// request actually resolved to.
	log.Printf("[subtitle] session=%s track=%d format=%s codec=%s", id, streamIndex, format, trackCodec)

	currentBytes := f.BytesCompleted()
	complete := subtitlesComplete(f)

	// Serve the cached result without re-running the extraction if it's
	// already final, or if nothing new has downloaded since it was
	// produced — re-extracting identical input would just waste CPU for
	// the same output.
	if existing != nil && (existing.complete || existing.extractedAtBytes >= currentBytes) {
		w.Header().Set("Content-Type", contentTypeFor(format))
		w.Header().Set("X-Subtitle-Complete", strconv.FormatBool(existing.complete))
		http.ServeFile(w, r, existing.path)
		return
	}

	if !sv.ffmpegReady {
		http.Error(w, "ffmpeg not installed on this server", http.StatusNotImplemented)
		return
	}
	if !subtitleProbeEligible(f) {
		http.Error(w, "file still downloading — not enough of it available yet", http.StatusServiceUnavailable)
		return
	}

	srcPath, err := sv.filePath(f)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Same destination path every time for a given (session, track,
	// format) triple — ExtractSubtitleTrack's ffmpeg calls run with -y,
	// so a re-extraction simply overwrites the previous partial result
	// in place rather than needing this handler to separately track and
	// clean up a prior file. Extension carries the format so a track
	// re-requested in a different format never collides with the other
	// format's temp file.
	destPath := filepath.Join(os.TempDir(), fmt.Sprintf("anistream-sub-%s-%d.%s", id, streamIndex, format))

	ctx, cancel := context.WithTimeout(r.Context(), 60*time.Second)
	defer cancel()
	if err := ExtractSubtitleTrack(ctx, srcPath, streamIndex, destPath, format); err != nil {
		http.Error(w, "extraction failed: "+err.Error(), http.StatusInternalServerError)
		return
	}

	s.mu.Lock()
	if s.extractedSubtitles == nil {
		s.extractedSubtitles = make(map[subtitleCacheKey]*extractedSubtitle)
	}
	s.extractedSubtitles[cacheKey] = &extractedSubtitle{
		path:             destPath,
		extractedAtBytes: currentBytes,
		complete:         complete,
	}
	s.mu.Unlock()

	w.Header().Set("Content-Type", contentTypeFor(format))
	w.Header().Set("X-Subtitle-Complete", strconv.FormatBool(complete))
	http.ServeFile(w, r, destPath)
}

// removeSessionData deletes this torrent's downloaded data from disk.
// t.Drop() stops the torrent and closes it, but per anacrolix/torrent's
// own storage docs, never deletes anything from storage — that's left to
// the caller. The default file storage this server uses (no DefaultStorage
// override in main()) lays each torrent's data out directly under dataDir,
// keyed by the torrent's own declared name (Info.Name), so that's the path
// removed here. info is nil for a session that never got past metadata
// resolution, in which case nothing was ever written to disk to begin
// with.
func (sv *srv) removeSessionData(t *torrent.Torrent) {
	info := t.Info()
	if info == nil {
		return
	}
	path := filepath.Join(sv.dataDir, info.Name)
	if err := os.RemoveAll(path); err != nil {
		log.Printf("[cleanup] failed to remove %q: %v", path, err)
	}
}

func (sv *srv) dropStream(w http.ResponseWriter, id string) {
	sv.mu.Lock()
	s, ok := sv.sessions[id]
	if ok {
		s.t.Drop()
		sv.removeSessionData(s.t)
		delete(sv.sessions, id)
	}
	sv.mu.Unlock()
	if !ok {
		http.Error(w, "session not found", http.StatusNotFound)
		return
	}
	s.cleanupSubtitleFiles()
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
				s.cleanupSubtitleFiles()
				sv.removeSessionData(s.t)
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
	readaheadBytes := flag.Int64("readahead-bytes", 10*1024*1024, "per-stream torrent read-ahead in bytes (lower this on memory-constrained servers, e.g. a Raspberry Pi)")
	uploadLimitKBps := flag.Int("upload-limit-kbps", 0, "cap upload/seeding bandwidth in KB/s (0 = unlimited)")
	flag.Parse()

	if err := os.MkdirAll(*dataDir, 0o755); err != nil {
		log.Fatalf("cannot create data directory %q: %v", *dataDir, err)
	}

	cfg := torrent.NewDefaultClientConfig()
	cfg.DataDir = *dataDir
	// Keep seeding so the swarm stays healthy after we finish downloading.
	cfg.NoUpload = false
	if *uploadLimitKBps > 0 {
		// Burst is left at 0 — ClientConfig.UploadRateLimiter's own doc
		// comment says anacrolix/torrent will pick a chunk-sized burst
		// itself in that case, rather than needing one guessed here.
		cfg.UploadRateLimiter = rate.NewLimiter(rate.Limit(*uploadLimitKBps*1024), 0)
	}

	client, err := torrent.NewClient(cfg)
	if err != nil {
		log.Fatalf("cannot start torrent client: %v", err)
	}
	defer client.Close()

	ffmpegReady := FFmpegAvailable()
	if !ffmpegReady {
		log.Printf("ffmpeg/ffprobe not found on PATH — subtitle extraction will be unavailable, video streaming is unaffected")
	}

	server := &srv{
		client:         client,
		sessions:       make(map[string]*session),
		port:           *port,
		dataDir:        *dataDir,
		ffmpegReady:    ffmpegReady,
		readaheadBytes: *readaheadBytes,
	}
	go server.reap()

	addr := fmt.Sprintf(":%d", *port)
	log.Printf("AniStream Server  listening on  http://0.0.0.0%s", addr)
	log.Printf("Data directory:   %s", *dataDir)
	log.Fatal(http.ListenAndServe(addr, server))
}
