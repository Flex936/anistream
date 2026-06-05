package main

import (
	"fmt"
	"io"
	"net/http"
	"net/url"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// LoginWithAniList opens the browser and starts a temporary local server to catch the token
func (a *App) LoginWithAniList() (string, error) {
	clientID := "43011"

	tokenChan := make(chan string)
	errChan := make(chan error)

	m := http.NewServeMux()
	srv := &http.Server{Addr: ":3456", Handler: m}

	// Catch the redirect from AniList and serve a script to grab the URL Hash
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

	// The Javascript above POSTs the token here so Go can save it
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

	// Start the server in the background
	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errChan <- err
		}
	}()

	// Tell Wails to open the user's OS browser
	authURL := fmt.Sprintf("https://anilist.co/api/v2/oauth/authorize?client_id=%s&response_type=token", clientID)
	runtime.BrowserOpenURL(a.ctx, authURL)

	// Wait for the result and shut down the server securely
	select {
	case token := <-tokenChan:
		cfg := LoadConfig()
		cfg.AniListToken = token
		err := SaveConfig(cfg)
		if err != nil {
			srv.Shutdown(a.ctx)
			return "", fmt.Errorf("failed to save config: %w", err)
		}

		srv.Shutdown(a.ctx)
		return "success", nil
	case err := <-errChan:
		srv.Shutdown(a.ctx)
		return "", err
	}
}

// IsLoggedIn allows Svelte to quickly check if a token exists on boot
func (a *App) IsLoggedIn() bool {
	cfg := LoadConfig()
	return cfg.AniListToken != ""
}

// Logout allows the user to clear their token
func (a *App) Logout() {
	cfg := LoadConfig()
	cfg.AniListToken = ""
	SaveConfig(cfg)
}
