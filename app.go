package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"anistream/internal/anilist"
	"anistream/internal/config"
	"anistream/internal/mpv"
	"anistream/internal/scraper"
	"anistream/internal/torrent"
)

// App is the single struct Wails binds to the frontend.
// It is a thin orchestration layer; all domain logic lives in internal packages.
type App struct {
	// ctx is the application lifetime context provided by Wails in startup().
	// Initialised to context.Background() so pre-startup HTTP calls don't panic.
	ctx    context.Context
	ctxMu  sync.RWMutex
	server *http.Server

	mpv     *mpv.Manager
	torrent *torrent.Manager
	al      *anilist.Client
	scraper *scraper.Client
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
		mpv:     mpv.NewManager(),
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
}

func (a *App) shutdown(_ context.Context) {
	log.Println("[App] Shutdown initiated.")

	// 1. Stop active stream: drops torrent + deletes tmp_downloads.
	a.StopStream()

	// 2. Close the torrent client permanently.
	a.torrent.Close()

	// 3. Delete any remaining HLS segments (belt-and-suspenders; StopStream
	//    already removes the dir, but a crash mid-stream could leave orphans).
	_ = os.RemoveAll(mpv.HLSOutputDir)

	// 4. Gracefully drain in-flight HTTP requests.
	shutCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := a.server.Shutdown(shutCtx); err != nil {
		log.Printf("[Server] Shutdown error: %v", err)
	}

	log.Println("[App] Shutdown complete.")
}

func (a *App) getCtx() context.Context {
	a.ctxMu.RLock()
	defer a.ctxMu.RUnlock()
	return a.ctx
}

// ── HTTP server ──────────────────────────────────────────────────────────────

func (a *App) buildHTTPServer() *http.Server {
	mux := http.NewServeMux()
	mux.HandleFunc("/stream", a.streamHandler)
	mux.HandleFunc("/anime-data", a.metadataHandler)

	fileServer := http.FileServer(http.Dir(mpv.HLSOutputDir))
	hlsStripped := http.StripPrefix("/hls/", fileServer)
	mux.Handle("/hls/", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Range, Content-Type")
		w.Header().Set("Access-Control-Expose-Headers", "Content-Length, Content-Range")
		w.Header().Set("Cache-Control", "no-cache, no-store, must-revalidate")
		w.Header().Set("Pragma", "no-cache")
		w.Header().Set("Expires", "0")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusOK)
			return
		}
		hlsStripped.ServeHTTP(w, r)
	}))

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

func (a *App) metadataHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}
	payload, err := a.mpv.GetMetadata()
	if err != nil {
		http.Error(w, err.Error(), http.StatusServiceUnavailable)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(payload)
}

// ── Stream control (Wails-bound) ─────────────────────────────────────────────

func (a *App) StreamTorrent(magnetLink string) (string, error) {
	cfg := config.Load()
	sid := "auto"
	aid := "auto"
	encoder, audioEncoder := mpv.ResolveEncoders(cfg, sid)

	if err := a.torrent.Stream(magnetLink); err != nil {
		return "", err
	}

	if err := a.mpv.StartTranscode("http://localhost:8080/stream", 0, sid, aid, encoder, audioEncoder); err != nil {
		// Transcode failed: clean up the torrent we just set up.
		a.StopStream()
		return "", fmt.Errorf("transcoder failed to initialise: %w", err)
	}

	return "http://localhost:8080/hls/index.m3u8", nil
}

// StopStream is the single authoritative cleanup path for an active stream.
// It is safe to call when no stream is active.
func (a *App) StopStream() {
	a.torrent.Stop()                   // cancel context + drop torrent + delete tmp_downloads
	a.mpv.Stop()                       // cancel context + kill mpv process
	_ = os.RemoveAll(mpv.HLSOutputDir) // delete live HLS segments
}

func (a *App) ChangeTrackAndRestart(timeInSeconds float64, sid string, aid string) error {
	if _, _, err := a.torrent.NewActiveFileReader(); err != nil {
		return fmt.Errorf("no active torrent stream to restart")
	}
	cfg := config.Load()
	encoder, audioEncoder := mpv.ResolveEncoders(cfg, sid)
	return a.mpv.StartTranscode(
		"http://localhost:8080/stream", timeInSeconds, sid, aid, encoder, audioEncoder,
	)
}

// ── MPV (Wails-bound) ────────────────────────────────────────────────────────

func (a *App) GetMpvMetadata() (*mpv.FrontendPayload, error) {
	return a.mpv.GetMetadata()
}

func (a *App) SendMpvCommand(command []interface{}) error {
	conn, err := mpv.DialMpv()
	if err != nil {
		return err
	}
	defer conn.Close()
	mpv.SendCommand(conn, command)
	return nil
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

func (a *App) GetTranscoder() string {
	cfg := config.Load()
	if cfg.Encoder == "" {
		return "libx264"
	}
	return cfg.Encoder
}

func (a *App) UpdateTranscoder(encoder string) error {
	cfg := config.Load()
	cfg.Encoder = encoder
	return config.Save(cfg)
}

func (a *App) GetAV1Enabled() bool { return config.Load().EnableAV1 }

func (a *App) UpdateAV1Enabled(enabled bool) error {
	cfg := config.Load()
	cfg.EnableAV1 = enabled
	return config.Save(cfg)
}

func (a *App) GetOpusEnabled() bool { return config.Load().EnableOpus }

func (a *App) UpdateOpusEnabled(enabled bool) error {
	cfg := config.Load()
	cfg.EnableOpus = enabled
	return config.Save(cfg)
}
