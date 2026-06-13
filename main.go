package main

import (
	"embed"
	"os"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
	"github.com/wailsapp/wails/v2/pkg/options/linux"
	"github.com/wailsapp/wails/v2/pkg/options/mac"
	"github.com/wailsapp/wails/v2/pkg/options/windows"

	"anistream/internal/config"
)

//go:embed all:frontend/dist
var assets embed.FS

func init() {
	// Force GTK to use the X11 backend (XWayland) for MPV compatibility
	_ = os.Setenv("GDK_BACKEND", "x11")

	// Fix "Failed to create GBM buffer" crashes on Arch/CachyOS
	_ = os.Setenv("WEBKIT_DISABLE_DMABUF_RENDERER", "1")
}

func main() {
	app := NewApp()
	cfg := config.Load()

	// The WebView2 autoplay policy env-var is no longer needed:
	// native MPV handles its own audio/video pipeline.
	// We intentionally leave it unset.

	err := wails.Run(&options.App{
		Title:     "AniStream",
		Width:     cfg.Width,
		Height:    cfg.Height,
		Frameless: true,

		// Alpha=0 makes the Wails window itself transparent.
		// Each platform block below enables the compositor-level
		// translucency that lets the native MPV render layer show through.
		BackgroundColour: &options.RGBA{R: 0, G: 0, B: 0, A: 0},

		AssetServer: &assetserver.Options{Assets: assets},
		OnStartup:   app.startup,
		OnShutdown:  app.shutdown,
		Bind:        []interface{}{app},

		// ── Windows ────────────────────────────────────────────────────────
		// WebviewIsTransparent: WebView2 renders with per-pixel alpha so the
		// native MPV child window (positioned at HWND_BOTTOM) shows through.
		// WindowIsTranslucent: enables DWM compositing on the HWND itself.
		Windows: &windows.Options{
			WebviewIsTransparent: true,
			WindowIsTranslucent:  true,
			DisableWindowIcon:    false,
		},

		// ── macOS ──────────────────────────────────────────────────────────
		// WebviewIsTransparent: WKWebView composits with alpha.
		// WindowIsTranslucent:  NSWindow becomes a non-opaque layer window,
		//   letting the MPV NSView subview (placed below WKWebView) show through.
		Mac: &mac.Options{
			TitleBar:             mac.TitleBarHiddenInset(),
			Appearance:           mac.NSAppearanceNameDarkAqua,
			WebviewIsTransparent: true,
			WindowIsTranslucent:  true,
		},

		// ── Linux ──────────────────────────────────────────────────────────
		// GTK + WebKitGTK: transparency is compositor-dependent (Mutter/KWin).
		// WebviewGpuPolicy: keep GPU compositing on so alpha works correctly.
		// Note: --wid embedding requires X11/XOrg. On Wayland, set
		//   GDK_BACKEND=x11 to force XWayland before launching.
		Linux: &linux.Options{
			ProgramName:      "AniStream",
			WebviewGpuPolicy: linux.WebviewGpuPolicyAlways,
		},
	})
	if err != nil {
		println("Fatal:", err.Error())
		os.Exit(1)
	}
}
