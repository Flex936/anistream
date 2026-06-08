package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os/exec"
	"sync"
	"time"

	"github.com/anacrolix/torrent"
)

// App struct holds the application state and aggregates the MPV engine
type App struct {
	ctx           context.Context
	torrentClient *torrent.Client
	httpClient    *http.Client
	mpv           *MpvManager
	cancelStream  context.CancelFunc // Track and kill active stream routines

	mu            sync.RWMutex // guards fields below
	activeFile    *torrent.File
	activeTorrent *torrent.Torrent
	activeCmd     *exec.Cmd
	aniListToken  string // cached from config; mutated only by Login/Logout
	viewerID      int    // 0 = not yet fetched; cached after first successful call
}

func NewApp() *App {
	cfg := torrent.NewDefaultClientConfig()
	cfg.DataDir = "./tmp_downloads"
	cfg.NoUpload = true

	// Aggressive Streaming Network Config
	cfg.EstablishedConnsPerTorrent = 100 // Default is 50. Grab more peers for faster chunks.
	cfg.HalfOpenConnsPerTorrent = 50     // Default is 25. Dial out to peers twice as fast.
	cfg.TorrentPeersHighWater = 1000     // Keep a massive pool of potential peers ready.
	cfg.TorrentPeersLowWater = 500

	client, err := torrent.NewClient(cfg)
	if err != nil {
		log.Fatalf("failed to create torrent client: %v", err)
	}

	app := &App{
		torrentClient: client,
		httpClient:    &http.Client{Timeout: 10 * time.Second},
		mpv:           NewMpvManager(),
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/stream", app.streamHandler)
	mux.HandleFunc("/anime-data", app.handleMetadata)
	fileServer := http.FileServer(http.Dir("./tmp_hls"))
	hlsHandler := http.StripPrefix("/hls/", fileServer)

	// Wrap it with CORS middleware so hls.js can access index.m3u8 and .m4s segments
	mux.Handle("/hls/", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Range, Content-Type")
		w.Header().Set("Access-Control-Expose-Headers", "Content-Length, Content-Range")

		// Tell the browser this is a live stream, do not cache!
		w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
		w.Header().Set("Pragma", "no-cache")
		w.Header().Set("Expires", "0")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}

		hlsHandler.ServeHTTP(w, r)
	}))

	go func() {
		srv := &http.Server{Addr: ":8080", Handler: mux}
		log.Println("[Server] Launching HTTP streaming server on :8080...")
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("stream server exited: %v", err)
		}
	}()

	return app
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	cfg := LoadConfig()
	a.mu.Lock()
	a.aniListToken = cfg.AniListToken
	a.mu.Unlock()

	if err := a.mpv.Init(); err != nil {
		log.Printf("[MPV] Failed to initialize mpv: %v", err)
	}
}

func (a *App) shutdown(ctx context.Context) {
	a.mpv.Shutdown()
}

func (a *App) handleMetadata(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	payload, err := a.mpv.GetMetadata()
	if err != nil {
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(payload)
}

func (a *App) GetMpvMetadata() (*FrontendPayload, error) {
	return a.mpv.GetMetadata()
}

// SendMpvCommand allows Svelte to send commands directly to MPV.
// This will auto-generate the MpvCommand type!
func (a *App) SendMpvCommand(command []interface{}) error {
	conn, err := DialMpv()
	if err != nil {
		return err
	}
	defer conn.Close()

	sendCommand(conn, command)
	return nil
}

func (a *App) ChangeTrackAndRestart(timeInSeconds float64, sid string, aid string) error {
	a.mu.RLock()
	file := a.activeFile
	a.mu.RUnlock()

	if file == nil {
		return fmt.Errorf("no active torrent stream to restart")
	}

	sourceURL := "http://localhost:8080/stream"

	cfg := LoadConfig()
	encoder := cfg.Encoder
	if encoder == "" {
		encoder = "libx264"
	}

	if err := a.mpv.StartTranscode(sourceURL, timeInSeconds, sid, aid, encoder); err != nil {
		return fmt.Errorf("failed to restart stream with new tracks: %w", err)
	}

	return nil
}
