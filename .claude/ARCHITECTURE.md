# AniStream Architecture

> 📚 **AniStream Docs:** [CLAUDE.md](CLAUDE.md) · [DESIGN.md](DESIGN.md) · **ARCHITECTURE.md** · [API.md](API.md) · [README.md](../README.md) · [CONTRIBUTING.md](CONTRIBUTING.md)
> **Covers:** the `lib/` folder structure, state-management pattern, native platform layer, and how the optional Go server fits in. **See also:** [CLAUDE.md](CLAUDE.md) for the rules that assume this structure, [DESIGN.md](DESIGN.md) for the UI layer this hosts, [API.md](API.md) for what the data layer talks to.

**In this file:** [System Overview](#1-system-overview) · [Flutter App Structure](#2-flutter-app-structure) · [State Management](#3-state-management) · [Native Platform Layer](#4-native-platform-layer) · [Streaming Pipeline](#5-streaming-pipeline) · [AniStream Server (Go)](#6-anistream-server-go) · [Known Issues](#7-known-issues)

## 1. System Overview

AniStream is a single Flutter/Dart codebase producing native apps for Windows, Linux, macOS, Android (phone + TV), and iOS. Two things are pluggable behind a shared interface:

- **Torrenting** — either on-device (`libtorrent_flutter`, an FFI binding to `libtorrent`) or offloaded to the optional companion Go server over LAN (§6). The app never runs both at once for a single session — `AppSettings.serverMode` picks one `BaseStreamingController` implementation for the whole session (§5).
- **Playback** — always local, via `media_kit`, which hands frames to Flutter's own Impeller renderer so video and UI overlays composite on the same native surface with no separate video-view Z-index problems.

Metadata and tracking come from AniList's GraphQL API; torrent discovery comes from scraping Nyaa.si's RSS feeds. Both are covered in [API.md](API.md), not here.

```text
┌──────────────┐      GraphQL      ┌──────────────┐
│  AniList API │◄─────────────────►│              │
└──────────────┘                   │              │
┌──────────────┐    RSS scrape     │ Flutter App  │
│   Nyaa.si    │◄─────────────────►│              │
└──────────────┘                   │              │
                                    └──────┬───────┘
                on-device FFI ◄────────────┤
                (libtorrent_flutter)       │
                                           │  LAN REST (optional)
                                  ┌────────▼────────┐
                                  │ AniStream Server│  (Go, § 6)
                                  └─────────────────┘
```

## 2. Flutter App Structure

```text
lib/
├── main.dart                  # Entry point: zone setup, AppLogger.init(), MediaKit.ensureInitialized(),
│                               # InputModeController.instance.init(), desktop window bootstrap, runApp()
├── app.dart                   # MaterialApp root: Dpad.wrap() > InputModeScope > SettingsScope > routed content
│
├── core/                      # App-wide infrastructure. Nothing here is feature-specific.
│   ├── extensions/                build_context_extensions.dart   (Breakpoints, ResponsiveContext)
│   ├── input/                      input_mode_controller.dart, input_mode_scope.dart
│   ├── logging/                    app_logger.dart
│   ├── router/                     app_router.dart
│   ├── settings/                   settings_service.dart, settings_scope.dart
│   └── theme/                      app_palette.dart
│
├── data/                       # External-API clients + their models. No UI.
│   ├── anilist/
│   │   ├── models/                 anime.dart, media_list.dart
│   │   ├── anilist_auth_service.dart
│   │   ├── anilist_query_service.dart
│   │   ├── anilist_queries.dart
│   │   └── anilist_tracker_service.dart
│   └── torrent/
│       ├── models/                 torrent.dart
│       ├── services/               torrent_mirror_fetcher.dart, torrent_parser.dart,
│       │                           torrent_parser_worker.dart, torrent_scoring_engine.dart
│       └── torrent_scraper_service.dart
│
├── shared/                     # Reused by 2+ features. No single feature owns these.
│   ├── widgets/                    anime_card.dart, app_network_image.dart, frosted_container.dart,
│   │                                hover_focus_builder.dart, mouse_back_forward_listener.dart,
│   │                                toast.dart, glass_toast_content.dart
│   └── utils/                       responsive_grid.dart, html_utils.dart, anime_status_style.dart,
│                                    perf_animations.dart
│
└── features/                   # One folder per screen/flow. Each owns its own widgets/services/controllers.
    ├── anime_details/                anime_details_screen.dart, widgets/{episode_tile, hero_banner,
    │                                 torrent_tile, external_link_buttons}.dart
    ├── home/                         home_screen.dart, widgets/anime_carousel.dart
    ├── schedule/                     scheduled_screen.dart, utils/schedule_grouping.dart,
    │                                 widgets/calendar_card.dart
    ├── search/                       search_results_screen.dart, widgets/search_filter_panel.dart
    ├── settings/                     settings_menu.dart, widgets/settings_components.dart
    ├── shell/                        app_shell.dart, controllers/navigation_controller.dart,
    │                                 widgets/{navbar, search_input}.dart
    ├── theater/                      theater_screen.dart, exo_theater_screen.dart,
    │                                 services/{streaming_controller_base, streaming_controller,
    │                                 remote_streaming_controller, player_configurator,
    │                                 auto_skip_controller, theater_data, track_name_parser}.dart,
    │                                 widgets/{theater_controls, theater_player, seekbar,
    │                                 theater_settings, batch_picker}.dart
    └── watchlist/                    watchlist_screen.dart, controllers/watchlist_controller.dart,
                                     widgets/watchlist_cards.dart
```

**Where does new code go?**

| The code… | Goes in |
| --- | --- |
| …is only ever used by one screen/flow | `features/<name>/widgets/` (or `services/`, `controllers/`, `utils/` as needed) |
| …is a widget or util reused by 2+ features | `shared/widgets/` or `shared/utils/` |
| …calls an external API (AniList, Nyaa) | `data/<domain>/services/`, with its wire model in `data/<domain>/models/` |
| …is app-wide infrastructure (logging, theming, routing, settings, input-mode detection) | `core/` |

`playback_session_controller.dart` currently exists in the repo as an empty stub with nothing importing it anywhere in the app — see § 7.

## 3. State Management

Global, app-wide state is managed exclusively via `InheritedNotifier`, wrapped in a `StatefulWidget` "Scope" that owns the underlying controller and installs itself once near the root in `app.dart`:

- **`SettingsScope`** — wraps a `SettingsController` (itself a `ChangeNotifier` around `AppSettings`). Any descendant reads it via `SettingsScope.of(context)`.
- **`InputModeScope`** — wraps the `InputModeController` singleton (TV/D-pad detection — see [DESIGN.md](DESIGN.md) § 4).

Both live directly under `Dpad.wrap()` in `app.dart`'s `MaterialApp.builder`, in that specific order (`InputModeScope(child: SettingsScope(child: child!))`) — this nesting is load-bearing for several widgets further down the tree and shouldn't be reordered without checking every consumer.

Feature-local state (a single screen's pagination, tab selection, or navigation history) uses a plain `ChangeNotifier` controller instead — `NavigationController` (shell's back/forward stack), `WatchlistController` (per-tab pagination across CURRENT/PLANNING/COMPLETED). These are **not** `InheritedNotifier`-wrapped; they're constructed directly by their owning `StatefulWidget` and exposed via `ListenableBuilder`, since nothing outside that screen needs to read them.

There is no Provider, Riverpod, Bloc, or Redux dependency in `pubspec.yaml` — this is deliberate, not an oversight. Don't introduce one; extend the `*Scope` pattern above for new app-wide state instead.

`SettingsCache` (in `settings_service.dart`) is a narrow exception: a synchronous, static in-memory mirror of the current `AppSettings`, for the handful of no-`BuildContext` services (`AnilistQueryService`, instantiated fresh per screen) that need to read a setting (currently just `filterEcchi`) without walking a widget tree they don't have. It's written to only by `SettingsController`, and is never read from inside the widget tree as a replacement for `SettingsScope`.

## 4. Native Platform Layer

Two distinct native-integration mechanisms are in use — new performance-sensitive native work should extend the second, not add more of the first:

1. **A single `MethodChannel`** (`anistream/device_mode`, method `isTelevision`) — used exactly once, by `InputModeController`, to ask the native Android side a one-time yes/no question at boot. Fails safe to `false` (not a TV) if the platform channel isn't implemented, so a build without the native handler wired up simply never activates TV mode rather than crashing. This is only one of two signals feeding `dpadModeActive` — the other (live D-pad/pointer input sniffing) is pure Dart, has no native bridge of its own, and is documented in [DESIGN.md](DESIGN.md) § 4.
2. **FFI plugins** — `libtorrent_flutter` (the torrent engine, all platforms) and its supporting `jni` / `jni_flutter` / `objective_c` packages (cross-platform native interop — not Android-only despite the `jni` name). This is the mechanism for anything performance-critical; the app deliberately keeps custom `MethodChannel` surface area to the single case above.

### Android

- One manifest, one APK, serving both phone and Android TV (`LEANBACK_LAUNCHER` intent-filter category alongside the standard `LAUNCHER`, `android.software.leanback` declared as `required="false"`, a `tv_banner` drawable for the TV launcher). **The phone/TV split is entirely runtime** (`InputModeController.isTvPlatform` + `dpadModeActive`), never a build-time flavor or a separate manifest.
- `android:usesCleartextTraffic="true"` is required because both local streaming paths are plain HTTP: `libtorrent_flutter`'s local streaming server, and (if `serverMode` is on) the LAN-only Go server.
- `android:enableOnBackInvokedCallback="true"` enables predictive back gestures, matching the app's own `PopScope`-based back handling (`AppShell`, `TheaterScreen`).
- `androidHwDec` setting distinguishes `mediacodec` (zero-copy, phones) from `mediacodec-copy` (safer, recommended for TV — see `settings_menu.dart`'s help text). Build tooling: AGP `9.0.1`, Kotlin `2.3.20`, JVM target 17.
- **Known limitation** (carried from [README.md](../README.md)): Android TV builds don't yet use the TV's own decode unit, so weak-GPU TV hardware may struggle with 1080p.

### macOS / iOS

- Standard `FlutterAppDelegate` / `FlutterViewController` embedding; the one behavioral customization is `applicationShouldTerminateAfterLastWindowClosed` returning `true` (quits on last-window-close, matching desktop-app rather than menu-bar-app conventions).
- `Release.entitlements` declares only `com.apple.security.app-sandbox`; `DebugProfile.entitlements` additionally declares `com.apple.security.cs.allow-jit` and `com.apple.security.network.server`. **Worth verifying:** if AniList OAuth (which opens a loopback HTTP server on port 3456) or on-device torrenting stop working specifically in signed/notarized Release builds on macOS, check whether Release needs `com.apple.security.network.client`/`.server` added too — this hasn't been confirmed broken, just flagged as an untested gap between the two entitlement files.
- Per [README.md](../README.md), neither maintainer has a Mac or iOS device to test on — treat this platform as best-effort/community-verified rather than actively maintained.

### Linux

- GTK3 embedding via CMake; the one native customization is setting the GTK window's background to solid black (`#000000`) before the first Flutter frame, avoiding a white flash on a dark-themed app.
- System dependencies: `mpv` (the underlying decode/render library `media_kit` wraps), GTK3 dev headers, standard C++ build tools — see [README.md](../README.md)'s install instructions.

### Windows

- Win32 embedding via CMake/MSVC; window chrome is fully custom (`window_manager` package, `titleBarStyle: TitleBarStyle.hidden` in `main.dart`), with `dwmapi` used natively for dark-mode title-bar theming.
- Requires the Visual Studio 2022 Build Tools "Desktop development with C++" workload — see [README.md](../README.md).

## 5. Streaming Pipeline

`TheaterScreen` depends only on the `BaseStreamingController` interface (`streaming_controller_base.dart`) — `statusText`, `streamUrl`, `isReadyToPlay`, `hasError`, `needsManualSelection`, `batchFiles`, `initialize()`, `selectBatchFile()`. Two implementations satisfy it, chosen once per session by `AppSettings.serverMode`:

| | `StreamingController` | `RemoteStreamingController` |
| --- | --- | --- |
| Torrent engine | On-device, `libtorrent_flutter` (FFI) | Delegated to the Go server over LAN (§6) |
| Transport to player | Local HTTP server (loopback) | Server's `/api/stream/:id/video` endpoint |
| "Ready" threshold | 0.1% sequential buffer downloaded | 5.0% sequential buffer downloaded (server-side `bufferThreshold`) |
| Batch-file selection | In-process, via `libtorrent_flutter`'s file list | Polled from the server's `needs_selection` state, POSTed back via `/select` |

Both implementations parse candidate filenames with the same `TorrentParser` (see [API.md](API.md)) to guess episode numbers inside a batch torrent — this logic is intentionally not duplicated between the on-device and remote paths.

Independent of which streaming controller is active, `AppSettings.useExperimentalPlayer` (mobile/TV only; exposed as "Experimental Video Engine" under Settings → Playback Preferences) additionally picks the *player* implementation: `TheaterScreen` (`media_kit`/mpv — the default, and the only path with chapters, auto-skip, and AniList tracking) or `exo_theater_screen.dart`'s `ExoTheaterScreen` (`video_player`, an ExoPlayer/AVPlayer-backed engine kept around to isolate whether stutter on weak Android TV hardware is a decode-engine problem — see that file's own header comment for the experiment's findings so far). The two axes are orthogonal: either streaming controller pairs with either player. `useExperimentalPlayer` defaults to `false`, so `TheaterScreen` is what every session gets unless a user opts in.

## 6. AniStream Server (Go)

Optional, standalone companion for thin clients (Android TV boxes, phones, weak laptops) that shouldn't run a BitTorrent engine locally. Lives in `anistream_server/`, module `github.com/anistream/server`, single external dependency `github.com/anacrolix/torrent`. Full build/run/API instructions live in [`anistream_server/README.md`](../anistream_server/README.md) — this section is the condensed architectural summary; that file is authoritative for the actual command-line flags and endpoint reference.

**Flow:** the Flutter app POSTs a magnet link to the server; the server does all torrenting and exposes the result as an HTTP range-request video stream (`http.ServeContent` over a `torrent.Reader`, which implements `io.ReadSeeker` — this is what makes MPV's seeking work against the server with no special-casing).

**Session state machine** (one session per active magnet link):

```text
loading_metadata
    │
    ├── single video file found ──────────────┐
    │                                          ▼
    └── multiple video files ──► needs_selection ──(POST /select)──► buffering ──(≥5% downloaded)──► ready

any state ──(3 min metadata timeout / no video files / stream failure)──► error
```

- Sessions idle for 30+ minutes are dropped automatically (`reap()`, checked every 5 minutes).
- No authentication — the server is designed for trusted-LAN use only (see [`anistream_server/README.md`](../anistream_server/README.md)'s own notes on this).
- CORS is fully open (`Access-Control-Allow-Origin: *`) since it's meant to be reachable from any device on the LAN.
- `RemoteStreamingController` (§5) is the only Dart-side consumer of this API.

## 7. Known Issues

Documented per the Living Documentation Rule (CLAUDE.md § 4) rather than silently patched around or left for a reader to rediscover — mirrors the same pattern DESIGN.md § 5 uses for design debt.

- **`playback_session_controller.dart` is a dead stub.** It exists in the repo as an empty file with nothing importing it anywhere in the app (already omitted from the folder tree in § 2). It's slated for removal — don't build on it, and don't be misled by its presence into thinking it's load-bearing.

---
*Last reviewed against the codebase: 2026-08-07. Added a folder, a native bridge, or changed the server's REST surface? Update this file — see CLAUDE.md's Living Documentation Rule (§ 4).*