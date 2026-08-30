# AniStream Architecture

> **AniStream Docs:** [CLAUDE.md](CLAUDE.md) · [CODING_RULES.md](CODING_RULES.md) · [DESIGN.md](DESIGN.md) · **ARCHITECTURE.md** · [API.md](API.md) · [README.md](../README.md) · [CONTRIBUTING.md](CONTRIBUTING.md)
> **Covers:** the `lib/` folder structure, state-management pattern, native platform layer, and how the optional Go server fits in. **See also:** [CODING_RULES.md](CODING_RULES.md) for the rules that assume this structure, [DESIGN.md](DESIGN.md) for the UI layer this hosts, [API.md](API.md) for what the data layer talks to.

## 1. System Overview

AniStream is a single Flutter/Dart codebase producing native apps for Windows, Linux, macOS, Android (phone + TV), and iOS. Two things are pluggable behind a shared interface:

- **Torrenting** — either on-device (`libtorrent_flutter`, an FFI binding to `libtorrent`) or offloaded to the optional companion Go server over LAN (§ 6). NEVER both at once for a single session — `AppSettings.serverMode` picks one `BaseStreamingController` implementation for the whole session (§ 5).
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
                                  │ AniStream Server │  (Go, § 6)
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
│   └── theme/                      app_palette.dart, app_radii.dart, app_typography.dart,
│                                   app_materials.dart, app_card_sizes.dart
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
│   ├── widgets/                     anime_card.dart, app_network_image.dart, app_segmented_control.dart,
│   │                                frosted_container.dart, hover_focus_builder.dart, mouse_back_forward_listener.dart,
│   │                                selection_modal.dart, settings_text_field.dart,
│   │                                toggle_switch.dart, toast.dart, glass_toast_content.dart
 
│   └── utils/                       html_utils.dart, anime_status_style.dart, perf_animations.dart,
│                                    theater_session.dart
│
└── features/                   # One folder per screen/flow. Each owns its own widgets/services/controllers.
    ├── anime_details/                anime_details_screen.dart, widgets/{episode_tile, hero_banner,
    │                                 hero_header_delegate, hero_header_compact, anime_synopsis_section,
    │                                 torrent_tile, torrent_search_modal, external_link_buttons}.dart
    ├── custom_stream/                custom_stream_launcher.dart, widgets/custom_magnet_modal.dart
    ├── home/                         home_screen.dart, widgets/anime_carousel.dart
    ├── schedule/                     scheduled_screen.dart, utils/schedule_grouping.dart,
    │                                 widgets/calendar_card.dart
    ├── search/                       search_results_screen.dart, widgets/search_filter_panel.dart
    ├── settings/                     settings_menu.dart, widgets/settings_components.dart
    ├── shell/                        app_shell.dart, controllers/navigation_controller.dart,
    │                                 widgets/{navbar, search_input}.dart
    ├── theater/                      theater_screen.dart,
    │                                 services/{streaming_controller_base, streaming_controller,
    │                                 remote_streaming_controller, player_configurator,
    │                                 auto_skip_controller, playback_diagnostics, theater_data,
    │                                 track_name_parser}.dart,
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

Both live directly under `Dpad.wrap()` in `app.dart`'s `MaterialApp.builder`, in that specific order (`InputModeScope(child: SettingsScope(child: child!))`). NEVER reorder this nesting without checking every consumer — it's load-bearing for several widgets further down the tree.

Feature-local state (a single screen's pagination, tab selection, or navigation history) uses a plain `ChangeNotifier` controller instead — `NavigationController` (shell's back/forward stack), `WatchlistController` (per-tab pagination across CURRENT/PLANNING/COMPLETED).

- These are **not** `InheritedNotifier`-wrapped. They're constructed directly by their owning `StatefulWidget` and exposed via `ListenableBuilder`, since nothing outside that screen needs to read them.
- FORBIDDEN: Provider, Riverpod, Bloc, Redux, or any other state-management package — deliberate, not an oversight. Extend the `*Scope` pattern above for new app-wide state instead.

`SettingsCache` (in `settings_service.dart`) is a narrow exception: a synchronous, static in-memory mirror of the current `AppSettings`, for the handful of no-`BuildContext` services (`AnilistQueryService`, instantiated fresh per screen) that need to read a setting (currently just `filterEcchi`) without walking a widget tree they don't have. `SettingsController` is its only writer. NEVER read it from inside the widget tree as a replacement for `SettingsScope`.

## 4. Native Platform Layer

Two distinct native-integration mechanisms are in use — new performance-sensitive native work should extend the second, not add more of the first:

1. **A single `MethodChannel`** (`anistream/device_mode`, method `isTelevision`) — used exactly once, by `InputModeController`, to ask the native Android side a one-time yes/no question at boot. Fails safe to `false` (not a TV) if the platform channel isn't implemented, so a build without the native handler wired up simply never activates TV mode rather than crashing. This is the *only* signal feeding `dpadModeActive`, sticky for the process lifetime once resolved — deliberately NOT combined with live input-sniffing. A directional key or gamepad press is ordinary keyboard/pointer input on desktop and phone, regardless of connected hardware, and is never treated as a TV signal there. See [DESIGN.md](DESIGN.md) § 4.
2. **FFI plugins** — `libtorrent_flutter` (the torrent engine, all platforms) and its supporting `jni` / `jni_flutter` / `objective_c` packages (cross-platform native interop — not Android-only despite the `jni` name). This is the mechanism for anything performance-critical; the app deliberately keeps custom `MethodChannel` surface area to the single case above.

### Android

- One manifest, one APK, serving both phone and Android TV (`LEANBACK_LAUNCHER` intent-filter category alongside the standard `LAUNCHER`, `android.software.leanback` declared as `required="false"`, a `tv_banner` drawable for the TV launcher). **The phone/TV split is entirely runtime** (`InputModeController.isTvPlatform` + `dpadModeActive`), never a build-time flavor or a separate manifest.
- `android:usesCleartextTraffic="true"` is required because both local streaming paths are plain HTTP: `libtorrent_flutter`'s local streaming server, and (if `serverMode` is on) the LAN-only Go server.
- `android:enableOnBackInvokedCallback="true"` enables predictive back gestures, matching the app's own `PopScope`-based back handling (`AppShell`, `TheaterScreen`).
- `androidHwDec` setting distinguishes `mediacodec` (zero-copy, phones) from `mediacodec-copy` (safer, recommended for TV — see `settings_menu.dart`'s help text). Build tooling: AGP `9.0.1`, Kotlin `2.3.20`, JVM target 17.
- **Known limitation** (carried from [README.md](../README.md) § 6): Android TV builds don't yet use the TV's own decode unit, so weak-GPU TV hardware may struggle with 1080p.

### macOS / iOS

- Standard `FlutterAppDelegate` / `FlutterViewController` embedding; the one behavioral customization is `applicationShouldTerminateAfterLastWindowClosed` returning `true` (quits on last-window-close, matching desktop-app rather than menu-bar-app conventions).
- `Release.entitlements` declares only `com.apple.security.app-sandbox`; `DebugProfile.entitlements` additionally declares `com.apple.security.cs.allow-jit` and `com.apple.security.network.server`. **Worth verifying:** if AniList OAuth (loopback HTTP server on port 3456) or on-device torrenting stop working specifically in signed/notarized Release builds, check whether Release needs `com.apple.security.network.client`/`.server` added too — not confirmed broken, just an untested gap between the two entitlement files (logged in § 7).
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
| Torrent engine | On-device, `libtorrent_flutter` (FFI) | Delegated to the Go server over LAN (§ 6) |
| Transport to player | Local HTTP server (loopback) | Server's `/api/stream/:id/video` endpoint |
| "Ready" threshold | 0.1% sequential buffer downloaded | 5.0% sequential buffer downloaded (server-side `bufferThreshold`) |
| Batch-file selection | In-process, via `libtorrent_flutter`'s file list | Polled from the server's `needs_selection` state, POSTed back via `/select` |

Both implementations parse candidate filenames with the same `TorrentParser` (see [API.md](API.md) § 3) to guess episode numbers inside a batch torrent — this logic is intentionally not duplicated between the on-device and remote paths.

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
- No auth, CORS fully open (`Access-Control-Allow-Origin: *`) — trusted-LAN use only. Full rationale in [`anistream_server/README.md`](../anistream_server/README.md)'s own notes.
- `RemoteStreamingController` (§ 5) is the only Dart-side consumer of this API.

## 7. Known Issues

Documented per the Living Documentation Rule ([CLAUDE.md](CLAUDE.md) § 2) rather than silently patched around or left for a reader to rediscover — mirrors the same pattern [DESIGN.md](DESIGN.md) § 5 uses for design debt.

- **`playback_session_controller.dart` is a dead stub.** Empty file, nothing imports it (already omitted from § 2's folder tree). Slated for removal — NEVER build on it.
- **macOS/iOS Release entitlements are an unconfirmed gap, not a confirmed fix.** § 4 flags that `Release.entitlements` may be missing `com.apple.security.network.client`/`.server` relative to `DebugProfile.entitlements`. Not confirmed to actually break AniList OAuth's loopback server or on-device torrenting in signed/notarized Release builds — just an untested gap. Cross-referenced here so this stays the complete index of open items.
- **Linux/Wayland/NVIDIA video freeze after an extended pause — confirmed, not fixable from this codebase, mitigated with a manual restart button.**
  - **Repro:** pause 15 minutes to over an hour, then resume. Audio and the seekbar/position continue normally; the video frame stays permanently frozen for the rest of that session.
  - **Confirmed on:** Linux + Wayland + NVIDIA (`hwdec-current=nvdec`, `current-vo=libmpv`). Not on Windows + Intel iGPU.
  - **Ruled out** (via `playback_diagnostics.dart`): network layer, demuxer/cache, app focus/lifecycle, mpv's own decode pipeline — all confirmed healthy.
  - **Root cause** (source inspection of `media_kit_video`'s Linux plugin, `video_output.cc`, `media-kit/media-kit`): it renders through an EGL context deliberately isolated from Flutter's own, created exactly once when the `Player` is constructed — no public API to re-initialize it short of fully disposing that `Player`.
  - **Tried and confirmed ineffective**, on real affected hardware: a same-position seek; cycling the `hwdec` mpv property. Manually scrubbing the seekbar doesn't restore the picture either.
  - **No automatic fix is possible:** no mpv property distinguishes a frozen frame from a healthy one, so no automatic trigger could ever be correct.
  - **Shipped mitigation:** a manual restart button (`AppSettings.showFreezeRecoveryButton`, Settings → Playback Preferences, default off) in `TheaterTopBar`. It disposes only `_player` — freeing the stuck texture — while deliberately leaving the buffered `BaseStreamingController` running. `TheaterScreen` pops with a `TheaterRestartRequest` carrying that controller and a resume position (a few seconds before wherever playback was); `AnimeDetailsScreen._streamTorrent` immediately re-pushes a fresh `TheaterScreen` against it, recovering without re-downloading the torrent.
  - **Still open:** not yet filed upstream against `media-kit/media-kit` — worth doing regardless of the mitigation, since the confirmed root cause lives entirely in the plugin's native Linux rendering path and this codebase can't fix it directly.

---
*Last reviewed against the codebase: 2026-08-15. Added a folder, a native bridge, or changed the server's REST surface? Update this file — see [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule.*
