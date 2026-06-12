package mpv

import (
	"bufio"
	"context"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	goruntime "runtime"
	"strings"
	"sync"
	"time"

	"anistream/internal/config"
)

// HLSOutputDir is the working directory for live HLS segments.
// Exported so that app.go can delete it during StopStream / shutdown.
const HLSOutputDir = "./tmp_hls"

// Manager owns the lifecycle of the background mpv transcode process.
type Manager struct {
	mu         sync.Mutex
	activeCmd  *exec.Cmd
	cancelFunc context.CancelFunc
}

func NewManager() *Manager {
	log.Println("[MPV] Transcoder engine initialised.")
	return &Manager{}
}

// ResolveEncoders picks the correct video/audio encoder pair for the current
// platform and config. The sid parameter is reserved: once copy-mode is
// implemented, any sid value other than "no" will veto copy and force a full
// transcode to prevent the HLS/fMP4 muxer from receiving ASS subtitle tracks.
func ResolveEncoders(cfg config.AppConfig, sid string) (videoEncoder, audioEncoder string) {
	_ = sid // reserved for copy-mode veto — do not remove

	audioEncoder = "aac"
	if cfg.EnableOpus {
		audioEncoder = "libopus"
	}

	videoEncoder = cfg.Encoder
	if videoEncoder == "" {
		videoEncoder = "libx264"
	}

	// Linux: remap Windows/AMD GPU encoder strings to their VAAPI equivalents.
	if goruntime.GOOS == "linux" {
		switch videoEncoder {
		case "h264_amf", "h264_qsv":
			videoEncoder = "h264_vaapi"
		case "av1_amf", "av1_qsv":
			videoEncoder = "av1_vaapi"
		}
	}

	return videoEncoder, audioEncoder
}

// StartTranscode clears any previous HLS output, starts a new mpv encode
// pipeline, and blocks until the first init segment and at least one media
// segment have appeared on disk (i.e. the stream is ready for playback).
func (m *Manager) StartTranscode(
	sourceURL string,
	startTime float64,
	sid, aid, encoder, audioEncoder string,
	display config.Resolution,
	upscaler string,
) error {
	m.mu.Lock()
	m.stopLocked() // tear down any existing process before touching the output dir

	if err := os.RemoveAll(HLSOutputDir); err != nil {
		log.Printf("[MPV] Warning: could not remove old HLS dir: %v", err)
	}
	if err := os.MkdirAll(HLSOutputDir, 0755); err != nil {
		m.mu.Unlock()
		return fmt.Errorf("create HLS output dir: %w", err)
	}

	CleanupIpc()

	if encoder == "" {
		encoder = "libx264"
	}
	if audioEncoder == "" {
		audioEncoder = "aac"
	}

	ctx, cancel := context.WithCancel(context.Background())
	m.cancelFunc = cancel

	args := buildArgs(sourceURL, startTime, sid, aid, encoder, audioEncoder, display, upscaler)
	cmd := exec.Command("mpv", args...)
	cmd.Dir = HLSOutputDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		cancel()
		m.cancelFunc = nil
		m.mu.Unlock()
		return fmt.Errorf("start mpv: %w", err)
	}

	m.activeCmd = cmd
	log.Println("[MPV] Background HLS transcode started.")
	m.mu.Unlock()

	// Poll outside the lock so Stop() can interrupt cleanly via ctx cancellation.
	if err := m.poll(ctx, 60*time.Second, "init.mp4", func() bool {
		_, err := os.Stat(filepath.Join(HLSOutputDir, "init.mp4"))
		return err == nil
	}); err != nil {
		m.Stop()
		return err
	}

	if err := m.poll(ctx, 60*time.Second, "first .m4s segment", func() bool {
		segs, _ := filepath.Glob(filepath.Join(HLSOutputDir, "*.m4s"))
		return len(segs) > 0
	}); err != nil {
		m.Stop()
		return err
	}

	return nil
}

// Stop cancels the active encode context and kills the mpv process.
// Safe to call concurrently and multiple times.
func (m *Manager) Stop() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.stopLocked()
}

// stopLocked is the internal implementation; caller must hold m.mu.
func (m *Manager) stopLocked() {
	if m.cancelFunc != nil {
		m.cancelFunc()
		m.cancelFunc = nil
	}
	if m.activeCmd != nil && m.activeCmd.Process != nil {
		log.Println("[MPV] Stopping transcode process.")
		_ = killProcess(m.activeCmd)
		_ = m.activeCmd.Wait()
		m.activeCmd = nil
	}
}

// poll checks condition every 250 ms until it returns true, the context is
// cancelled, or the timeout elapses.
func (m *Manager) poll(ctx context.Context, timeout time.Duration, label string, condition func() bool) error {
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	ticker := time.NewTicker(250 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return fmt.Errorf("transcode stopped before %s was ready", label)
		case <-timer.C:
			return fmt.Errorf("timed out waiting for %s", label)
		case <-ticker.C:
			if condition() {
				log.Printf("[MPV] Ready — %s present on disk.", label)
				return nil
			}
		}
	}
}

// GetMetadata dials the mpv IPC socket and returns track/chapter/duration data.
func (m *Manager) GetMetadata() (*FrontendPayload, error) {
	conn, err := DialMpv()
	if err != nil {
		return nil, fmt.Errorf("connect to mpv socket: %w", err)
	}
	defer conn.Close()

	r := bufio.NewReader(conn)
	duration := getFloatProperty(conn, r, "duration")
	tracks := getTracks(conn, r)
	chapters := getChapters(conn, r)

	var audio, subs []MpvTrack
	for _, t := range tracks {
		switch t.Type {
		case "audio":
			audio = append(audio, t)
		case "sub":
			subs = append(subs, t)
		}
	}

	return &FrontendPayload{
		Duration:    duration,
		AudioTracks: audio,
		Subtitles:   subs,
		Chapters:    chapters,
	}, nil
}

func buildArgs(sourceURL string, startTime float64, sid, aid, encoder, audioEncoder string, display config.Resolution, upscaler string) []string {
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

	if upscaler != "" && display.Height > 0 && display.Width > 0 {
		args = append(args, fmt.Sprintf("--vf-add=libplacebo=w=%d:h=%d:upscaler=%s", display.Width, display.Height, upscaler))
	}

	switch {
	case encoder == "libx264":
		args = append(args, "--ovcopts=preset=ultrafast,tune=zerolatency,g=48")
	case strings.Contains(encoder, "nvenc"):
		args = append(args, "--vf=format=yuv420p", "--ovcopts=preset=p2,tune=ll,g=48")
	case strings.Contains(encoder, "vaapi"),
		strings.Contains(encoder, "amf"),
		strings.Contains(encoder, "qsv"):
		args = append(args, "--ovcopts=g=48")
	}

	if startTime > 0 {
		args = append(args, fmt.Sprintf("--start=%.3f", startTime))
	}
	if sid != "" {
		args = append(args, "--sid="+sid)
	}
	if aid != "" {
		args = append(args, "--aid="+aid)
	}

	return args
}
