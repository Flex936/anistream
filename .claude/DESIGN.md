# AniStream Design System & UI Specs

> 📚 **AniStream Docs:** [CLAUDE.md](CLAUDE.md) · **DESIGN.md** · [ARCHITECTURE.md](ARCHITECTURE.md) · [API.md](API.md) · [README.md](../README.md) · [CONTRIBUTING.md](CONTRIBUTING.md)
> **Covers:** visual language, performance-mode rules, responsive layout, and TV/D-pad spatial navigation. **See also:** [CLAUDE.md](CLAUDE.md) for how these rules are enforced when generating code, [ARCHITECTURE.md](ARCHITECTURE.md) for where the widgets implementing them live.

## 1. UI/UX Philosophy & Visual Language

- Execute a premium, Apple/Spotify-inspired UI/UX. Prioritize clean layouts, deep contrasts, and seamless transitions.
- Source all colors strictly from `lib/core/theme/app_palette.dart`. Extend this palette logically if new shades are required. NEVER hardcode color values in widget files.
- Enforce a strictly scaled typography system. Avoid hardcoded font sizes.
- Standardize border radiuses: **~12px** for list/grid item cards (`AnimeCard`, `TorrentTile`, the watchlist grid's `WatchlistCard`), **~24px** for large slide-in panels (`SettingsMenu`, `SearchFilterPanel`, the mobile nav drawer). See § 5 for current outliers to this rule.
- Utilize Glassmorphism heavily for overlays, toasts, and floating elements using `BackdropFilter` — always routed through the shared `FrostedContainer` widget, never a bare `BackdropFilter` call (see § 2).

## 2. Performance UI Mode

- Read the active performance state (`SettingsScope.of(context).uiPerformanceMode`) when building visually complex components.
- Auto-downgrade expensive rendering when performance mode is active — e.g., replace `BackdropFilter` glassmorphism with flat, semi-transparent fallback colors.

**Checklist for any new component that renders a visual effect:**

- **Blur** — never call `BackdropFilter` directly. Wrap content in `FrostedContainer(uiPerformanceMode: ...)`; it skips the blur entirely in performance mode rather than just lowering its sigma.
- **Clipping** — use `Clip.hardEdge` instead of `ClipRRect`'s default (`Clip.antiAlias`) when `uiPerformanceMode` is true. Anti-aliased clipping is a sampled, layer-based operation; hard-edge is a cheap stencil. Applies to every rounded-corner image/card in the app (`AnimeCard`, `TorrentTile`, `WatchlistCard`, `CalendarCard`, `HeroCard`, etc.) — check `clipBehavior` on any new `ClipRRect`.
- **Animation duration** — route any `Animated*` widget's duration through `perfDuration(uiPerformanceMode, normalDuration)` rather than a bare `Duration`. A zero duration still applies the end state on the next frame with no interpolation and no forced `saveLayer`, which is what actually matters for hover/focus overlays, opacity fades, and slide transitions.
- **Shadows** — set `boxShadow: null` (not a smaller shadow) when `uiPerformanceMode` is true. A `BoxShadow`, however small, still costs a blur pass.
- **Images** — always pass `cacheWidth` sized to the widget's actual rendered width (× ~2–3 for pixel-density headroom); never let `Image.network` decode AniList's `extraLarge` variant at full resolution for a 170dp poster. Drop `filterQuality` to `FilterQuality.low` in performance mode.
- Don't gate a *static* value (a color, a border width) behind performance mode — only gate things that cost a compositor layer or a decode: blur, anti-aliased clipping, shadows, non-zero-duration animations, oversized image decodes.

## 3. Responsive Layouts (Mobile / PC / TV)

- Design universally for Mobile, PC, and TV.
- Maximize screen real estate on Desktop. Ensure touch targets are a minimum of 48x48 logical pixels on Mobile.
- Hide PC-specific UI controls (e.g., window management, explicit fullscreen toggles) on Mobile/TV builds.
- Shared breakpoints live in `build_context_extensions.dart` (`Breakpoints.{mobile,tablet,desktop,wide}` = 600/900/1200/1500) and the column-count helpers in `responsive_grid.dart`. Use these instead of a new hardcoded `< 600` check per screen.

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
- Exactly one `autofocus: true` per screen, placed on the single most likely first target (the play button in Theater, the first "up next" episode, the first search result).
- Standard text inputs (`SettingsTextField`, `SearchInput`) are plain `Focus` widgets with a custom `onKeyEvent`, not `DpadFocusable` — arrow keys move the text cursor normally and only hand off to directional focus traversal at the start/end of the field's content. Give a new text field this same boundary-escape pattern rather than wrapping it in `DpadFocusable`.

## 5. Known Inconsistencies (Design Debt)

These are documented as-is per the Living Documentation Rule — **do not silently rename, resize, or "fix" these as a side effect of an unrelated PR.** Raise a dedicated design-system issue/PR if you want to formalize new tiers.

- **Blur sigma has no named tiers.** Values in use today range from `10` (small icon buttons and badges — `FrostedIconButton`, the watchlist progress badge) to `50` (`SettingsMenu`'s full panel), with `12`, `16`, `20` (the `FrostedContainer` default), `30`, and `40` also in use across different components. The rough pattern is "bigger surface → higher sigma," but it isn't formalized into e.g. `BlurTier.small/medium/large` constants.
- **Border radius outliers to the "12px items / 24px panels" rule in § 1:**
  - `CalendarCard` uses 10px/9px (outer/inner), not 12px.
  - The watchlist screen's `ListCard` (list-view row) and `HeroCard` (featured "Watching" card) use 16px/15px, not 12px.
  - `BatchEpisodePickerOverlay` (a genuine modal) uses 16px, not 24px.
  - `TheaterSettingsMenu` (a floating popup, arguably closer to the 12px "item" category despite being a menu) uses 12px.

---
*Last reviewed against the codebase: 2026-07-28. Added a palette color, a blur/radius value, or a D-pad pattern? Update this file — see CLAUDE.md's Living Documentation Rule (§ 4).*
