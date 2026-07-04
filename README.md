# AniStream

AniStream is a lightweight, high-performance desktop application that lets you stream anime torrents instantly without waiting for them to finish downloading. By combining a sequential peer-to-peer torrent engine with a native hardware-accelerated video player, you get the high quality of raw torrents with the seamless convenience of modern streaming platforms.

Built entirely in **Flutter and Dart**, AniStream bypasses heavy webviews and Electron wrappers. It renders its beautiful, glassmorphic UI directly onto the GPU canvas alongside the video, resulting in a flawless, stutter-free experience with minimal memory footprint across Windows, macOS, and Linux.

---

## Features

* **P2P Playback:** Click an episode, and streaming begins within seconds. The app utilizes a high-performance C++ torrent engine (`libtorrent`) with time-critical piece deadlines to stream data sequentially without buffering.
* **AniList Syncing:** Log in via secure OAuth2 into your AniList account. The app automatically pulls your current **Watching** and **Plan to Watch** lists into a personalized library view.
* **Progress Tracker:** Watching an episode past the **90% mark** triggers an automated progress update to your AniList account.
* **Hardware Acceleration:** Powered by the `media_kit` package, the video player taps directly into your OS graphics pipeline (NVENC, AMF, QuickSync, VideoToolbox) for HEVC decoding with near-zero CPU usage.

---

## How It Works

AniStream operates as a single, compiled native binary, handling scraping, networking, and rendering in a unified Dart isolate:

1. **The Scraper:** When you select an episode, a background Dart isolate queries **Nyaa.si RSS feeds**, cross-references it with the AniList GraphQL metadata, and assigns a weighted quality score to find the absolute best release group.
2. **The Streaming Pipeline:** The chosen magnet link is fed into `libtorrent_flutter`. Instead of downloading randomly, the engine creates a highly optimized local HTTP streaming server and requests sequential piece deadlines from peers.
3. **The Native Player:** The local stream URL is passed directly to `media_kit`. Because Flutter renders UI using its own 2D graphics engine (Skia/Impeller), the video frames and the UI overlays are composited onto the exact same native OS window simultaneously, entirely eliminating Z-index bugs and OS rendering conflicts.

---

## Developer & System Setup

If you want to compile AniStream from source, modify components, or run a local development build, follow the setup instructions for your operating system below.

### Runtime Prerequisites (All Platforms)

Because the streaming pipeline utilizes native C bindings for video playback, **the `mpv` shared library must be installed on your system.**

---

### Linux Installation

#### 1. Install Base Compiler Tools & Dependencies

Flutter requires standard C++ build tools and GTK3 headers to compile the Linux desktop window.

**For Arch Linux:**

```bash
sudo pacman -S base-devel cmake ninja pkgconf mpv git
```

**For Ubuntu / Debian:**

```bash
sudo apt update
sudo apt install build-essential cmake ninja-build pkg-config libgtk-3-dev mpv git
```

#### 2. Install the Flutter SDK

The cleanest way to install Flutter on Linux is directly from GitHub.

```bash
git clone https://github.com/flutter/flutter.git ~/.flutter-sdk
```

Add Flutter to your shell path (example for **Fish Shell**):

```fish
fish_add_path -g -p ~/.flutter-sdk/bin
```

*(For bash/zsh, add `export PATH="$PATH:$HOME/.flutter-sdk/bin"` to your `.bashrc` or `.zshrc`)*

Run the diagnostic tool to automatically download the Dart SDK:

```bash
flutter doctor
```

---

### Windows Installation

#### 1. Install Git

Install Git via winget:

```cmd
winget install Git.Git
```

#### 2. Install the Flutter SDK

Download and install the Flutter SDK from the [official Flutter website](https://docs.flutter.dev/get-started/install/windows/desktop). Extract it somewhere like `C:\flutter` and add `C:\flutter\bin` to your `PATH` environment variable.

Then run the diagnostic tool to verify your setup and download the Dart SDK:

```cmd
flutter doctor
```

#### 3. Install Visual Studio 2022 Build Tools

Flutter Windows desktop apps require the MSVC C++ compiler and the Windows SDK.

1. Download [Visual Studio 2022 Build Tools](https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022) *(or the full Visual Studio 2022 IDE)*.
2. In the installer, select the **Desktop development with C++** workload.
3. Complete the installation and restart your PC.

After restarting, run `flutter doctor` again to confirm all Windows requirements are satisfied.

---

## Getting Started (Development)

Once your Flutter environment is ready, navigate to the project directory to launch the application.

### 1. Install Dart Packages

Fetch the necessary dependencies (like `media_kit`, `libtorrent_flutter`, etc):

```bash
flutter pub get
```

### 2. Launch the App in Live Development Mode

Flutter handles live hot-reloading automatically. When you save a `.dart` file, the UI will update instantly without losing its state.

*For Linux:*

```bash
flutter run -d linux
```

*For Windows:*

```bash
flutter run -d windows
```

*For macOS:*

```bash
flutter run -d macos
```

---

## Production Builds

To compile a highly optimized, production-ready, standalone binary utilizing the AOT (Ahead-of-Time) compiler, execute:

*For Linux:*

```bash
flutter build linux --release
```

*Outputs to: `build/linux/x64/release/bundle/*`

*For Windows:*

```bash
flutter build windows --release
```

*Outputs to: `build/windows/x64/runner/Release/*`

These commands strip debug symbols, aggressively tree-shake unused code, and output a native executable that requires no external VMs or browsers to run.

---

*For Android (Phone or AndroidTV):*

```bash
flutter build apk --release
```

*Outputs to: `build/app/outputs/flutter-apk/*`                                                                                                           

These commands strip debug symbols, aggressively tree-shake unused code, and output a native executable that requires no external VMs or browsers to run.

> Note: AndroidTV currently doesn't use your TV's built in DPU, so if your TV model has a weak GPU it most likely won't run 1080p footage. *(will most likely run 720p)*
---


## AniStream Remote Server

AniStream ships an optional companion **Go server** (`anistream_server/`) designed for thin clients — Android TV boxes, phones, or weak laptops — that lack the hardware muscle to run a full BitTorrent engine locally. Instead of seeding and downloading on-device, the Flutter app sends a magnet link to the server over the LAN. The server (running on a PC, NAS, or Raspberry Pi) handles all torrent activity and exposes the resulting video as an HTTP range-request stream that MPV opens directly, giving you remote-playback quality without any of the client-side overhead.

For full setup instructions, CLI flags, the REST API reference, and systemd service configuration, see the **[AniStream Server README](anistream_server/README.md)**.

---

## Legal Disclaimer

AniStream is an open-source architectural proof-of-concept designed strictly as a personal utility for local media network synchronization. Users assume complete liability for the metadata aggregation parameters, torrent tracking hashes, and compliance with local legal frameworks governing peer-to-peer data transfers. No copyright-infringing media files are hosted, stored, or distributed on or through this codebase.
