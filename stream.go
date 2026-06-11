package main

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/anacrolix/torrent"
)

func (a *App) StreamTorrent(magnetLink string) (string, error) {
	// Instantly nuke any currently active stream using our centralized cleanup
	a.StopStream()

	// Setup the fresh stream context
	a.mu.Lock()
	ctx, cancel := context.WithCancel(context.Background())
	a.cancelStream = cancel
	a.mu.Unlock()

	t, err := a.torrentClient.AddMagnet(magnetLink)
	if err != nil {
		cancel()
		return "", fmt.Errorf("failed to add magnet: %w", err)
	}

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

	PrepareTorrentForStreaming(t, targetFile)
	a.mu.Lock()
	if ctx.Err() != nil {
		a.mu.Unlock()
		t.Drop()
		return "", fmt.Errorf("stream setup aborted before transcoding")
	}
	a.activeTorrent = t
	a.activeFile = targetFile
	a.mu.Unlock()

	sourceURL := "http://localhost:8080/stream"
	sid := "auto"
	aid := "auto"

	encoder, audioEncoder := a.resolveEncoders(sid)
	upscalingMethod, upscalingResolution := a.resolveUpscaling()
	if err := a.mpv.StartTranscode(sourceURL, 0, sid, aid, encoder, audioEncoder, upscalingResolution, upscalingMethod); err != nil {
		// Leverage StopStream to automatically drop context, kill MPV, and dump the bad torrent!
		a.StopStream()
		return "", fmt.Errorf("transcoder failed to initialize: %w", err)
	}

	return "http://localhost:8080/hls/index.m3u8", nil
}

func (a *App) StopStream() {
	a.mu.Lock()
	if a.cancelStream != nil {
		a.cancelStream()
		a.cancelStream = nil
	}
	a.mu.Unlock()

	a.mpv.StopTranscode()

	a.mu.Lock()
	defer a.mu.Unlock()
	if a.activeTorrent != nil {
		a.activeTorrent.Drop()
		a.activeTorrent = nil
		a.activeFile = nil
	}
}

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
	reader.SetReadahead(8 << 20)
	defer reader.Close()

	w.Header().Set("Access-Control-Allow-Origin", "*")
	http.ServeContent(w, r, file.DisplayPath(), time.Time{}, reader)
}

func PrepareTorrentForStreaming(t *torrent.Torrent, f *torrent.File) {
	t.CancelPieces(0, t.NumPieces())
	pieceLength := t.Info().PieceLength
	startPiece := int(f.Offset() / pieceLength)
	endPiece := int((f.Offset() + f.Length()) / pieceLength)

	for i := startPiece; i < startPiece+2 && i <= endPiece; i++ {
		t.Piece(i).SetPriority(torrent.PiecePriorityNow)
	}
	for i := endPiece; i > endPiece-2 && i >= startPiece; i-- {
		t.Piece(i).SetPriority(torrent.PiecePriorityNow)
	}
}
