package main

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/anacrolix/torrent"
)

func (a *App) StreamTorrent(magnetLink string) (string, error) {
	// 1. Cancel any currently executing stream setup goroutines immediately
	a.mu.Lock()
	if a.cancelStream != nil {
		a.cancelStream()
	}
	// Create a fresh session context for this specific stream request
	ctx, cancel := context.WithCancel(context.Background())
	a.cancelStream = cancel
	a.mu.Unlock()

	// 2. Tell MPV manager to drop any previous background transcodes
	a.mpv.StopTranscode()

	// 3. Drop any previously active torrent stream
	a.mu.Lock()
	if a.activeTorrent != nil {
		a.activeTorrent.Drop()
		a.activeTorrent = nil
		a.activeFile = nil
	}
	a.mu.Unlock()

	t, err := a.torrentClient.AddMagnet(magnetLink)
	if err != nil {
		cancel()
		return "", fmt.Errorf("failed to add magnet: %w", err)
	}

	// Wait for torrent metadata OR timeout OR explicit session cancellation
	select {
	case <-t.GotInfo():
	case <-time.After(30 * time.Second):
		t.Drop()
		cancel()
		return "", fmt.Errorf("timed out waiting for torrent metadata")
	case <-ctx.Done():
		t.Drop()
		return "", fmt.Errorf("stream setup was cancelled by user navigation")
	}

	// Double check cancellation status right after waking up
	if ctx.Err() != nil {
		t.Drop()
		return "", fmt.Errorf("stream setup aborted")
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
		cancel()
		return "", fmt.Errorf("no valid video file found in torrent")
	}

	//targetFile.Download()
	PrepareTorrentForStreaming(t, targetFile)
	a.mu.Lock()
	// Final safety check before mutating shared app state and launching mpv
	if ctx.Err() != nil {
		a.mu.Unlock()
		t.Drop()
		return "", fmt.Errorf("stream setup aborted before transcoding")
	}
	a.activeTorrent = t
	a.activeFile = targetFile
	a.mu.Unlock()

	// 4. Delegate background process creation entirely to your MpvManager
	sourceURL := "http://localhost:8080/stream"
	if err := a.mpv.StartTranscode(sourceURL); err != nil {
		cancel()

		// FIX: Clean up application state and drop torrent if MPV fails/times out
		a.mu.Lock()
		if a.activeTorrent == t {
			a.activeTorrent = nil
			a.activeFile = nil
		}
		a.mu.Unlock()
		t.Drop()

		return "", fmt.Errorf("transcoder failed to initialize: %w", err)
	}

	return "http://localhost:8080/hls/index.m3u8", nil
}

func (a *App) StopStream() {
	// Cancel any active loading/setup lifecycle phase instantly
	a.mu.Lock()
	if a.cancelStream != nil {
		a.cancelStream()
		a.cancelStream = nil
	}
	a.mu.Unlock()

	// Force kill any running MPV process
	a.mpv.StopTranscode()

	a.mu.Lock()
	defer a.mu.Unlock()
	if a.activeTorrent != nil {
		a.activeTorrent.Drop()
		a.activeTorrent = nil
		a.activeFile = nil
	}
}

// streamHandler feeds the downloading torrent bytes to the background MPV engine
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
func PrepareTorrentForStreaming(t *torrent.Torrent, f *torrent.File) {
	// 1. Cancel any global sequential downloading temporarily
	t.CancelPieces(0, t.NumPieces())

	// 2. Calculate the piece range for this specific file
	fileOffset := f.Offset()
	fileLength := f.Length()

	// Get the piece size of the torrent
	pieceLength := t.Info().PieceLength

	startPiece := int(fileOffset / pieceLength)
	endPiece := int((fileOffset + fileLength) / pieceLength)

	// 3. PRIORITIZE THE HEAD AND TAIL (Critical for MKV metadata)
	// High-priority for the first 2 pieces (contains MKV headers)
	for i := startPiece; i < startPiece+2 && i <= endPiece; i++ {
		t.Piece(i).SetPriority(torrent.PiecePriorityHigh)
	}

	// High-priority for the last 2 pieces (contains MKV Cues/Duration/Chapters)
	for i := endPiece; i > endPiece-2 && i >= startPiece; i-- {
		t.Piece(i).SetPriority(torrent.PiecePriorityHigh)
	}

	// 4. Set the rest of the file to normal sequential download
	// anacrolix/torrent allows you to download a specific range sequentially
	go func() {
		// Wait a brief moment or check if head/tail are downloaded,
		// then feed the rest sequentially.
		t.DownloadPieces(startPiece, endPiece)
	}()
}
