package main

import (
	"bufio"
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
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

func (m *MpvManager) StartTranscode(sourceURL string, startTime float64, sid string, aid string, encoder string, audioEncoder string) error {
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
	if audioEncoder == "" {
		audioEncoder = "aac"
	}

	if runtime.GOOS == "linux" {
		if encoder == "h264_amf" || encoder == "h264_qsv" {
			encoder = "h264_vaapi"
		} else if encoder == "av1_amf" || encoder == "av1_qsv" {
			encoder = "av1_vaapi"
		}
	}

	args := []string{
		sourceURL,
		"--o=index.m3u8",
		"--of=hls",
		GetIpcArg(),
		"--ofopts=hls_time=2,hls_segment_type=fmp4,hls_playlist_type=event,hls_list_size=0",
		"--hwdec=auto-safe",
		"--msg-level=ffmpeg=error",
		"--ovc=" + encoder,
		"--oac=" + audioEncoder,
	}

	if encoder == "libx264" {
		args = append(args, "--ovcopts=preset=ultrafast,tune=zerolatency,g=48")
	} else if strings.Contains(encoder, "nvenc") {
		args = append(args, "--vf=format=yuv420p", "--ovcopts=preset=p2,tune=ll,g=48")
	} else if strings.Contains(encoder, "vaapi") || strings.Contains(encoder, "amf") || strings.Contains(encoder, "qsv") {
		args = append(args, "--ovcopts=g=48")
	}

	if startTime > 0 {
		args = append(args, fmt.Sprintf("--start=%.3f", startTime))
	}
	if sid != "" {
		args = append(args, fmt.Sprintf("--sid=%s", sid))
	}
	if aid != "" {
		args = append(args, fmt.Sprintf("--aid=%s", aid))
	}

	cmd := exec.Command("mpv", args...)
	cmd.Dir = "./tmp_hls"
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		cancel()
		m.cancelFunc = nil
		m.mutex.Unlock()
		return fmt.Errorf("failed to start mpv background transcode: %w", err)
	}

	m.activeCmd = cmd
	log.Println("[MPV] Started live background HLS transcode pipeline.")
	m.mutex.Unlock()

	err := m.pollForCondition(ctx, 60*time.Second, "init.mp4 was ready", func() (string, bool) {
		if _, err := os.Stat(filepath.Join("./tmp_hls", "init.mp4")); err == nil {
			return "init.mp4", true
		}
		return "", false
	})
	if err != nil {
		m.StopTranscode()
		return err
	}

	err = m.pollForCondition(ctx, 60*time.Second, "video segments were ready", func() (string, bool) {
		files, _ := filepath.Glob(filepath.Join("./tmp_hls", "*.m4s"))
		if len(files) > 0 {
			return filepath.Base(files[0]), true
		}
		return "", false
	})
	if err != nil {
		m.StopTranscode()
		return err
	}

	return nil
}

// pollForCondition checks a condition function every 250ms until it returns true or times out.
func (m *MpvManager) pollForCondition(ctx context.Context, timeout time.Duration, abortMsg string, check func() (string, bool)) error {
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return fmt.Errorf("transcode stopped before %s", abortMsg)
		case <-timer.C:
			return fmt.Errorf("timed out waiting for %s", abortMsg)
		case <-ticker.C:
			if fileName, ok := check(); ok {
				log.Printf("[MPV] Ready — %s written to disk.", fileName)
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
