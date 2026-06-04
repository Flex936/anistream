package main

import (
	"context"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/anacrolix/torrent"
)

// App struct holds the application state and torrent engine
type App struct {
	ctx           context.Context
	torrentClient *torrent.Client
	httpClient    *http.Client // shared, see anilist.go section

	mu            sync.RWMutex // guards the two fields below
	activeFile    *torrent.File
	activeTorrent *torrent.Torrent
}

// NewApp creates a new App application struct and boots the background services
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
	// streamHandler is defined in stream.go
	mux.HandleFunc("/stream", app.streamHandler)

	go func() {
		srv := &http.Server{Addr: ":8080", Handler: mux}
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("stream server exited: %v", err)
		}
	}()

	return app
}

// startup is called when the app starts. The context is saved so we can call runtime methods.
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
}
