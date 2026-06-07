package main

import (
	"context"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/anacrolix/torrent"
)

type App struct {
	ctx           context.Context
	torrentClient *torrent.Client
	httpClient    *http.Client

	mu            sync.RWMutex
	activeFile    *torrent.File
	activeTorrent *torrent.Torrent
	aniListToken  string // cached from config; mutated only by Login/Logout
	viewerID      int    // 0 = not yet fetched; cached after first successful call
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
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/stream", app.streamHandler)

	go func() {
		srv := &http.Server{Addr: ":8080", Handler: mux}
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("stream server exited: %v", err)
		}
	}()

	return app
}

// startup is called by Wails after the window is ready. We warm the token
// cache here so doGraphQL never needs to touch disk during normal operation.
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	cfg := LoadConfig()
	a.mu.Lock()
	a.aniListToken = cfg.AniListToken
	a.mu.Unlock()
}
