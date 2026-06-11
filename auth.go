package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/wailsapp/wails/v2/pkg/runtime"

	"anistream/internal/config"
)

// LoginWithAniList opens the system browser to the AniList OAuth page, then
// spins up a short-lived local server to capture the returned bearer token.
func (a *App) LoginWithAniList() (string, error) {
	const clientID = "43011"

	// Buffered channels prevent the HTTP handler goroutines from blocking if
	// the select has already resolved on the other channel.
	tokenCh := make(chan string, 1)
	errCh := make(chan error, 1)

	mux := http.NewServeMux()
	srv := &http.Server{Addr: ":3456", Handler: mux}

	// Step 1: browser lands here, extracts the hash fragment via JS, POSTs to /store.
	mux.HandleFunc("/callback", func(w http.ResponseWriter, r *http.Request) {
		const html = `<html><body style="font-family:sans-serif;text-align:center;
			margin-top:50px;background:#0a0a0c;color:#f1f5f9;">
			<h2>Authenticating…</h2>
			<script>
				const hash = window.location.hash.substring(1);
				fetch('/store', {method:'POST', body:hash})
					.then(() => {
						document.body.innerHTML =
							"<h2 style='color:#6366f1'>Success!</h2>" +
							"<p>You can close this window and return to AniStream.</p>";
					})
					.catch(() => {
						document.body.innerHTML =
							"<h2 style='color:#f87171'>Authentication Failed</h2>";
					});
			</script></body></html>`
		_, _ = w.Write([]byte(html))
	})

	// Step 2: JS POSTs the URL-encoded fragment; we extract access_token.
	mux.HandleFunc("/store", func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		params, _ := url.ParseQuery(string(body))
		if token := params.Get("access_token"); token != "" {
			tokenCh <- token
		} else {
			errCh <- fmt.Errorf("no access_token in OAuth callback")
		}
		w.WriteHeader(http.StatusOK)
	})

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errCh <- err
		}
	}()

	runtime.BrowserOpenURL(a.getCtx(), fmt.Sprintf(
		"https://anilist.co/api/v2/oauth/authorize?client_id=%s&response_type=token", clientID,
	))

	// Always shut down with a fresh context. The Wails app context (a.getCtx())
	// may already be cancelled when shutdown() runs, which would make
	// srv.Shutdown hang indefinitely.
	shutdownSrv := func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(ctx)
	}

	select {
	case token := <-tokenCh:
		cfg := config.Load()
		cfg.AniListToken = token
		if err := config.Save(cfg); err != nil {
			shutdownSrv()
			return "", fmt.Errorf("save config: %w", err)
		}
		// Update the in-memory client immediately — no disk read on next request.
		a.al.SetToken(token)
		shutdownSrv()
		return "success", nil

	case err := <-errCh:
		shutdownSrv()
		return "", err
	}
}

// Logout clears the persisted token and resets all AniList auth state.
func (a *App) Logout() {
	cfg := config.Load()
	cfg.AniListToken = ""
	_ = config.Save(cfg)
	a.al.ClearToken()
}
