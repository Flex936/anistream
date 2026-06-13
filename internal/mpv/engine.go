package mpv

// engine.go replaces manager.go entirely.
//
// Architecture change summary
// ───────────────────────────
// Old path:  torrent → HTTP /stream → mpv --stream-record → HLS segments → hls.js <video>
// New path:  torrent → HTTP /stream → mpv --wid → native OS render layer → glass Svelte UI
//
// MPV is launched with --wid=<handle> which embeds its video output directly into the
// application's native OS window. The Wails WebView (with transparent background) floats
// on top as the "glass pane". No transcoding, no HLS, no HTML5 video element.

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/exec"
	"sync"
	"time"
)

// Engine owns the lifecycle of the native MPV process embedded via --wid.
type Engine struct {
	mu           sync.Mutex
	cmd          *exec.Cmd
	cancelFunc   context.CancelFunc
	windowHandle uintptr
	windowWidth  int
	windowHeight int
}

func NewEngine() *Engine {
	log.Println("[MPV Engine] Native video engine initialised.")
	return &Engine{}
}

// SetWindowHandle stores the native OS window handle and dimensions acquired
// at startup. Must be called before any Play() invocation.
//
//   - Windows → HWND of the top-level application window
//   - Linux   → X11 XID of the GTK/X11 window
//   - macOS   → sentinel 1 (the actual NSView is created per-call in PrepareVideoSurface)
func (e *Engine) SetWindowHandle(handle uintptr, width, height int) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.windowHandle = handle
	e.windowWidth = width
	e.windowHeight = height
	log.Printf("[MPV Engine] Window handle registered: 0x%x  dimensions: %dx%d",
		handle, width, height)
}

// Play tears down any existing MPV instance, prepares a native video surface in
// the OS window, then starts a new MPV process with --wid pointing at that surface.
//
// streamURL is the HTTP URL of the torrent byte-stream served by the local
// /stream endpoint. MPV requests it directly — no HLS transcoding is performed.
func (e *Engine) Play(streamURL string, startTime float64) error {
	e.mu.Lock()
	defer e.mu.Unlock()

	// Tear down any previous instance cleanly before touching the IPC socket.
	e.stopLocked()
	CleanupIpc()

	if e.windowHandle == 0 {
		return fmt.Errorf(
			"[MPV Engine] native window handle was not acquired during startup; " +
				"check AcquireWindowHandle() for your platform")
	}

	// PrepareVideoSurface is platform-specific (see handle_*.go):
	//   Windows → creates a child HWND at HWND_BOTTOM (behind WebView2 sibling)
	//   macOS   → creates an NSView subview below WKWebView
	//   Linux   → returns the X11 XID unchanged (MPV creates its own child window)
	surface, err := PrepareVideoSurface(e.windowHandle, e.windowWidth, e.windowHeight)
	if err != nil {
		return fmt.Errorf("prepare video surface: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	e.cancelFunc = cancel

	args := buildMPVArgs(streamURL, surface, startTime)

	// exec.CommandContext: when cancel() is called, the OS sends SIGKILL (Unix)
	// or TerminateProcess (Windows) to the mpv process — killProcess() also does
	// this explicitly so shutdown is deterministic even if ctx isn't cancelled.
	cmd := exec.CommandContext(ctx, "mpv", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Start(); err != nil {
		cancel()
		e.cancelFunc = nil
		return fmt.Errorf("start mpv: %w", err)
	}

	e.cmd = cmd
	log.Printf("[MPV Engine] Started PID=%d  wid=0x%x  url=%s",
		cmd.Process.Pid, surface, streamURL)

	// Reap the process in the background so Wait() never blocks Stop().
	go func() {
		if err := cmd.Wait(); err != nil {
			log.Printf("[MPV Engine] Process exited: %v", err)
		} else {
			log.Println("[MPV Engine] Process exited cleanly.")
		}
	}()

	return nil
}

// WaitReady polls the IPC socket until MPV accepts connections or the timeout
// elapses. Call this after Play() before exposing controls to the frontend.
func (e *Engine) WaitReady(timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		conn, err := DialMpv()
		if err == nil {
			conn.Close()
			return nil
		}
		time.Sleep(150 * time.Millisecond)
	}
	return fmt.Errorf("MPV IPC socket not ready after %v", timeout)
}

// Stop cancels the active context and kills the MPV process.
// Safe to call when no process is active.
func (e *Engine) Stop() {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.stopLocked()
}

func (e *Engine) stopLocked() {
	if e.cancelFunc != nil {
		e.cancelFunc()
		e.cancelFunc = nil
	}
	if e.cmd != nil && e.cmd.Process != nil {
		log.Println("[MPV Engine] Killing process.")
		_ = killProcess(e.cmd)

		// REMOVED: e.cmd.Wait()
		// We MUST NOT call Wait() here because the background reaper
		// goroutine in Play() is already waiting on it.
		// Calling Wait() twice causes a permanent deadlock!

		e.cmd = nil
	}
}

// ── IPC helpers ───────────────────────────────────────────────────────────────

// sendIPC opens a fresh connection to the IPC socket, writes one command, then
// closes. Opening per-command avoids shared-state race conditions and keeps the
// implementation simple for the fire-and-forget control commands used here.
func (e *Engine) sendIPC(command []interface{}) error {
	conn, err := DialMpv()
	if err != nil {
		return fmt.Errorf("mpv IPC unavailable: %w", err)
	}
	defer conn.Close()
	_ = conn.SetWriteDeadline(time.Now().Add(2 * time.Second))

	req := ipcCmd{Command: command}
	b, err := json.Marshal(req)
	if err != nil {
		return err
	}
	_, err = conn.Write(append(b, '\n'))
	return err
}

// ── Playback control (Wails-bound via app.go) ─────────────────────────────────

func (e *Engine) TogglePause() error {
	return e.sendIPC([]interface{}{"cycle", "pause"})
}

func (e *Engine) Pause() error {
	return e.sendIPC([]interface{}{"set_property", "pause", true})
}

func (e *Engine) Resume() error {
	return e.sendIPC([]interface{}{"set_property", "pause", false})
}

// Seek performs an absolute seek to the given timestamp in seconds.
func (e *Engine) Seek(seconds float64) error {
	return e.sendIPC([]interface{}{"seek", seconds, "absolute"})
}

// SetVolume sets playback volume. vol must be in MPV's native 0–100 range.
func (e *Engine) SetVolume(vol int) error {
	return e.sendIPC([]interface{}{"set_property", "volume", vol})
}

// ToggleMute cycles MPV's mute property so the pre-mute volume level is preserved.
func (e *Engine) ToggleMute() error {
	return e.sendIPC([]interface{}{"cycle", "mute"})
}

// SetSubtitle selects a subtitle track by ID string, or disables subtitles
// entirely when sid == "no".  No MPV restart is required — pure IPC.
func (e *Engine) SetSubtitle(sid string) error {
	if sid == "no" {
		return e.sendIPC([]interface{}{"set_property", "sub-visibility", false})
	}
	_ = e.sendIPC([]interface{}{"set_property", "sub-visibility", true})
	return e.sendIPC([]interface{}{"set_property", "sid", sid})
}

// SetAudioTrack selects an audio track by ID string. No MPV restart required.
func (e *Engine) SetAudioTrack(aid string) error {
	return e.sendIPC([]interface{}{"set_property", "aid", aid})
}

// SendCommand is a generic escape hatch for arbitrary IPC commands.
func (e *Engine) SendCommand(command []interface{}) error {
	return e.sendIPC(command)
}

// ── State polling (Wails-bound via app.go) ────────────────────────────────────

// GetMetadata opens a single IPC connection, fetches all live playback state
// in one sequential sweep, then closes. Called every ~500 ms by the frontend.
func (e *Engine) GetMetadata() (*FrontendPayload, error) {
	conn, err := DialMpv()
	if err != nil {
		return nil, fmt.Errorf("connect to mpv socket: %w", err)
	}
	defer conn.Close()
	// Hard deadline so a hung MPV doesn't block the frontend poll.
	_ = conn.SetDeadline(time.Now().Add(2 * time.Second))

	r := bufio.NewReader(conn)

	duration := getFloatProperty(conn, r, "duration")
	timePos := getFloatProperty(conn, r, "time-pos")
	paused := getBoolProperty(conn, r, "pause")
	volume := getFloatProperty(conn, r, "volume")
	muted := getBoolProperty(conn, r, "mute")
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
		TimePos:     timePos,
		Paused:      paused,
		Volume:      volume,
		Muted:       muted,
		AudioTracks: audio,
		Subtitles:   subs,
		Chapters:    chapters,
	}, nil
}

// ── MPV argument builder ──────────────────────────────────────────────────────

func buildMPVArgs(url string, wid uintptr, startTime float64) []string {
	args := []string{
		url,
		// Core embedding: attach to the prepared native surface.
		fmt.Sprintf("--wid=%d", wid),
		// IPC: all UI interactions go through the socket.
		GetIpcArg(),

		// Visual: no MPV chrome — the Svelte glass pane is our UI.
		"--no-border",
		"--no-osd-bar",
		"--osd-level=0",

		// Process behaviour.
		"--really-quiet",
		"--no-terminal",
		"--keep-open=yes", // hold last frame; don't exit at EOF
		"--idle=yes",      // accept IPC commands before a file is loaded
		"--force-window=yes",

		// Decoding: prefer GPU decode paths; fall back to SW silently.
		"--hwdec=auto-safe",

		// Input: the glass UI owns all pointer and keyboard interaction.
		"--no-input-default-bindings",
		"--input-cursor=no",
		"--cursor-autohide=no",
	}

	if startTime > 0 {
		args = append(args, fmt.Sprintf("--start=%.3f", startTime))
	}

	return args
}

// killProcess safely terminates the MPV command if it is running.
func killProcess(cmd *exec.Cmd) error {
	if cmd != nil && cmd.Process != nil {
		return cmd.Process.Kill()
	}
	return nil
}
