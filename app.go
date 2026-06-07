package main

import (
	"context"
	"encoding/json"
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
	mu            sync.RWMutex // guards fields below
	activeFile    *torrent.File
	activeTorrent *torrent.Torrent
	activeCmd     *exec.Cmd
	httpClient    *http.Client
	mpv           *MpvManager        // Access point to separated MPV logic
	cancelStream  context.CancelFunc // ADD THIS: Track and kill active stream routines
}

func NewApp() *App {
	cfg := torrent.NewDefaultClientConfig()
	cfg.DataDir = "./tmp_downloads"
	cfg.NoUpload = true

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

	// 2. Wrap it with CORS middleware so hls.js can access index.m3u8 and .m4s segments
	mux.Handle("/hls/", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Range, Content-Type")
		w.Header().Set("Access-Control-Expose-Headers", "Content-Length, Content-Range")

		// Handle browser preflight checks instantly
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

// startup is called when the app starts.
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	if err := a.mpv.Init(); err != nil {
		log.Printf("[MPV] Failed to initialize mpv: %v", err)
	}
}

func (a *App) shutdown(ctx context.Context) {
	a.mpv.Shutdown()
}
func (a *App) handleMetadata(w http.ResponseWriter, r *http.Request) {
	// Add CORS so your Svelte dev server can access it
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	// Fetch the metadata from our MPV manager
	payload, err := a.mpv.GetMetadata()
	if err != nil {
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}

	// Send it to the frontend
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(payload)
}
