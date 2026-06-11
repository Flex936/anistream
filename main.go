package main

import (
	"embed"
	"os"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"

	"anistream/internal/config"
)

//go:embed all:frontend/dist
var assets embed.FS

func main() {
	app := NewApp()
	cfg := config.Load()

	// Allow the WebView2 engine to autoplay media without a user gesture,
	// which is required for hls.js to start playback programmatically.
	os.Setenv("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS", "--autoplay-policy=no-user-gesture-required")

	err := wails.Run(&options.App{
		Title:     "AniStream",
		Width:     cfg.Width,
		Height:    cfg.Height,
		Frameless: true,
		AssetServer: &assetserver.Options{
			Assets: assets,
		},
		BackgroundColour: &options.RGBA{R: 27, G: 38, B: 54, A: 1},
		OnStartup:        app.startup,
		OnShutdown:       app.shutdown,
		Bind:             []interface{}{app},
	})
	if err != nil {
		println("Fatal:", err.Error())
	}
}
