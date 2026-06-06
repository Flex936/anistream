package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"
)

type MpvManager struct {
	mutex     sync.Mutex
	activeCmd *exec.Cmd // Tracks the background transcoder process safely
}

func NewMpvManager() *MpvManager {
	return &MpvManager{}
}

func (m *MpvManager) Init() error {
	log.Println("[MPV] Transcoder engine initialized.")
	return nil
}

// StartTranscode fires up a detached background process to slice video into HLS segments
func (m *MpvManager) StartTranscode(sourceURL string) error {
	m.mutex.Lock()
	defer m.mutex.Unlock()

	// 1. Guard against overlapping runs: kill any existing transcoder first
	m.stopOldProcess()

	// 2. Clear out old HLS segment cache
	_ = os.RemoveAll("./tmp_hls")
	_ = os.MkdirAll("./tmp_hls", 0755)

	// 3. Configure MPV to run persistently in the background
	cmd := exec.Command("mpv",
		sourceURL,
		"--o=index.m3u8",
		"--of=hls",
		"--ofopts=hls_time=2,hls_segment_type=fmp4,hls_playlist_type=event",
		"--ovc=libx264",
		"--oac=aac",
		"--ovcopts=preset=ultrafast,tune=zerolatency",
		"--sid=1", // Default to subtitle track 1
	)
	cmd.Dir = "./tmp_hls"
	// Note: We deliberately do NOT use a defer Kill loop here.
	// We want this process to stay alive after this function returns!
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("failed to start mpv background transcode: %w", err)
	}

	m.activeCmd = cmd
	log.Println("[MPV] Started live background HLS transcode pipeline.")
	return m.waitForFile(filepath.Join("./tmp_hls", "init.mp4"), 30*time.Second)
}

func (m *MpvManager) waitForFile(path string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(path); err == nil {
			log.Printf("[MPV] Ready — %s written to disk.", filepath.Base(path))
			return nil
		}
		time.Sleep(250 * time.Millisecond)
	}
	// MPV never produced the file; kill it so we don't leave a zombie.
	m.stopOldProcess()
	return fmt.Errorf("timed out waiting for %s — MPV may have crashed or the source is not yet buffered", filepath.Base(path))
}

// StopTranscode safely halts the active transcoder process
func (m *MpvManager) StopTranscode() {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	m.stopOldProcess()
}

func (m *MpvManager) Shutdown() {
	m.StopTranscode()
}

// Internal helper assumes mutex lock is already held
func (m *MpvManager) stopOldProcess() {
	if m.activeCmd != nil && m.activeCmd.Process != nil {
		log.Println("[MPV] Stopping active background transcoder process...")
		_ = m.activeCmd.Process.Kill()
		_ = m.activeCmd.Wait()
		m.activeCmd = nil
	}
}
