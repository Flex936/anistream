package main

import (
	"context"
	"net/http"

	"github.com/anacrolix/torrent"
)

// App struct holds the application state and torrent engine
type App struct {
	ctx           context.Context
	torrentClient *torrent.Client
	activeFile    *torrent.File
}

// NewApp creates a new App application struct and boots the background services
func NewApp() *App {
	// Initialize the torrent client
	clientConfig := torrent.NewDefaultClientConfig()
	clientConfig.DataDir = "./tmp_downloads" // Temporarily store video chunks here
	client, _ := torrent.NewClient(clientConfig)

	app := &App{
		torrentClient: client,
	}

	// Start the local HTTP streaming server in the background
	go func() {
		http.HandleFunc("/stream", app.streamHandler)
		http.ListenAndServe(":8080", nil)
	}()

	return app
}

// startup is called when the app starts. The context is saved so we can call runtime methods.
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
}
