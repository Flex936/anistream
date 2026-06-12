# AniStream

AniStream is a lightweight, high-performance desktop application that lets you stream anime torrents instantly without waiting for them to finish downloading. By combining a sequential peer-to-peer torrent engine with an embedded live-transcoding pipeline, you get high-quality torrents and seamless convenience of modern streaming platforms.

AniStream uses native OS layout engines via **Wails v2**, resulting in a microscopic storage footprint and minimal RAM usage.

---

## Features

- **Instant P2P Playback:** Click an episode, and streaming begins within seconds. The custom Go engine prioritizes file headers and sequentially grabs pieces so you can watch while the rest downloads.
- **Automatic AniList Syncing:** Log in via secure OAuth2 into your AniList account. The app automatically pulls your current **Watching** and **Plan to Watch** lists into a personalized library view.
- **Smart "Scrobbling" Progress Tracker:** Watching an episode past the **90% mark** triggers an automated progress update to your AniList account.
- **Studio-Grade Upscaling (via `libplacebo`):** Turn 1080p source video into a razor-sharp experience on 1440p or 4K monitors using advanced shaders like **EWA Lanczos** and **Lanczos Sharp** straight from the player settings.
- **Zero Junk Files:** Torrents download to a temporary cache. The moment you close a video, go back to the menu, or close the application, the app completely purges all temporary video, torrent pieces, and HLS segments from your drive to protect your SSD (or HDD).
- **Hardware Acceleration:** Toggles for NVENC (NVIDIA), AMF (AMD), QuickSync (Intel), and VideoToolbox (Apple Silicon) alongside **AV1 and Opus audio encoding** support.

---

## How It Works

AniStream splits its heavy lifting across Go and a Svelte frontend:

1. **The Scraper:** When you select an episode, a Go worker queries **Nyaa.si RSS feeds**, cross-references it with the AniList metadata, and assigns a weighted quality score to find the absolute best release group.
2. **The Streaming Pipeline:** The chosen magnet link is sent to an embedded `anacrolix/torrent` instance. The first and last pieces are prioritized to extract video headers.
3. **The Transcoder:** Go pipes the local torrent stream directly into a background **MPV process**, which splits the raw video into immediate, localized **HLS (HTTP Live Streaming)** segments, instantly readable by the frontend's video player.

---

## Developer & System Setup

If you want to compile AniStream from source, modify components, or run a local development build, follow the setup instructions for your operating system below.

### Runtime Prerequisites (All Platforms)

Because the streaming pipeline orchestrates a live transcoder, **MPV must be installed on your system and accessible via your global environment variables (PATH).** ---

### Linux Installation (Arch / Ubuntu / Debian)

#### 1. Install Base Compiler Tools & Dependencies

**For Arch Linux:**

```bash
sudo pacman -S base-devel go nodejs npm gtk3 webkit2gtk-4.1 mpv
```

**For Ubuntu / Debian:**

```bash
sudo apt update
sudo apt install build-essential golang nodejs npm libgtk-3-dev libwebkit2gtk-4.1-dev mpv
```

#### 2. Install Wails CLI Globally

```bash
go install github.com/wailsapp/wails/v2/cmd/wails@latest
```

_Note for **Fish Shell** users: Ensure your path tracks your local Go binaries:_

```fish
fish_add_path ~/go/bin
```

---

### Windows Installation

The easiest way to set up a Windows development environment is using **Winget**. Open a terminal as Administrator and run:

#### 1. Install System Dependencies

```cmd
winget install Gold.Go
winget install OpenJS.NodeJS
winget install wailsapp.wails
winget install shinchiro.mpv
```

_(Make sure to restart your terminal after these installations finish so your system updates its environmental path variables!)_

---

## Getting Started (Development)

Once dependencies are installed, navigate to the project directory to launch or compile the application.

### 1. Synchronize the Workspace

Go requires you to map the internal packages to your local directory target. Check your `go.mod` module path name, and ensure internal imports are resolved.

### 2. Launch the App in Live Development Mode

Wails handles live hot-reloading for both Go and Svelte automatically.

```bash
wails dev
```

_For Linux environments running WebKit2GTK 4.1 layout engines explicitly, build with the target tag:_

```bash
wails dev -tags webkit2_41
```

### 3. Generate TypeScript Bindings Manually (Optional because the wails dev command does it automatically)

If you alter signatures inside `app.go` or add new configuration variables to the Go runtime, compile the updated types instantly for Svelte 5:

```bash
wails generate bindings
```

---

## Production Builds

To compile a highly optimized, production-ready, standalone binary for your current machine layout, execute:

```bash
wails build -clean
```

This strips debug symbols, optimizes asset packaging, and outputs a native executable inside the `build/bin` subdirectory.

---

## Legal Disclaimer

AniStream is an open-source architectural proof-of-concept designed strictly as a personal utility for local media network synchronization. Users assume complete liability for the metadata aggregation parameters, torrent tracking hashes, and compliance with local legal frameworks governing peer-to-peer data transfers. No copyright-infringing media files are hosted, stored, or distributed on or through this codebase.
