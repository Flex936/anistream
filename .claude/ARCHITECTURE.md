# AniStream Architecture

> **AniStream Docs:** [CLAUDE.md](CLAUDE.md) · [CODING_RULES.md](CODING_RULES.md) · [DESIGN.md](DESIGN.md) · **ARCHITECTURE.md** · [API.md](API.md) · [README.md](../README.md) · [CONTRIBUTING.md](CONTRIBUTING.md)
> **Covers:** the `lib/` folder structure, state-management pattern, native platform layer, and how the optional Go server fits in. **See also:** [CODING_RULES.md](CODING_RULES.md) for the rules that assume this structure, [DESIGN.md](DESIGN.md) for the UI layer this hosts, [API.md](API.md) for what the data layer talks to.

## 1. System Overview

AniStream is a single Flutter/Dart codebase producing native apps for Windows, Linux, macOS, Android (phone + TV), and iOS. Two things are pluggable behind a shared interface:

- **Torrenting** — either on-device (`libtorrent_flutter`, an FFI binding to `libtorrent`) or offloaded to the optional companion Go server over LAN (§ 6). NEVER both at once for a single session — `AppSettings.serverMode` picks one `BaseStreamingController` implementation for the whole session (§ 5).
- **Playback** — always local, via `media_kit`, whose frames go through Flutter's own Impeller renderer — video and UI overlays composite on the same native surface, no separate video-view Z-index problems.

Metadata and tracking come from AniList's GraphQL API. Torrent discovery is layered — TsukiHime API first, Nyaa.si RSS scraping as fallback, BitTorrent tracker scraping backfills live seeder counts. Full detail: [API.md](API.md), not here.

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

*(Diagram simplified to Nyaa.si's original single-source role — see [API.md](API.md) §§ 3, 5, 6 for the current layered torrent-discovery flow.)*

## 2. Flutter App Structure

```text
lib/
├── main.dart                  # Entry point: zone setup, AppLogger.init(), MediaKit.ensureInitialized(),
│                               # InputModeController.instance.init(), desktop window bootstrap, runApp()
├── app.dart                   # MaterialApp root: Dpad.wrap() > InputModeScope > SettingsScope > routed content
│
├── core/                      # App-wide infrastructure. Nothing here is feature-specific.
│   ├── deep_link/                  deep_link_server.dart
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
│       ├── models/                 torrent.dart, tsukihime_models.dart
│       ├── services/               torrent_mirror_fetcher.dart, torrent_parser.dart,
│       │                           torrent_parser_worker.dart, torrent_scoring_engine.dart,
│       │                           tsukihime_api_service.dart, tracker_scrape_service.dart,
│       │                           bencode.dart
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
    ├── shell/                        app_shell.dart, controllers/{navigation_controller,
    │                                 anilist_login_controller}.dart, widgets/{navbar, search_input}.dart
    ├── theater/                      theater_screen.dart, exo_theater_screen.dart,
    │                                 services/{streaming_controller_base, streaming_controller,
    │                                 remote_streaming_controller, player_configurator,
    │                                 auto_skip_controller, controls_visibility_controller,
    │                                 next_episode_prefetch_controller, playback_stall_controller,
    │                                 playback_diagnostics, theater_data, track_name_parser,
    │                                 top_notification_controller, playback_handle,
    │                                 mpv_chapter_loader, native_chapter_parser,
    │                                 native_subtitle_parser}.dart,
    │                                 widgets/{theater_controls, mobile_theater_controls,
    │                                 theater_player, seekbar, skip_chip, playback_action_chip,
    │                                 styled_subtitle_view, theater_settings, batch_picker}.dart
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

`playback_session_controller.dart` currently exists as an empty stub with nothing importing it anywhere — see § 7.

## 3. State Management

Global, app-wide state uses `InheritedNotifier`, wrapped in a `StatefulWidget` "Scope" that owns the controller and installs once near the root in `app.dart`:

- **`SettingsScope`** — wraps `SettingsController` (a `ChangeNotifier` around `AppSettings`). Read via `SettingsScope.of(context)`.
- **`InputModeScope`** — wraps the `InputModeController` singleton (TV/D-pad detection — [DESIGN.md](DESIGN.md) § 4).

Both live directly under `Dpad.wrap()` in `app.dart`'s `MaterialApp.builder`, in that order: `InputModeScope(child: SettingsScope(child: child!))`. NEVER reorder this nesting without checking every consumer — several widgets further down depend on it.

Feature-local state (a screen's pagination, tab selection, navigation history) uses a plain `ChangeNotifier` controller instead — `NavigationController` (shell's back/forward stack), `WatchlistController` (per-tab pagination across CURRENT/PLANNING/COMPLETED).

- NOT `InheritedNotifier`-wrapped — constructed directly by the owning `StatefulWidget`, exposed via `ListenableBuilder`, since nothing outside that screen reads them.
- FORBIDDEN: Provider, Riverpod, Bloc, Redux, or any other state-management package — deliberate. Extend the `*Scope` pattern for new app-wide state instead.

`SettingsCache` (`settings_service.dart`) is a narrow exception — a synchronous, static in-memory mirror of `AppSettings`, for no-`BuildContext` services (`AnilistQueryService`, instantiated fresh per screen) that need a setting (currently just `filterEcchi`) without a widget tree to walk. `SettingsController` is its only writer. NEVER read it from inside the widget tree as a `SettingsScope` replacement.

## 4. Native Platform Layer

Two distinct native-integration mechanisms exist — extend the second for new performance-sensitive native work, not the first.

**1. `MethodChannel`s** — three today, all registered in `MainActivity.kt`, all Android-only with no iOS/macOS equivalent:

| Channel | Method | Used by | Notes |
| --- | --- | --- | --- |
| `anistream/device_mode` | `isTelevision` | `InputModeController`, once at boot | Sole signal feeding `dpadModeActive` — fails safe to `false` if unimplemented, rather than crashing. See [DESIGN.md](DESIGN.md) § 4 for why a second, live-sniffing signal is never added |
| `anistream/chapter_parser` | `extractChapters` | ExoPlayer path only (`ExoTheaterScreen`) | Opens a throwaway ExoPlayer against the stream URL to read Media3's Chapter metadata — `video_player` has no chapter API of its own; media_kit/mpv gets chapters natively |
| `anistream/subtitle_parser` | `parseSubtitle` | ExoPlayer path only | Hands raw subtitle bytes to Media3's `TtmlParser`/`SsaParser` for real cue timing/positioning/per-run styling, instead of `video_player`'s plain-text `ClosedCaptionFile` |

**2. FFI plugins** — `libtorrent_flutter` (the torrent engine, all platforms) plus its `jni`/`jni_flutter`/`objective_c` interop packages (cross-platform despite the `jni` name). The mechanism for anything performance-critical — the `MethodChannel`s above are one-shot metadata/parsing calls, not sustained high-throughput work.

### Android

- One manifest, one APK, serves both phone and Android TV (`LEANBACK_LAUNCHER` alongside the standard `LAUNCHER`, `android.software.leanback` as `required="false"`, a `tv_banner` drawable for the TV launcher). **The phone/TV split is entirely runtime** (`InputModeController.isTvPlatform` + `dpadModeActive`) — never a build-time flavor or separate manifest.
- `android:usesCleartextTraffic="true"` — both local streaming paths are plain HTTP: `libtorrent_flutter`'s local server, and (if `serverMode` is on) the LAN-only Go server.
- `android:enableOnBackInvokedCallback="true"` enables predictive back gestures, matching the app's `PopScope`-based back handling (`AppShell`, `TheaterScreen`).
- `androidHwDec`: `mediacodec` (zero-copy, phones) vs. `mediacodec-copy` (safer, recommended for TV — see `settings_menu.dart`'s help text). Build tooling: AGP `9.0.1`, Kotlin `2.3.20`, JVM target 17.
- **Known limitation** ([README.md](../README.md) § 6): Android TV builds don't yet use the TV's own decode unit — weak-GPU TV hardware may struggle with 1080p.

### macOS / iOS

- Standard `FlutterAppDelegate`/`FlutterViewController` embedding — the one behavioral customization is `applicationShouldTerminateAfterLastWindowClosed` returning `true` (quits on last-window-close, matching desktop-app rather than menu-bar-app conventions).
- `Release.entitlements` declares only `com.apple.security.app-sandbox`; `DebugProfile.entitlements` additionally has `com.apple.security.cs.allow-jit` and `.network.server`. **Worth verifying:** if AniList OAuth (loopback server, port 3456) or on-device torrenting break specifically in signed/notarized Release builds, check whether Release needs `.network.client`/`.server` too — untested gap, not confirmed broken (§ 7).
- Per [README.md](../README.md), neither maintainer has a Mac or iOS device to test on — treat this platform as best-effort/community-verified, not actively maintained.

### Linux

- GTK3 embedding via CMake — the one native customization sets the GTK window's background to solid black (`#000000`) before the first Flutter frame, avoiding a white flash on a dark-themed app.
- System dependencies: `mpv` (the decode/render library `media_kit` wraps), GTK3 dev headers, standard C++ build tools — see [README.md](../README.md)'s install instructions.

### Windows

- Win32 embedding via CMake/MSVC — window chrome is fully custom (`window_manager` package, `titleBarStyle: TitleBarStyle.hidden` in `main.dart`), with `dwmapi` used natively for dark-mode title-bar theming.
- Requires the Visual Studio 2022 Build Tools "Desktop development with C++" workload — see [README.md](../README.md).

## 5. Streaming Pipeline

`TheaterScreen` depends only on the `BaseStreamingController` interface (`streaming_controller_base.dart`) — `statusText`, `streamUrl`, `isReadyToPlay`, `hasError`, `needsManualSelection`, `batchFiles`, `initialize()`, `selectBatchFile()`. Two implementations satisfy it, chosen once per session via `AppSettings.serverMode`:

| | `StreamingController` | `RemoteStreamingController` |
| --- | --- | --- |
| Torrent engine | On-device, `libtorrent_flutter` (FFI) | Delegated to the Go server over LAN (§ 6) |
| Transport to player | Local HTTP server (loopback) | Server's `/api/stream/:id/video` endpoint |
| "Ready" threshold | 0.1% sequential buffer downloaded | 5.0% sequential buffer downloaded (server-side `bufferThreshold`) |
| Batch-file selection | In-process, via `libtorrent_flutter`'s file list | Polled from the server's `needs_selection` state, POSTed back via `/select` |

Both implementations parse candidate filenames with the same `TorrentParser` ([API.md](API.md) § 3) to guess episode numbers inside a batch torrent — this logic is intentionally not duplicated between the two paths.

`AppSettings.useExoPlayer` (mobile/TV only, "ExoPlayer Video Engine" under Settings → Playback Preferences) independently picks the player, orthogonal to `serverMode`:

| | `TheaterScreen` (default) | `ExoTheaterScreen` |
| --- | --- | --- |
| Engine | media_kit / mpv | `video_player` (ExoPlayer/AVPlayer) |
| D-Pad/TV-remote focus nav | Yes | No |
| Chapters, auto-skip, AniList tracking | Yes | Yes |
| Audio-track switching | Yes — media_kit's `Tracks`/`setAudioTrack` | Yes, via `PlaybackHandle` (`getAudioTracks()`/`selectAudioTrack()`, Media3's `DefaultTrackSelector`) — closes a gap specific to this path |
| Platform scope | All | Android/TV-primary; iOS out of scope |

`ExoTheaterScreen` exists to isolate whether stutter on weak Android TV hardware is a decode-engine problem — see that file's own header comment for findings so far. Either streaming controller pairs with either player. `useExoPlayer` defaults to `false`, so `TheaterScreen` is what every session gets unless a user opts in.

**Background prefetching:** `NextEpisodePrefetchController` runs two tiers as the current episode nears its end.

- **Tier 1** (always): resolves and scores the next episode's torrents via `TorrentScraperService`, so `TorrentSearchModal` opens pre-resolved even with autoplay off.
- **Tier 2** (only with episode-autoplay on): builds a second, short-lived `BaseStreamingController` — via `createStreamingController(AppSettings)`, so it matches the current episode's own `serverMode` pick — and starts buffering it, for an instant hand-off.
- This briefly overlaps two controller *instances* of the same implementation, never two different implementations — § 1's "never both at once" rule still holds.
- Owned and disposed by `TheaterScreen`; only an actual episode transition takes ownership of the warm controller. Scoped to `TheaterScreen` — `ExoTheaterScreen` has neither episode-autoplay nor prefetching.

**HTTP reconnect tuning:** both streaming backends serve plain HTTP(S), read via mpv's libavformat network layer (`PlayerConfigurator._applyStreamingTuning`). A long pause routinely outlives the underlying TCP connection's keep-alive window (OS, local-server idle-out, or a LAN NAT/router) — mpv's demuxer has no built-in awareness the socket died, so left at defaults it never reissues the ranged GET, and a resume/seek reads from a dead connection, indistinguishable from a freeze. Mitigated via `network-timeout=10` plus `stream-lavf-o`'s `reconnect`/`reconnect_streamed`/`reconnect_on_network_error`/`reconnect_delay_max=5` — libavformat's standard dropped-connection recovery. Targets the specific failure mode `PlaybackDiagnostics` is built to confirm (§ 7); a freeze reproducing with `demuxer-cache-idle`/`core-idle` already `no` has a different root cause this tuning won't fix.

## 6. AniStream Server (Go)

Optional, standalone companion for thin clients (Android TV boxes, phones, weak laptops) that shouldn't run a BitTorrent engine locally. Lives in `anistream_server/`, module `github.com/anistream/server`, two dependencies: `github.com/anacrolix/torrent`, `asticode/go-astisub`. This section is the condensed architectural summary — [`anistream_server/README.md`](../anistream_server/README.md) is authoritative for actual CLI flags and the endpoint reference.

**Flow:** the Flutter app POSTs a magnet link; the server does all torrenting and exposes the result as an HTTP range-request video stream (`http.ServeContent` over a `torrent.Reader`, which implements `io.ReadSeeker` — this is what makes MPV's seeking work with no special-casing).

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
- `max-storage-gb` (0 = unlimited) caps `-data`'s total on-disk size — once reached, `POST /api/stream` rejects new sessions with 507 rather than accept one that can't fit. Measured by periodically walking `-data`, not by summing the torrent client's own byte-completed counters (see [`anistream_server/README.md`](../anistream_server/README.md) § 4). Existing sessions are never paused to enforce this.
- No auth, CORS fully open (`Access-Control-Allow-Origin: *`) — trusted-LAN use only. Full rationale in [`anistream_server/README.md`](../anistream_server/README.md)'s own notes.
- `RemoteStreamingController` (§ 5) is the only Dart-side consumer of this API.

## 7. Known Issues

Documented per the Living Documentation Rule ([CLAUDE.md](CLAUDE.md) § 2) rather than silently patched around — mirrors [DESIGN.md](DESIGN.md) § 5's pattern for design debt.

- **`playback_session_controller.dart` is a dead stub.** Empty file, nothing imports it (already excluded from § 2's tree). Slated for removal — NEVER build on it.
- **macOS/iOS Release entitlements are an unconfirmed gap.** § 4 flags that `Release.entitlements` may be missing `com.apple.security.network.client`/`.server`, relative to `DebugProfile.entitlements`. Not confirmed to break AniList OAuth's loopback server or on-device torrenting in signed/notarized builds — just untested. Logged here so this stays the complete index of open items.
- **Linux/Wayland/NVIDIA video freeze after an extended pause** — confirmed, not fixable from this codebase, mitigated with a manual restart button:

  | Aspect | Detail |
  | --- | --- |
  | Repro | Pause 15 minutes to over an hour, then resume. Audio and the seekbar/position continue normally; the video frame stays permanently frozen for the rest of that session. |
  | Confirmed on | Linux + Wayland + NVIDIA (`hwdec-current=nvdec`, `current-vo=libmpv`). Not on Windows + Intel iGPU. |
  | Ruled out | Network layer, demuxer/cache, app focus/lifecycle, mpv's own decode pipeline — all confirmed healthy (via `playback_diagnostics.dart`). |
  | Root cause | `media_kit_video`'s Linux plugin (`video_output.cc`, source-inspected) renders through an EGL context deliberately isolated from Flutter's own, created once when the `Player` is constructed — no public API to reinit it short of fully disposing that `Player`. |
  | Tried, confirmed ineffective | A same-position seek; cycling the `hwdec` mpv property. Manually scrubbing the seekbar doesn't restore the picture either. |
  | Automatic fix | Not possible — no mpv property distinguishes a frozen frame from a healthy one. |
  | Shipped mitigation | Manual restart button (`AppSettings.showFreezeRecoveryButton`, Settings → Playback Preferences, default off) in `TheaterTopBar`. Disposes only `_player` — freeing the stuck texture — while leaving the buffered `BaseStreamingController` running. `TheaterScreen` pops a `TheaterRestartRequest` carrying that controller and a resume position a few seconds back; `AnimeDetailsScreen._streamTorrent` immediately re-pushes a fresh `TheaterScreen` against it, recovering with no re-download. |
  | Still open | Not yet filed upstream against `media-kit/media-kit` — worth doing regardless of the mitigation, since the root cause lives entirely in the plugin's native Linux rendering path. |

- **TsukiHime internal-ID lookups aren't cached per session.** `TsukihimeApiService.resolveInternalId` re-resolves the AniList ID → internal ID mapping on every `fetchTorrents` call — `_TorrentSearchCache` (`torrent_scraper_service.dart`) only caches the final, per-episode torrent list, not this intermediate lookup. Binge-watching one show re-runs it once per episode. Flagged in-code as a TODO, not yet implemented.
- **Batch-torrent episode selection still pulls in a sliver of adjacent episodes — expected, not a regression.** BitTorrent's atomic unit is the piece, not the file — pieces are laid out across a multi-file torrent's whole concatenated byte stream (BEP 0003), so a piece straddling two episode files can't complete for one without also pulling in the other's overlapping bytes. `session.activate()` (`main.go`) sets every file but the selected one to `PiecePriorityNone`, but the one or two pieces shared with its immediate neighbors still download regardless — the torrent client needs them to complete the selected file. Bounded to roughly one piece's worth per side (a few MiB to several dozen, depending on the torrent's own piece size) — not the full neighboring episode, and distinct from the earlier whole-batch-download bug, which `session.run()`'s metadata-resolve-time deprioritization already fixed. Not fixable client-side — would require the torrent to have been authored with episode-aligned piece boundaries in the first place, outside this app's control.

## 8. Browser Extension Integration

A separate, small companion codebase (its own `manifest.json`/`content.js`/`background.js`) injects an "Open in AniStream" button on AniList and MyAnimeList anime pages. The button never carries anime metadata — the extension only knows which site it's on and the numeric id from the page URL (`anilist.co/anime/<id>`, `myanimelist.net/anime/<id>`) — resolving that id into a real `Anime` and opening it is entirely this app's job.

```text
Extension button click
  → GET http://127.0.0.1:53211/open?source=anilist|mal&id=<n>
  → DeepLinkServer (core/deep_link/deep_link_server.dart)
      validates the request, responds 200/400 immediately,
      brings the desktop window to front, stores the request
  → AppShell (features/shell/app_shell.dart)
      resolves the id via AnilistQueryService.getAnimeByExternalId
      (API.md § 2), then reuses the same _handleSelectAnime() every
      card/carousel already calls to reach AnimeDetailsScreen
```

- `DeepLinkServer` is a `ChangeNotifier` singleton (`.instance`), started once from `main.dart`'s `_bootstrap()`, desktop-only — Chrome/Edge/Brave extensions have no equivalent on the mobile platforms this app also targets.
- Binds `127.0.0.1` only (`InternetAddress.loopbackIPv4`), matching the extension's own same-device-only design. No auth: a request can't reach this port from anywhere but the same machine.
- A bind failure (most likely a second AniStream instance already holding the port) is logged and swallowed, not surfaced as a crash — that instance simply never receives deep links.
- `pending` (not a bare broadcast stream) lets a request arriving before `AppShell` mounts still be picked up — `AppShell` checks it directly in `initState`, not just future notifications.

---
*Last reviewed against the codebase: 2026-09-06. Added a folder, a native bridge, or changed the server's REST surface? Update this file — see [CLAUDE.md](CLAUDE.md)'s Living Documentation Rule (§ 2).*
