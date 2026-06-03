//go:build torrent

package main

import (
	"fmt"
	"net/http"
	"time"

	"github.com/anacrolix/torrent"
)

var (
	globalTorrentClient *torrent.Client
	globalActiveFile    *torrent.File
)

func initTorrentEngine() error {
	if globalTorrentClient != nil {
		return nil
	}
	clientConfig := torrent.NewDefaultClientConfig()
	clientConfig.DataDir = "./tmp_downloads"
	client, err := torrent.NewClient(clientConfig)
	if err != nil {
		return err
	}
	globalTorrentClient = client
	return nil
}

func internalStreamTorrent(magnetLink string) (string, error) {
	if globalTorrentClient == nil {
		return "", fmt.Errorf("torrent client not initialized")
	}

	t, err := globalTorrentClient.AddMagnet(magnetLink)
	if err != nil {
		return "", fmt.Errorf("failed to add magnet: %w", err)
	}

	select {
	case <-t.GotInfo():
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

	globalActiveFile = targetFile
	targetFile.Download()

	return "http://localhost:8080/stream", nil
}

func internalStreamHandler(w http.ResponseWriter, r *http.Request) {
	if globalActiveFile == nil {
		http.Error(w, "No active stream", http.StatusNotFound)
		return
	}

	reader := globalActiveFile.NewReader()
	reader.SetResponsive()
	defer reader.Close()

	w.Header().Set("Access-Control-Allow-Origin", "*")
	http.ServeContent(w, r, globalActiveFile.DisplayPath(), time.Time{}, reader)
}
