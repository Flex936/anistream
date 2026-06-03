package main

import (
	"fmt"
	"net/http"
	"time"

	"github.com/anacrolix/torrent"
)

// StreamTorrent takes a magnet link, finds the video file, and starts downloading
func (a *App) StreamTorrent(magnetLink string) (string, error) {
	t, err := a.torrentClient.AddMagnet(magnetLink)
	if err != nil {
		return "", fmt.Errorf("failed to add magnet: %w", err)
	}

	// Wait for the P2P swarm to send us the metadata, with a timeout
	select {
	case <-t.GotInfo():
		// metadata received, proceed
	case <-time.After(30 * time.Second):
		t.Drop()
		return "", fmt.Errorf("timed out waiting for torrent metadata — no peers responded")
	}

	var targetFile *torrent.File
	var maxSize int64
	for _, f := range t.Files() {
		if f.Length() > maxSize {
			maxSize = f.Length()
			targetFile = f
		}
	}

	if targetFile == nil {
		return "", fmt.Errorf("no valid video file found in torrent")
	}

	a.activeFile = targetFile
	targetFile.Download()

	return "http://localhost:8080/stream", nil
}

// streamHandler feeds the downloading torrent bytes to the Svelte video player
func (a *App) streamHandler(w http.ResponseWriter, r *http.Request) {
	if a.activeFile == nil {
		http.Error(w, "No active stream", http.StatusNotFound)
		return
	}

	reader := a.activeFile.NewReader()
	reader.SetResponsive()
	defer reader.Close()

	w.Header().Set("Access-Control-Allow-Origin", "*")
	http.ServeContent(w, r, a.activeFile.DisplayPath(), time.Time{}, reader)
}
