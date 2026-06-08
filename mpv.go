package main

import (
	"bufio"
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
	cancelFunc context.CancelFunc
}

func NewMpvManager() *MpvManager {
	return &MpvManager{}
}

func (m *MpvManager) Init() error {
	log.Println("[MPV] Transcoder engine initialized.")
	return nil
}

func (m *MpvManager) StartTranscode(sourceURL string, startTime float64, sid string, aid string, encoder string) error {
	m.mutex.Lock()
	m.stopOldProcess()

	_ = os.RemoveAll("./tmp_hls")
	_ = os.MkdirAll("./tmp_hls", 0755)

	CleanupIpc()

	ctx, cancel := context.WithCancel(context.Background())
	m.cancelFunc = cancel

	if encoder == "" {
		encoder = "libx264"
	}

	args := []string{
		sourceURL,
		"--o=index.m3u8",
		"--of=hls",
		GetIpcArg(),
		"--ofopts=hls_time=2,hls_segment_type=fmp4,hls_playlist_type=event",
		"--hwdec=auto-safe",
		"--ovc=" + encoder,
		"--oac=aac",
	}

	if encoder == "libx264" {
		args = append(args, "--ovcopts=preset=ultrafast,tune=zerolatency")
	}

	// Conditionally append our track and time flags
	if startTime > 0 {
		args = append(args, fmt.Sprintf("--start=%.3f", startTime))
	}
	if sid != "" {
		args = append(args, fmt.Sprintf("--sid=%s", sid))
	}
	if aid != "" {
		args = append(args, fmt.Sprintf("--aid=%s", aid))
	}

	// Pass the dynamic slice to exec.Command
	cmd := exec.Command("mpv", args...)
	cmd.Dir = "./tmp_hls"

	if err := cmd.Start(); err != nil {
		cancel()
		m.cancelFunc = nil
		m.mutex.Unlock()
		return fmt.Errorf("failed to start mpv background transcode: %w", err)
	}

	m.activeCmd = cmd
	log.Println("[MPV] Started live background HLS transcode pipeline.")
	m.mutex.Unlock()

	// Wait for the container header
	if err := m.waitForFile(ctx, filepath.Join("./tmp_hls", "init.mp4"), 45*time.Second); err != nil {
		m.StopTranscode()
		return err
	}

	// Wait for the actual video chunks to start writing!
	if err := m.waitForSegments(ctx, "./tmp_hls", 15*time.Second); err != nil {
		m.StopTranscode()
		return err
	}

	return nil
}

func (m *MpvManager) waitForFile(ctx context.Context, path string, timeout time.Duration) error {
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return fmt.Errorf("transcode stopped before %s was ready", filepath.Base(path))
		case <-timer.C:
			return fmt.Errorf("timed out waiting for %s", filepath.Base(path))
		case <-ticker.C:
			if _, err := os.Stat(path); err == nil {
				log.Printf("[MPV] Ready — %s written to disk.", filepath.Base(path))
				return nil
			}
		}
	}
}

// Scans the directory for the first encoded .m4s video segment
func (m *MpvManager) waitForSegments(ctx context.Context, dir string, timeout time.Duration) error {
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return fmt.Errorf("transcode stopped before segments were ready")
		case <-timer.C:
			return fmt.Errorf("timed out waiting for video segments")
		case <-ticker.C:
			files, _ := filepath.Glob(filepath.Join(dir, "*.m4s"))
			if len(files) > 0 {
				log.Printf("[MPV] Ready — First chunk %s written to disk.", filepath.Base(files[0]))
				return nil
			}
		}
	}
}

func (m *MpvManager) StopTranscode() {
	m.mutex.Lock()
	defer m.mutex.Unlock()
	m.stopOldProcess()
}

func (m *MpvManager) Shutdown() {
	m.StopTranscode()
}

func (m *MpvManager) stopOldProcess() {
	if m.cancelFunc != nil {
		m.cancelFunc()
		m.cancelFunc = nil
	}
	if m.activeCmd != nil && m.activeCmd.Process != nil {
		log.Println("[MPV] Stopping active background transcoder process...")
		_ = KillProcess(m.activeCmd)
		_ = m.activeCmd.Wait()
		m.activeCmd = nil
	}
}

func (m *MpvManager) GetMetadata() (*FrontendPayload, error) {
	conn, err := DialMpv()
	if err != nil {
		return nil, fmt.Errorf("failed to connect to mpv socket: %w", err)
	}
	defer conn.Close()

	reader := bufio.NewReader(conn)
	duration := getFloatProperty(conn, reader, "duration")
	tracks := getTracks(conn, reader)
	chapters := getChapters(conn, reader)

	var audioTracks []MpvTrack
	var subtitles []MpvTrack

	for _, track := range tracks {
		if track.Type == "audio" {
			audioTracks = append(audioTracks, track)
		} else if track.Type == "sub" {
			subtitles = append(subtitles, track)
		}
	}

	return &FrontendPayload{
		Duration:    duration,
		AudioTracks: audioTracks,
		Subtitles:   subtitles,
		Chapters:    chapters,
	}, nil
}
