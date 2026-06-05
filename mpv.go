package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"sync"
)

type MpvManager struct {
	mutex sync.Mutex
}

func NewMpvManager() *MpvManager {
	return &MpvManager{}
}

// Init can now remain basic as we spawn transcoding pipelines per request
func (m *MpvManager) Init() error {
	log.Println("[MPV] Transcoder engine initialized.")
	return nil
}

func (m *MpvManager) Shutdown() {}

// LiveStreamHandler transcodes the torrent source into a real-time WebM video on the fly
func (m *MpvManager) LiveStreamHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Range, Content-Type")

	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	sourceURL := r.URL.Query().Get("source")
	subTrack := r.URL.Query().Get("sub")

	if sourceURL == "" {
		http.Error(w, "missing source URL parameter", http.StatusBadRequest)
		return
	}
	if subTrack == "" {
		subTrack = "1"
	}

	// 2. Set streaming headers
	w.Header().Set("Content-Type", "video/mp4")
	w.Header().Set("Cache-Control", "no-cache, private")
	w.Header().Set("Connection", "keep-alive")

	// 3. Execute MPV (This burns the subtitles in!)
	cmd := exec.Command("mpv",
		sourceURL,
		"--o=-",
		"--of=mp4",
		"--ovc=libx264",
		"--oac=aac",
		"--ofopts=movflags=frag_keyframe+empty_moov+default_base_moof",
		"--ovcopts=preset=ultrafast,tune=zerolatency",
		fmt.Sprintf("--sid=%s", subTrack), // <-- This burns the subtitles into the stream
	)
	cmd.Stderr = os.Stderr

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	if err := cmd.Start(); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	defer func() {
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
	}()

	_, _ = io.Copy(w, stdout)
}
