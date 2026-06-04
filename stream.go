package main

import (
	"fmt"
	"net/http"
	"time"

	"github.com/anacrolix/torrent"
)

func (a *App) StreamTorrent(magnetLink string) (string, error) {
	// drop any previously active stream
	a.mu.Lock()
	if a.activeTorrent != nil {
		a.activeTorrent.Drop()
		a.activeTorrent = nil
		a.activeFile = nil
	}
	a.mu.Unlock()

	t, err := a.torrentClient.AddMagnet(magnetLink)
	if err != nil {
		return "", fmt.Errorf("failed to add magnet: %w", err)
	}

	select {
	case <-t.GotInfo():
	case <-time.After(30 * time.Second):
		t.Drop()
		return "", fmt.Errorf("timed out waiting for torrent metadata")
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
		t.Drop()
		return "", fmt.Errorf("no valid video file found in torrent")
	}

	targetFile.Download()

	a.mu.Lock()
	a.activeTorrent = t
	a.activeFile = targetFile
	a.mu.Unlock()

	return "http://localhost:8080/stream", nil
}

// streamHandler feeds the downloading torrent bytes to the Svelte video player
func (a *App) streamHandler(w http.ResponseWriter, r *http.Request) {
	a.mu.RLock()
	file := a.activeFile
	a.mu.RUnlock()

	if file == nil {
		http.Error(w, "no active stream", http.StatusNotFound)
		return
	}

	reader := file.NewReader()
	reader.SetResponsive()
	reader.SetReadahead(8 << 20) // 8 MB — enough for ~3s of 1080p video
	defer reader.Close()

	w.Header().Set("Access-Control-Allow-Origin", "*")
	http.ServeContent(w, r, file.DisplayPath(), time.Time{}, reader)
}
