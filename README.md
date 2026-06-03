# AniStream

A lightweight, high-performance desktop application designed for streaming anime torrents sequentially. Built from the ground up using **Wails v2** (**Go (Golang)**, **Svelte**).

AniStream bypasses the bloat of traditional Electron-based applications, achieving immediate video playback of P2P media streams while maintaining a microscopic memory and storage footprint.

---

## Features

- **Native Framework Efficiency:** Powered by Wails v2 utilizing native OS webviews (WebView2 on Windows, WebKitGTK on Linux).
- **Sequential P2P Streaming:** Integrates a custom torrent engine that forces sequential piece-picking. Start watching high-definition 1080p anime within seconds while the rest of the torrent downloads seamlessly in the background.
- **Reactive Modern UI:** Crafted with Svelte, and styled using TailwindCSS for fluid animations.
- **Clean Metadata Aggregation:** Designed to plug directly into the **AniList GraphQL API** for beautiful cover art, synopses, schedules, and automated user tracking, cross-referenced against **Nyaa.si RSS feeds**.
- **Seamless Cross-Compilation (for those working in Linux):** Built-in support to cross-compile fully static, standalone `.exe` binaries for Windows 11 directly from your Linux workspace.

---

## Architecture Overview

The app splits execution responsibilities across a secure native Go boundary and a reactive frontend webview:

1. **Frontend Call:** The Svelte user interface issues a reactive command to the backend by calling an auto-generated TypeScript method (e.g., `window.go.main.App.StreamTorrent(magnetLink)`).
2. **Sequential Pre-buffering:** The Go backend initiates the torrent client via `anacrolix/torrent`, prioritizes downloading the file header, index, and initial sequence blocks, and drops lower-priority blocks.
3. **Local Loopback Streaming:** Go mounts an internal HTTP listener on a local random port, transforming the real-time downloading binary buffer into an un-seekable or semi-seekable network stream (`http://localhost:XXXX/stream`).
4. **Media Render:** The frontend video player attaches to the local streaming URL, treating it as a standard web stream.

---

## Prerequisites & System Environment

### 1. Base Development Tools (Host: Arch Linux)

Install the core compilation headers, the Go runtime, Node.js, and the necessary WebKit layout engines:

```bash
sudo pacman -S base-devel go nodejs npm gtk3 webkit2gtk-4.1

```

### 2. Wails CLI Installation

Install the global project management utility for Wails via Go's package manager:

```bash
go install [github.com/wailsapp/wails/v2/cmd/wails@latest](https://github.com/wailsapp/wails/v2/cmd/wails@latest)

```

*Note for **Fish Shell** users:* Ensure your user space path environment variables track Go's workspace binaries folder:

```fish
fish_add_path ~/go/bin

```

---

## Getting Started

### Running in Development Mode

Execute the live development environment.

```bash
wails dev
```

Execute on Linux with WebKit2GTK 4.1

```bash
wails dev -tags webkit2_41
```

---

## Production Compilations

### Build for Native Host

Happens automatically on GitHub Actions.
Config settings can be found inside ./github/workflows/release.yaml`

---

## Legal Disclaimer

AniStream is an open-source architectural proof-of-concept designed strictly for a personal utility, and local media network synchronization. Users assume complete liability for metadata aggregation parameters, torrent tracking hashes, and compliance with local legal frameworks governing peer-to-peer data transfers.
