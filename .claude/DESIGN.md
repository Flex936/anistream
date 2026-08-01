# AniStream Design System & UI Specs

> 📚 **AniStream Docs:** [CLAUDE.md — overview & index](CLAUDE.md) · [CODING_RULES.md — tech constraints](CODING_RULES.md) · **DESIGN.md — UI/UX rules** · [ARCHITECTURE.md — structure & platform](ARCHITECTURE.md) · [API.md — data & caching](API.md) · [README.md — project intro](../README.md) · [CONTRIBUTING.md — PR process](CONTRIBUTING.md)
> **Covers:** visual language, performance-mode rules, responsive layout, and TV/D-pad spatial navigation. **See also:** [CODING_RULES.md](CODING_RULES.md) for how these rules are enforced when generating code, [ARCHITECTURE.md](ARCHITECTURE.md) § 2 for where the widgets implementing them live.

## 1. UI/UX Philosophy & Visual Language

- Execute a premium, Apple/Spotify-inspired UI/UX. Prioritize clean layouts, deep contrasts, and seamless transitions.
- Source all colors strictly from `lib/core/theme/app_palette.dart` (`AppPalette.*`). Extend this palette logically if new shades are required. Colors should not be hardcoded in widget files — known exceptions are tracked in § 5.
- Source all text styles from `lib/core/theme/app_typography.dart` (`context.appTypography`) rather than hardcoded font sizes/weights — see that file's own doc comment for the full named-token list.
- Source border radii from `lib/core/theme/app_radii.dart` (`context.appRadii`), a 3-tier scale: **`.tag` (~6px)** for small decorative badges/pills, **`.small` (~12px)** for list/grid item cards (`AnimeCard`, `TorrentTile`, the watchlist grid's `WatchlistCard`), **`.large` (~24px)** for large slide-in panels (`SettingsMenu`, `SearchFilterPanel`, the mobile nav drawer). See § 5 for current outliers to this rule.
- Utilize Glassmorphism heavily for overlays, toasts, and floating elements using `BackdropFilter` — this should always be routed through the shared `FrostedContainer` widget rather than a bare `BackdropFilter` call (see § 2). A pre-existing exception is tracked in § 5.

## 2. Performance UI Mode

- Read the active performance state (`SettingsScope.of(context).uiPerformanceMode`) when building visually complex components.
- Auto-downgrade expensive rendering when performance mode is active — e.g., replace `BackdropFilter` glassmorphism with flat, semi-transparent fallback colors.

**Checklist for any new component that renders a visual effect:**

- **Blur** — new code should never call `BackdropFilter` directly; wrap content in `FrostedContainer(uiPerformanceMode: ...)` instead, which skips the blur entirely in performance mode rather than just lowering its sigma. A pre-existing exception is tracked in § 5.
- **Clipping** — use `Clip.hardEdge` instead of `ClipRRect`'s default (`Clip.antiAlias`) when `uiPerformanceMode` is true. Anti-aliased clipping is a sampled, layer-based operation; hard-edge is a cheap stencil. Applies to every rounded-corner image/card in the app (`AnimeCard`, `TorrentTile`, `WatchlistCard`, `CalendarCard`, `HeroCard`, etc.) — check `clipBehavior` on any new `ClipRRect`. A pre-existing exception is tracked in § 5.
- **Animation duration** — new `Animated*` widget durations should route through `perfDuration(uiPerformanceMode, normalDuration)` rather than a bare `Duration`. A zero duration still applies the end state on the next frame with no interpolation and no forced `saveLayer`, which is what actually matters for hover/focus overlays, opacity fades, and slide transitions. Pre-existing exceptions are tracked in § 5.
- **Shadows** — set `boxShadow: null` (not a smaller shadow) when `uiPerformanceMode` is true. A `BoxShadow`, however small, still costs a blur pass.
- **Images** — always pass `cacheWidth` sized to the widget's actual rendered width (× ~2–3 for pixel-density headroom); never let `Image.network` decode AniList's `extraLarge` variant at full resolution for a 170dp poster. Drop `filterQuality` to `FilterQuality.low` in performance mode.
- Don't gate a *static* value (a color, a border width) behind performance mode — only gate things that cost a compositor layer or a decode: blur, anti-aliased clipping, shadows, non-zero-duration animations, oversized image decodes.

## 3. Responsive Layouts (Mobile / PC / TV)

- Design universally for Mobile, PC, and TV.
- Maximize screen real estate on Desktop. Touch targets should be a minimum of 48x48 logical pixels on Mobile — a pre-existing exception is tracked in § 5.
- Hide PC-specific UI controls (e.g., window management, explicit fullscreen toggles) on Mobile/TV builds.
- Shared breakpoints live in `build_context_extensions.dart` (`Breakpoints.{mobile,tablet,desktop,wide}` = 600/900/1200/1500) and the column-count helpers in `responsive_grid.dart`. New screens should use these (`context.isMobile`, etc.) rather than a new hardcoded `< 600` check — § 5 tracks the current split between migrated and not-yet-migrated call sites.

## 4. Spatial Navigation & TV (D-Pad)

- Isolate D-Pad navigation exclusively to TV builds or when a physical controller is explicitly connected. Do NOT let TV focus logic bleed into standard Mobile/PC pointer/touch interactions.
- Manage spatial navigation strictly via `FocusNode` and `FocusTraversalGroup` (in practice, via the `dpad` package's `DpadRegion`/`DpadFocusable`, which wrap these).
- Display visual focus rings ONLY when `dpadModeActive` is true.

**How `dpadModeActive` is resolved** (`InputModeController`) — two independent signals, either of which can turn it on. Native bridge specifics (channel name, method, platform) live in [ARCHITECTURE.md](ARCHITECTURE.md) § 4; the design-relevant behavior is:

1. **A one-time platform check on boot**, sticky for the process lifetime — a TV's remote is its only input, so there's nothing to detect "switching away" from.
2. **Live input sniffing** — the moment a D-pad-shaped key is observed (arrow keys, select, a gamepad face button, the TV back key), `dpadModeActive` flips on; the moment a pointer-down event is observed, it flips back off. This is what lets a desktop with a connected gamepad, or a phone paired with a Bluetooth remote, get the same treatment as a real TV, and what lets a TV box with a mouse attached fall back to pointer-style UI.

This deliberately does **not** reuse Flutter's own `FocusManager.instance.highlightMode`, which defaults to "traditional" (rings visible) on desktop from the very first frame — exactly the "D-pad UI bleeding onto PC" bug this mechanism exists to prevent. `dpadModeActive` starts `false` everywhere except a confirmed TV, and only turns on after D-pad-shaped input is actually observed.

**Conventions when adding a new screen or overlay:**

- One `DpadRegion` per *visual section* (a carousel shelf, the settings popup, the theater control bar) — not one giant region per screen. Regions determine where directional focus can "escape" to (e.g., Up from a carousel escapes to the navbar).
- Give a region a `memoryKey` (e.g., `'home.trending'`, `'theater.controls'`) whenever its contents can be rebuilt or the user can navigate away and back — this is what makes "leave and return" land on the same focused card instead of resetting to the first item.
- New screens should have exactly one `autofocus: true`, placed on the single most likely first target (the play button in Theater, the first "up next" episode, the first search result). A pre-existing exception is tracked in § 5.
- Standard text inputs (`SettingsTextField`, `SearchInput`) are plain `Focus` widgets with a custom `onKeyEvent`, not `DpadFocusable` — arrow keys move the text cursor normally and only hand off to directional focus traversal at the start/end of the field's content. Give a new text field this same boundary-escape pattern rather than wrapping it in `DpadFocusable`.

## 5. Known Inconsistencies (Design Debt)

These are documented as-is per the Living Documentation Rule — **do not silently rename, resize, or "fix" these as a side effect of an unrelated PR.** Raise a dedicated design-system issue/PR if you want to formalize new tiers or complete a migration below.

- **Blur sigma has no named tiers.** Values in use today range from `10` (small icon buttons and badges — `FrostedIconButton`, the watchlist progress badge) to `50` (`SettingsMenu`'s full panel), with `12`, `16`, `20` (the `FrostedContainer` default), `30`, and `40` also in use across different components. The rough pattern is "bigger surface → higher sigma," but it isn't formalized into e.g. `BlurTier.small/medium/large` constants.
- **Border radius outliers to the "12px items / 24px panels" rule in § 1:**
  - `BatchEpisodePickerOverlay` (a genuine modal) uses 16px, not 24px.
  - `TheaterSettingsMenu` (a floating popup, arguably closer to the 12px "item" category despite being a menu) uses 12px.

  *(`CalendarCard`, the watchlist screen's `ListCard`, and `HeroCard` previously listed here have since converged onto `AppRadii.small`/`AppRadii.tag` — removed from this list accordingly.)*
- **Hardcoded colors (§ 1):** `hero_banner.dart`'s AniList/MyAnimeList external-link buttons use raw third-party brand colors (`Color(0xFF3DB4F2)`, `Color(0xFF2E51A2)`) rather than `AppPalette` — accepted as-is, since these represent another product's brand identity rather than this app's own palette. Separately, `calendar_card.dart`'s card shadow uses a raw `Color(0x4D000000)` instead of `AppPalette.black.withValues(...)` — this one is a genuine gap, not an intentional exception.
- **`anime_carousel.dart`'s `_NavArrow`** calls `BackdropFilter` directly instead of routing through `FrostedContainer` (§ 2's Blur rule), and its `ClipRRect` doesn't gate `clipBehavior` on `uiPerformanceMode` (§ 2's Clipping rule) either. Both gaps live in the same widget; not yet migrated.
- **`episode_tile.dart`** hardcodes two animation durations instead of routing them through `perfDuration(uiPerformanceMode, ...)` per § 2's Animation duration rule — the header's `AnimatedContainer` (150ms) and its `Expansible`'s `AnimationStyle` (250ms).
- **The `< 600` → `context.isMobile`/`Breakpoints` migration (§ 3) is incomplete.** `anime_details_screen.dart`, `anime_carousel.dart`, `scheduled_screen.dart`, `settings_menu.dart`, and `navbar.dart` still inline `MediaQuery.sizeOf(context).width < 600` — versus `episode_tile.dart`, `hero_banner.dart`, `torrent_tile.dart`, `search_results_screen.dart`, and `watchlist_cards.dart`'s `ListCard`, which already use `context.isMobile`. Roughly an even split today; migrate the remaining call sites opportunistically rather than in one sweeping PR.
- **`navbar.dart`'s `_NavIconButton`** (the mobile Search/Menu buttons) is a fixed 44×44, short of § 3's 48×48 minimum mobile touch target.
- **`search_filter_panel.dart`** sets `autofocus: true` on all three `ChoiceChip`s in its status-filter `.map()`, rather than exactly one per § 4's autofocus rule.

---
*Last reviewed against the codebase: 2026-07-28. Added a palette color, a blur/radius value, or a D-pad pattern? Update this file — see [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule.*
