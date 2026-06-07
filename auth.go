package main

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// LoginWithAniList opens the browser and starts a temporary local server to catch the token.
func (a *App) LoginWithAniList() (string, error) {
	clientID := "43011"

	// Buffered so HTTP handler goroutines never block if the select has
	// already resolved on the other channel.
	tokenChan := make(chan string, 1)
	errChan := make(chan error, 1)

	m := http.NewServeMux()
	srv := &http.Server{Addr: ":3456", Handler: m}

	m.HandleFunc("/callback", func(w http.ResponseWriter, r *http.Request) {
		html := `<html><body style="font-family: sans-serif; text-align: center; margin-top: 50px; background-color: #0a0a0c; color: #f1f5f9;">
			<h2>Authenticating...</h2>
			<script>
				const hash = window.location.hash.substring(1);
				fetch('/store', { method: 'POST', body: hash }).then(() => {
					document.body.innerHTML = "<h2 style='color: #6366f1;'>Success!</h2><p>You can close this window and return to AniStream.</p>";
				}).catch(() => {
					document.body.innerHTML = "<h2 style='color: #f87171;'>Authentication Failed</h2>";
				});
			</script>
		</body></html>`
		w.Write([]byte(html))
	})

	m.HandleFunc("/store", func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		params, _ := url.ParseQuery(string(body))
		token := params.Get("access_token")
		if token != "" {
			tokenChan <- token
		} else {
			errChan <- fmt.Errorf("no token found in redirect")
		}
		w.WriteHeader(http.StatusOK)
	})

	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errChan <- err
		}
	}()

	runtime.BrowserOpenURL(a.ctx, fmt.Sprintf(
		"https://anilist.co/api/v2/oauth/authorize?client_id=%s&response_type=token", clientID,
	))

	// Always shut down with a fresh context. Using a.ctx is unsafe because
	// Wails may cancel it during app shutdown before Shutdown() finishes.
	shutdown := func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		srv.Shutdown(ctx)
	}

	select {
	case token := <-tokenChan:
		cfg := LoadConfig()
		cfg.AniListToken = token
		if err := SaveConfig(cfg); err != nil {
			shutdown()
			return "", fmt.Errorf("failed to save config: %w", err)
		}
		// Update in-memory cache immediately so all subsequent API calls
		// see the new token without another disk read.
		a.mu.Lock()
		a.aniListToken = token
		a.viewerID = 0 // reset in case the user switched accounts
		a.mu.Unlock()
		shutdown()
		return "success", nil

	case err := <-errChan:
		shutdown()
		return "", err
	}
}

// IsLoggedIn reads from the in-memory cache — no disk I/O.
func (a *App) IsLoggedIn() bool {
	a.mu.RLock()
	defer a.mu.RUnlock()
	return a.aniListToken != ""
}

// Logout clears both the persisted token and every related in-memory field.
func (a *App) Logout() {
	cfg := LoadConfig()
	cfg.AniListToken = ""
	SaveConfig(cfg)
	a.mu.Lock()
	a.aniListToken = ""
	a.viewerID = 0 // must be invalidated so a future login re-fetches it
	a.mu.Unlock()
}
