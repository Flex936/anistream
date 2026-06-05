package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
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
	httpClient    *http.Client
	mpv           *MpvManager // Access point to separated MPV logic
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
		mpv:           NewMpvManager(), // Initialize MPV manager
	}

	mux := http.NewServeMux()
	// streamHandler is assumed to be defined in stream.go
	mux.HandleFunc("/stream", app.streamHandler)
	mux.HandleFunc("/mpv-stream", app.mpv.LiveStreamHandler)

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

// MPVStream takes a magnet link, gets the stream URL, and forwards it to the MPV processor
func (a *App) MPVStream(magnetLink string, selectedSubtitle string) (string, error) {
	streamURL, err := a.StreamTorrent(magnetLink) // Fetch the localhost torrent server address
	if err != nil {
		return "", err
	}

	if selectedSubtitle == "" {
		selectedSubtitle = "1"
	}

	// Send the structural instructions directly to the frontend player element
	targetPlaybackURL := fmt.Sprintf("http://localhost:8080/mpv-stream?source=%s&sub=%s", streamURL, selectedSubtitle)
	return targetPlaybackURL, nil
}
