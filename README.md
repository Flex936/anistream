# AniStream

> **AniStream Docs:** [CLAUDE.md](.claude/CLAUDE.md) · [CODING_RULES.md](.claude/CODING_RULES.md) · [DESIGN.md](.claude/DESIGN.md) · [ARCHITECTURE.md](.claude/ARCHITECTURE.md) · [API.md](.claude/API.md) · **README.md** · [CONTRIBUTING.md](.claude/CONTRIBUTING.md)
> **Covers:** project introduction, feature overview, developer setup/build instructions, and licensing. **See also:** [CLAUDE.md](.claude/CLAUDE.md) for the doc suite's own index and AI/human working norms, [ARCHITECTURE.md](.claude/ARCHITECTURE.md) for the `lib/` folder structure and the optional Go server, [CONTRIBUTING.md](.claude/CONTRIBUTING.md) for the PR process.
> **Disclaimer:** Until we release v1.0.0, the current releases (up to v0.3.0) are built via Wails (a Svelte frontend with a Go backend, opened via your default webview). That version was built with entirely different tools and is also far more behind in development — in design, compatibility, features, optimizations, and general polish. The description below covers the complete new version of the app, which has not been released yet.

## 1. Documentation Index

| Doc | Purpose | Start here if you want to… |
| --- | --- | --- |
| [CLAUDE.md](.claude/CLAUDE.md) | Project overview, AI/human working norms, and the index tying the whole doc suite together | …get oriented, or find which doc covers what |
| [CODING_RULES.md](.claude/CODING_RULES.md) | Strict, enforced coding rules — performance, state management, caching, code-generation quality standards | …know what a PR or an AI-generated change needs to satisfy |
| [DESIGN.md](.claude/DESIGN.md) | Visual language, design tokens, TV/D-pad rules | …build or review UI |
| [ARCHITECTURE.md](.claude/ARCHITECTURE.md) | `lib/` folder structure, state-management pattern, native platform layer, the optional Go server | …know where a file belongs, or how a platform-specific piece works |
| [API.md](.claude/API.md) | AniList & Nyaa.si integrations, scraping, caching | …touch networking, scraping, or tracking |
| [CONTRIBUTING.md](.claude/CONTRIBUTING.md) | PR process, checklist, Code of Conduct | …submit a change |

AniStream started off from two separate ideas from the two of us.

1) Ease of use for torrenting animes.
2) Automatic tracking for animes you watch.

This is what the app has now become:
AniStream is an application that lets you stream anime torrents instantly without waiting for them to finish downloading completely. By combining a sequential torrent engine with mpv, you get the high quality of raw torrents with the seamless convenience of modern streaming platforms.

The app is built entirely in **Flutter and Dart** (well, technically, optionally Go also). It is compatible with Windows, Linux, MacOS, Android (Android based TVs included) and iOS. Take in mind that neither of us can really test MacOS and iOS, since we do not have any device for that.

---

## 2. Features

- **P2P Playback:** Click on an episode, and streaming begins within seconds. The app utilizes a high-performance C++ torrent engine (`libtorrent`) with time-critical piece deadlines to stream data sequentially.
- **Progress Tracker:** Log in to your AniList account via OAuth2. Watching an episode past the **90% mark** triggers an automated progress update to your AniList library.
- **AniList Library:** The app automatically pulls your current **Watching**, **Plan to Watch**, and **Watched** lists into a personalized library view.
- **Calendar:** View weekly upcoming anime.
- **Hardware Acceleration:** Powered by the `media_kit` package, the video player taps directly into your OS graphics pipeline for decoding with near-zero CPU usage.

---

## 3. How It Works

1. **The Scraper:** When you select an episode, the app first asks the **TsukiHime API** — an anime- and episode-aware torrent index — for releases matching that exact episode or the whole season. If TsukiHime doesn't know the anime yet, a background Dart isolate falls back to scraping **Nyaa.si's RSS feeds** directly and scoring the results itself. Either way, live seeder counts come from querying BitTorrent trackers directly. *(Full scoring rubric and query details: [API.md](.claude/API.md).)*
2. **The Streaming Pipeline:** The chosen magnet link is fed into `libtorrent_flutter`, which creates a local HTTP streaming server and requests sequential piece deadlines from peers instead of downloading randomly. *(Or, optionally, offloaded to the companion Go server — see [ARCHITECTURE.md](.claude/ARCHITECTURE.md) § 6.)*
3. **The Native Player:** The local stream URL is passed directly to `media_kit`. Because Flutter renders UI with its own 2D graphics engine (Impeller), the video frames and the UI overlays composite onto the exact same native OS window — no separate video-view Z-index bugs, no OS rendering conflicts.

---

## 4. Developer & System Setup

If you want to compile AniStream from source, modify components, or run a local development build, follow the setup instructions for your operating system below. For the project's folder structure and where new code belongs, see [ARCHITECTURE.md](.claude/ARCHITECTURE.md).

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

#### 2. Install the Flutter SDK (Linux)

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

#### 2. Install the Flutter SDK (Windows)

Download and install the Flutter SDK from the [official Flutter website](https://docs.flutter.dev/install). Extract it somewhere like `C:\flutter` and add `C:\flutter\bin` to your `PATH` environment variable.

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

## 5. Getting Started (Development)

Once your Flutter environment is ready, navigate to the project directory to launch the application.

### 1. Install Dart Packages

Fetch the necessary dependencies (like `media_kit`, `libtorrent_flutter`, etc):

```bash
flutter pub get
```

### 2. Launch the App in Live Development Mode

Flutter handles live hot-reloading automatically. When you save a `.dart` file, the UI updates instantly without losing its state.

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

## 6. Production Builds

Compile an optimized, production-ready binary via Flutter's AOT (Ahead-of-Time) compiler — strips debug symbols, aggressively tree-shakes unused code, and needs no external VM or browser to run.

**Linux** → `build/linux/x64/release/bundle/`

```bash
flutter build linux --release
```

**Windows** → `build/windows/x64/runner/Release/`

```bash
flutter build windows --release
```

**Android (phone or TV)** → `build/app/outputs/flutter-apk/`

```bash
flutter build apk --release
```

> If your model struggles on 1080p footage on AndroidTV consider switching to exoplayer engine in settings. Note: Exoplayer currently requires subtitles from the anistream server and are of lower quality. 

---

## 7. AniStream Remote Server

AniStream ships an optional companion Go server (`anistream_server/`) for thin clients — Android TV boxes, phones, weak laptops — that lack the hardware to run a full BitTorrent engine locally.

- The Flutter app sends a magnet link to the server over the LAN instead of downloading on-device.
- The server (PC, NAS, or Raspberry Pi) handles all torrent activity and exposes the result as an HTTP range-request stream that MPV opens directly — remote-playback quality with none of the client-side overhead.

Full setup instructions, CLI flags, the REST API reference, and systemd service configuration: [AniStream Server README](anistream_server/README.md). How this fits the rest of the app's architecture: [ARCHITECTURE.md](.claude/ARCHITECTURE.md) § 6.

---

## 8. Contributing

Contributions are welcome — bug reports, features, design work, and documentation fixes alike. Read [CONTRIBUTING.md](.claude/CONTRIBUTING.md) before opening a PR; it covers the coding standards ([CODING_RULES.md](.claude/CODING_RULES.md)), the design system ([DESIGN.md](.claude/DESIGN.md)), and the PR checklist (CONTRIBUTING.md § 6).

---

## 9. License

AniStream is licensed under the **GNU General Public License v3.0 (GPLv3)**; see the [`LICENSE`](LICENSE) file at the repository root. By contributing, you agree your contributions are made available under the same license — see [CONTRIBUTING.md](.claude/CONTRIBUTING.md) § 8.

---

## 10. Legal Disclaimer

AniStream is an open-source architectural proof-of-concept designed as a personal utility. Users assume complete liability for the metadata aggregation parameters, torrent tracking hashes, and compliance with local legal frameworks governing peer-to-peer data transfers. No copyright-infringing media files are hosted, stored, or distributed on this codebase. However, while you are streaming, you will become a seeder for that duration.

---
*Last reviewed against the codebase: 2026-08-26. Changed a setup step, added a feature, or introduced a new top-level doc? Update this file's Documentation Index (§ 1) and relevant section too — see [CLAUDE.md](.claude/CLAUDE.md)'s Living Documentation Rule (§ 2).*
