package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"
)

type MpvManager struct {
	mutex      sync.Mutex
	activeCmd  *exec.Cmd
	cancelFunc context.CancelFunc // cancels waitForFile when StopTranscode is called
}

func NewMpvManager() *MpvManager {
	return &MpvManager{}
}

func (m *MpvManager) Init() error {
	log.Println("[MPV] Transcoder engine initialized.")
	return nil
}

// StartTranscode fires up a detached background process to slice video into HLS segments.
// The mutex is held only for the setup phase so that StopTranscode can always interrupt
// immediately, even while waitForFile is polling.
func (m *MpvManager) StartTranscode(sourceURL string) error {
	// ── Phase 1: setup (mutex held) ─────────────────────────────────────────
	m.mutex.Lock()

	m.stopOldProcess() // kill any previous transcode + cancel its wait

	_ = os.RemoveAll("./tmp_hls")
	_ = os.MkdirAll("./tmp_hls", 0755)

	// Each transcode gets its own context so we can cancel waitForFile
	// the instant StopTranscode is called, without waiting for polling to finish.
	ctx, cancel := context.WithCancel(context.Background())
	m.cancelFunc = cancel

	// cmd.Dir = "./tmp_hls" is critical: the fMP4 HLS muxer writes init.mp4
	// relative to the process CWD, not relative to --o, so all output files
	// (index.m3u8, init.mp4, *.m4s) must land in the same folder.
	cmd := exec.Command("mpv",
		sourceURL,
		"--o=index.m3u8", // relative to cmd.Dir
		"--of=hls",
		"--ofopts=hls_time=2,hls_segment_type=fmp4,hls_playlist_type=event",
		"--ovc=libx264",
		"--oac=aac",
		"--ovcopts=preset=ultrafast,tune=zerolatency",
		"--sid=1",
	)
	cmd.Dir = "./tmp_hls"

	if err := cmd.Start(); err != nil {
		cancel()
		m.cancelFunc = nil
		m.mutex.Unlock()
		return fmt.Errorf("failed to start mpv background transcode: %w", err)
	}

	m.activeCmd = cmd
	log.Println("[MPV] Started live background HLS transcode pipeline.")

	// ── Phase 2: wait WITHOUT holding the mutex ──────────────────────────────
	// Releasing here lets StopTranscode acquire the lock and kill the process
	// immediately if the user switches videos during the wait.
	m.mutex.Unlock()

	if err := m.waitForFile(ctx, filepath.Join("./tmp_hls", "init.mp4"), 30*time.Second); err != nil {
		m.StopTranscode() // clean up if we timed out or were cancelled
		return err
	}
	return nil
}

// waitForFile polls until path exists or ctx is cancelled (StopTranscode was called)
// or the timeout elapses. It does NOT hold the mutex.
func (m *MpvManager) waitForFile(ctx context.Context, path string, timeout time.Duration) error {
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			// StopTranscode cancelled us — not an error worth surfacing
			return fmt.Errorf("transcode stopped before %s was ready", filepath.Base(path))
		case <-timer.C:
			return fmt.Errorf("timed out waiting for %s — MPV may have crashed or source not yet buffered", filepath.Base(path))
		case <-ticker.C:
			if _, err := os.Stat(path); err == nil {
				log.Printf("[MPV] Ready — %s written to disk.", filepath.Base(path))
				return nil
			}
		}
	}
}

// StopTranscode cancels any in-progress waitForFile, then kills the MPV process.
func (m *MpvManager) StopTranscode() {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	m.stopOldProcess()
}

func (m *MpvManager) Shutdown() {
	m.StopTranscode()
}

// stopOldProcess assumes the mutex is already held.
func (m *MpvManager) stopOldProcess() {
	// Cancel waitForFile first so it stops polling immediately.
	if m.cancelFunc != nil {
		m.cancelFunc()
		m.cancelFunc = nil
	}
	if m.activeCmd != nil && m.activeCmd.Process != nil {
		log.Println("[MPV] Stopping active background transcoder process...")
		_ = m.activeCmd.Process.Kill()
		_ = m.activeCmd.Wait()
		m.activeCmd = nil
	}
}
