package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/wailsapp/wails/v2/pkg/runtime"

	"anistream/internal/anilist"
	"anistream/internal/config"
	"anistream/internal/mpv"
	"anistream/internal/scraper"
	"anistream/internal/torrent"
)

// App is the single struct Wails binds to the frontend.
// HLS / transcoding infrastructure has been removed entirely.
// The video path is now: torrent → /stream HTTP → native MPV via --wid.
type App struct {
	ctx    context.Context
	ctxMu  sync.RWMutex
	server *http.Server // serves /stream only (no /hls/ anymore)

	mpv        *mpv.Engine
	torrent    *torrent.Manager
	al         *anilist.Client
	scraper    *scraper.Client
	fullscreen bool // track fullscreen state for toggle
}

func NewApp() *App {
	httpClient := &http.Client{Timeout: 15 * time.Second}
	cfg := config.Load()

	tm, err := torrent.NewManager()
	if err != nil {
		log.Fatalf("[App] Cannot create torrent manager: %v", err)
	}

	app := &App{
		ctx:     context.Background(),
		mpv:     mpv.NewEngine(),
		torrent: tm,
		al:      anilist.NewClient(httpClient, cfg.AniListToken),
		scraper: scraper.NewClient(httpClient),
	}

	app.server = app.buildHTTPServer()
	go func() {
		log.Println("[Server] HTTP server listening on :8080")
		if err := app.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("[Server] Exited: %v", err)
		}
	}()

	return app
}

// ── Wails lifecycle ──────────────────────────────────────────────────────────

func (a *App) startup(ctx context.Context) {
	a.ctxMu.Lock()
	a.ctx = ctx
	a.ctxMu.Unlock()

	cfg := config.Load()
	a.mpv.SetInternalPlayback(cfg.InternalPlayback)

	// Only acquire the native OS window handle when internal playback is enabled.
	// External mode doesn't need --wid embedding.
	if cfg.InternalPlayback {
		handle, err := mpv.AcquireWindowHandle()
		if err != nil {
			log.Printf("[App] WARNING: could not acquire native window handle: %v", err)
			log.Printf("[App] Native MPV embedding unavailable; streaming will fail.")
			return
		}
		a.mpv.SetWindowHandle(handle, cfg.Width, cfg.Height)
	} else {
		log.Println("[App] External playback mode — skipping window handle acquisition.")
	}
}

func (a *App) shutdown(_ context.Context) {
	log.Println("[App] Shutdown initiated.")

	// NUCLEAR OPTION: Guarantee the app completely dies in exactly 1.5 seconds,
	// no matter what deadlocks are happening inside the torrent engine or MPV.
	go func() {
		time.Sleep(1500 * time.Millisecond)
		log.Println("[App] Force quitting...")
		os.Exit(0)
	}()

	// 1. Instantly snap the HTTP server
	if a.server != nil {
		_ = a.server.Close()
	}

	// 2. Kill MPV (which no longer deadlocks thanks to the engine.go fix)
	a.StopStream()

	// 3. Politely ask the torrent engine to close
	if a.torrent != nil {
		a.torrent.Close()
	}

	log.Println("[App] Shutdown complete.")
}

func (a *App) getCtx() context.Context {
	a.ctxMu.RLock()
	defer a.ctxMu.RUnlock()
	return a.ctx
}

// ── HTTP server ──────────────────────────────────────────────────────────────
// The server now has a single purpose: serve the active torrent file as a
// seekable HTTP byte-stream that MPV reads directly.  No HLS file server needed.

func (a *App) buildHTTPServer() *http.Server {
	mux := http.NewServeMux()
	mux.HandleFunc("/stream", a.streamHandler)
	return &http.Server{Addr: ":8080", Handler: mux}
}

func (a *App) streamHandler(w http.ResponseWriter, r *http.Request) {
	reader, displayPath, err := a.torrent.NewActiveFileReader()
	if err != nil {
		http.Error(w, "no active stream", http.StatusNotFound)
		return
	}
	defer reader.Close()
	w.Header().Set("Access-Control-Allow-Origin", "*")
	http.ServeContent(w, r, displayPath, time.Time{}, reader)
}

// ── Stream control (Wails-bound) ─────────────────────────────────────────────

// StreamTorrent starts the torrent download, then launches native MPV pointing
// at the local HTTP byte-stream.  Returns when MPV's IPC socket is ready so the
// frontend knows it can immediately start polling for metadata.
//
// The return type is now error (no URL string) — the frontend no longer needs an
// HLS manifest URL; it controls playback through the IPC methods below.
func (a *App) StreamTorrent(magnetLink string) error {
	if err := a.torrent.Stream(magnetLink); err != nil {
		return err
	}

	// MPV reads the torrent data via the local streaming HTTP endpoint.
	// No HLS transcoding; MPV handles buffering and seeks natively.
	if err := a.mpv.Play("http://localhost:8080/stream", 0); err != nil {
		a.torrent.Stop()
		return fmt.Errorf("MPV failed to start: %w", err)
	}

	// Block until the IPC socket is ready so the frontend can poll immediately.
	if err := a.mpv.WaitReady(15 * time.Second); err != nil {
		a.StopStream()
		return fmt.Errorf("MPV IPC not ready: %w", err)
	}

	return nil
}

// StopStream is the single authoritative cleanup path.
// Safe to call when no stream is active.
func (a *App) StopStream() {
	a.mpv.Stop()
	a.torrent.Stop()
}

// ── MPV playback control (Wails-bound) ───────────────────────────────────────
// These methods are thin wrappers that expose the Engine's IPC commands to the
// Svelte glass UI via Wails' auto-generated TypeScript bindings.

// ToggleMPV cycles MPV between playing and paused.
func (a *App) ToggleMPV() error { return a.mpv.TogglePause() }

// PauseMPV explicitly pauses playback.
func (a *App) PauseMPV() error { return a.mpv.Pause() }

// PlayMPV explicitly resumes playback.
func (a *App) PlayMPV() error { return a.mpv.Resume() }

// SeekMPV seeks to an absolute position in seconds.
func (a *App) SeekMPV(seconds float64) error { return a.mpv.Seek(seconds) }

// SetVolumeMPV sets the playback volume (0–100).
func (a *App) SetVolumeMPV(vol int) error { return a.mpv.SetVolume(vol) }

// ToggleMuteMPV cycles MPV's mute state, preserving the volume level.
func (a *App) ToggleMuteMPV() error { return a.mpv.ToggleMute() }

// SetSubtitleMPV selects a subtitle track by ID string, or disables subtitles
// when sid == "no".  No stream restart is required — pure IPC.
func (a *App) SetSubtitleMPV(sid string) error { return a.mpv.SetSubtitle(sid) }

// SetAudioTrackMPV selects an audio track by ID string. No restart required.
func (a *App) SetAudioTrackMPV(aid string) error { return a.mpv.SetAudioTrack(aid) }

// GetMpvMetadata polls MPV for the current playback state.
// Called by the frontend on a ~500 ms interval to keep the glass UI in sync.
func (a *App) GetMpvMetadata() (*mpv.FrontendPayload, error) {
	return a.mpv.GetMetadata()
}

// SendMpvCommand forwards an arbitrary JSON IPC command array to MPV.
// Kept as a generic escape hatch for the frontend.
func (a *App) SendMpvCommand(command []interface{}) error {
	return a.mpv.SendCommand(command)
}

// ToggleFullscreen toggles OS-level window fullscreen via Wails runtime.
func (a *App) ToggleFullscreen() {
	ctx := a.getCtx()
	a.fullscreen = !a.fullscreen
	if a.fullscreen {
		runtime.WindowFullscreen(ctx)
	} else {
		runtime.WindowUnfullscreen(ctx)
	}
}

// ── AniList (Wails-bound) ────────────────────────────────────────────────────

func (a *App) IsLoggedIn() bool {
	return a.al.IsLoggedIn()
}

func (a *App) SearchAnime(query string) ([]anilist.Anime, error) {
	return a.al.Search(a.getCtx(), query, config.Load().FilterEcchi)
}

func (a *App) GetTrendingAnime() ([]anilist.Anime, error) {
	return a.al.Trending(a.getCtx(), config.Load().FilterEcchi)
}

func (a *App) GetAnimeProgress(animeID int) (int, error) {
	return a.al.Progress(a.getCtx(), animeID)
}

func (a *App) UpdateAnimeProgress(animeID int, episode int) error {
	return a.al.UpdateProgress(a.getCtx(), animeID, episode)
}

func (a *App) GetUserWatchlist() ([]anilist.MediaList, error) {
	return a.al.Watchlist(a.getCtx())
}

func (a *App) GetSeasonalAnime() ([]anilist.Anime, error) {
	return a.al.Seasonal(a.getCtx(), config.Load().FilterEcchi)
}

// ── Scraper (Wails-bound) ────────────────────────────────────────────────────

func (a *App) GetEpisodeTorrents(animeTitle string, episodeNumber int) ([]scraper.TorrentResult, error) {
	return a.scraper.GetEpisodeTorrents(animeTitle, episodeNumber)
}

// ── Config (Wails-bound) ─────────────────────────────────────────────────────

func (a *App) GetResolution() config.Resolution {
	cfg := config.Load()
	return config.Resolution{Width: cfg.Width, Height: cfg.Height}
}

func (a *App) UpdateResolution(width, height int) error {
	cfg := config.Load()
	cfg.Width = width
	cfg.Height = height
	return config.Save(cfg)
}

func (a *App) GetEcchiFilter() bool { return config.Load().FilterEcchi }

func (a *App) UpdateEcchiFilter(filter bool) error {
	cfg := config.Load()
	cfg.FilterEcchi = filter
	return config.Save(cfg)
}

// GetInternalPlayback returns the current internal playback setting.
func (a *App) GetInternalPlayback() bool { return config.Load().InternalPlayback }

// UpdateInternalPlayback persists the internal playback toggle.
// Requires an app restart to take effect (window handle acquisition happens at startup).
func (a *App) UpdateInternalPlayback(enabled bool) error {
	cfg := config.Load()
	cfg.InternalPlayback = enabled
	return config.Save(cfg)
}

func (a *App) GetUpscaleMethod() string { return config.Load().Upscaling }

func (a *App) UpdateUpscaleMethod(method string) error {
	cfg := config.Load()
	cfg.Upscaling = method
	return config.Save(cfg)
}

func (a *App) GetUpscaleResolution() config.Resolution {
	return config.Load().UpscaleResolution
}

func (a *App) UpdateUpscaleResolution(res config.Resolution) error {
	cfg := config.Load()
	cfg.UpscaleResolution = res
	return config.Save(cfg)
}

func (a *App) OpenDirectoryDialog() (string, error) {
	return runtime.OpenDirectoryDialog(a.ctx, runtime.OpenDialogOptions{
		Title: "Select Download Destination",
	})
}

func (a *App) UpdateDownloadFolder(dir string) error {
	if dir == "" {
		return nil
	}
	cfg := config.Load()
	cfg.DownloadDir = dir
	if err := config.Save(cfg); err != nil {
		return err
	}

	// Safely clean up any active stream and delete the old tmp folders
	// BEFORE we update the underlying paths.
	a.StopStream()

	a.torrent.SetDataDir(filepath.Join(dir, "tmp_downloads"))
	return nil
}

func (a *App) GetFolder() string {
	return config.Load().DownloadDir
}
