# AniStream Design System & UI Specs

> **AniStream Docs:** [CLAUDE.md](CLAUDE.md) · [CODING_RULES.md](CODING_RULES.md) · **DESIGN.md** · [ARCHITECTURE.md](ARCHITECTURE.md) · [API.md](API.md) · [README.md](../README.md) · [CONTRIBUTING.md](CONTRIBUTING.md)
> **Covers:** visual language, performance-mode rules, responsive layout, and TV/D-pad spatial navigation. **See also:** [CODING_RULES.md](CODING_RULES.md) for how these rules are enforced when generating code, [ARCHITECTURE.md](ARCHITECTURE.md) § 2 for where the widgets implementing them live.

## 1. UI/UX Philosophy & Visual Language

AniStream's design language is a deliberate four-layer hybrid — each layer borrows one proven idea from an existing design system, scoped strictly to what that system is actually good at. No single system is adopted wholesale, and a layer should never bleed into the surface another layer owns.

### 1.1 Foundation — Material widgets + `dpad`

- Every interactive control (buttons, sliders, dropdowns, toggles, text fields) is a Flutter Material widget underneath, for its built-in focus behavior and accessibility semantics — NEVER restyled to just *look* like Material. Known exceptions (hand-built focusables missing semantics) are tracked in § 5.1.
- Spatial navigation on top of individual controls — shelf position memory, directional focus traversal, escape-to-navbar behavior — comes from the `dpad` package (`DpadRegion`/`DpadFocusable`), not from Material. See § 4 for the full spatial-navigation ruleset; this subsection just names it as part of the Foundation.
- Shared responsive infrastructure (`Breakpoints`, `context.isMobile` in `build_context_extensions.dart`) belongs here too — see § 3.

### 1.2 Structure — streaming-platform content grammar

- Home, Anime Details, Schedule, Watchlist, and Theater follow mainstream streaming-platform conventions: horizontal shelves for browsing, a full-bleed hero/spotlight treatment for a featured title, minimal persistent chrome, and a D-pad-first focus system where the focused card is always unambiguous.
- This grammar governs layout and information architecture on these content-browsing screens **only**. Settings, the search filter drawer, and the batch-file picker are transactional surfaces — they follow § 1.1's plain form conventions instead.
- **Collapsing scroll headers** use `SliverPersistentHeaderDelegate`, not `NestedScrollView` — reserve `NestedScrollView` for a screen that genuinely has a second, independently-scrolling inner region. `AnimeDetailsScreen`'s `HeroHeaderDelegate` (`features/anime_details/widgets/hero_header_delegate.dart`) is the canonical example. Two rules any new collapsing header must follow:
  - Paint an unconditionally opaque backing color *before* any cross-fading layers — a header built entirely from `Opacity`-wrapped layers has a real paint gap mid-transition that lets content scrolling up from underneath show through.
  - Reserve `kHeroHeaderNavBarClearance` (96px, matching `HomeScreen`/`ScheduledScreen`'s own top padding) at the top of both the expanded and collapsed states — `AniStreamNavBar` is transparent until scrolled past 20px, so anything painted above that line has no guaranteed backdrop in either state.

  Under `uiPerformanceMode`, the delegate hard-swaps at the midpoint instead of cross-fading every scrolled pixel, per § 2's animation-duration rule.
- Current gaps against this layer (no Home billboard, no Continue Watching shelf, etc.) are tracked in § 5.2.

### 1.3 Aesthetic — Apple-inspired restraint

Visual restraint, typographic rhythm, and motion quality, in the spirit of Apple's design sensibility — NEVER literal Apple interaction idioms (no tab bars, no SF Symbols, no sheet-based navigation).

- Source all colors strictly from `lib/core/theme/app_palette.dart` (`AppPalette.*`). Extend this palette logically if new shades are required. NEVER hardcode a color in a widget file — known exceptions are tracked in § 5.3.
- Source all text styles from `lib/core/theme/app_typography.dart` (`context.appTypography`) rather than hardcoded font sizes/weights — see that file's own doc comment for the full named-token list.
- Source border radii from `lib/core/theme/app_radii.dart` (`context.appRadii`):

  | Tier | Radius | Used by |
  | --- | --- | --- |
  | `.tag` | ~6px | Small decorative badges/pills |
  | `.small` | ~12px | List/grid item cards (`AnimeCard`, `TorrentTile`, `WatchlistCard`) |
  | `.large` | ~24px | Large slide-in panels (`SettingsMenu`, `SearchFilterPanel`, mobile nav drawer) |

  Current outliers to this table are tracked in § 5.3.
- Source poster card sizing from `lib/core/theme/app_card_sizes.dart` (`context.appCardSizes`) rather than a per-screen literal:

  | Token | Value | Used by |
  | --- | --- | --- |
  | `posterAspectRatio` | 2:3 (matches AniList's own `coverImage` art) | Every poster card (`AnimeCard`, `WatchlistCard`, `ListCard`, `CalendarCard`) |
  | `shelfWidth` | 170px | Every horizontal shelf/carousel (`AnimeCarousel`, `ScheduledScreen`'s day shelves) |
  | `gridMaxWidth` / `heroGridMaxWidth` | caps a fluid-grid card's width | `SearchResultsScreen`, `WatchlistScreen` — feeds § 3's grid column counts |

  `HeroCard`'s 16:9 landscape treatment is a deliberate exception — it renders banner art, not cover art, and doesn't use `posterAspectRatio`.
- Prioritize clean layouts, deep contrast, and seamless transitions in every new component.

### 1.4 Accent — translucent materials

- A translucent-materials system provides depth and hierarchy on floating/overlay surfaces (toasts, popups, panels) — the same idea other platforms formalize as Acrylic/Mica or Liquid Glass, without committing to either name.
- This is `BackdropFilter` blur, ALWAYS routed through the shared `FrostedContainer` widget rather than a bare `BackdropFilter` call (see § 2) — including `anime_carousel.dart`'s `_NavArrow`, previously the one exception to this.
- Blur sigma comes from three named tiers in `lib/core/theme/app_materials.dart` (`AppMaterials`), accessed via `context.appMaterials`, matching the same `ThemeExtension` pattern as `AppRadii`/`AppTypography`/`AppCardSizes`:

  | Tier | Sigma | Used by |
  | --- | --- | --- |
  | `.subtle` | 10px | Small controls (badges, icon buttons, floating pill buttons) |
  | `.standard` | 16px | Content surfaces (dropdowns, popups, menus, full-screen loading overlays) |
  | `.prominent` | 40px | Large panels (side drawers, control bars, toasts) |

- **A full-screen glassmorphic backdrop behind a centered-card modal** (`.prominent` for the backdrop, `.standard` for the card) is this layer's canonical treatment for centered modals, alongside § 1.1's side-panel pattern. One shared implementation, `SelectionModal` (`shared/widgets/selection_modal.dart`), gates the glass treatment behind an explicit `useGlassEffect` flag rather than assuming every centered modal wants it.
  - `TorrentSearchModal` sets it `true`: a real pushed route (`showGeneralDialog<Torrent>`, pops with the chosen `Torrent` as its result — the same `showDialog<T>` contract Flutter's own dialogs use), with a tap-to-dismiss backdrop.
  - `BatchEpisodePickerOverlay` sets it `false`: predates the `AppMaterials` tiers (tracked in § 5.3), and is mounted inline as a branch of `TheaterScreen`'s own state machine rather than a pushed route — no backdrop-dismiss or pop-with-value behavior to speak of.
  - `TorrentSearchModal`'s backdrop is a real, opaque widget in front of the route's own transparent `ModalBarrier`, so it carries its own tap-to-dismiss handler — `showGeneralDialog`'s `barrierDismissible` alone won't reach it.
- This is the lowest-priority layer of the four — a desktop-leaning enhancement, not something Mobile or TV correctness ever depends on.

## 2. Performance UI Mode

- Read the active performance state (`SettingsScope.of(context).uiPerformanceMode`) when building visually complex components.
- Auto-downgrade expensive rendering when performance mode is active — e.g., replace `BackdropFilter` glassmorphism with flat, semi-transparent fallback colors.

**Checklist for any new component that renders a visual effect:**

- **Blur** — NEVER call `BackdropFilter` directly; wrap content in `FrostedContainer(uiPerformanceMode: ...)` instead, which skips the blur entirely in performance mode rather than just lowering its sigma. A pre-existing exception is tracked in § 5.
- **Clipping** — use `Clip.hardEdge` instead of `ClipRRect`'s default (`Clip.antiAlias`) when `uiPerformanceMode` is true. Anti-aliased clipping is a sampled, layer-based operation; hard-edge is a cheap stencil. Applies to every rounded-corner image/card in the app (`AnimeCard`, `TorrentTile`, `WatchlistCard`, `CalendarCard`, `HeroCard`, etc.) — check `clipBehavior` on any new `ClipRRect`. A pre-existing exception is tracked in § 5.
- **Animation duration** — route new `Animated*` widget durations through `perfDuration(uiPerformanceMode, normalDuration)` rather than a bare `Duration`. A zero duration still applies the end state on the next frame with no interpolation and no forced `saveLayer`, which is what actually matters for hover/focus overlays, opacity fades, and slide transitions. Pre-existing exceptions are tracked in § 5.
- **Shadows** — set `boxShadow: null` (not a smaller shadow) when `uiPerformanceMode` is true. A `BoxShadow`, however small, still costs a blur pass.
- **Images** — ALWAYS pass `cacheWidth` sized to the widget's actual rendered width (× ~2–3 for pixel-density headroom); NEVER let `Image.network` decode AniList's `extraLarge` variant at full resolution for a 170dp poster. Drop `filterQuality` to `FilterQuality.low` in performance mode.
- Don't gate a *static* value (a color, a border width) behind performance mode — only gate things that cost a compositor layer or a decode: blur, anti-aliased clipping, shadows, non-zero-duration animations, oversized image decodes.

## 3. Responsive Layouts (Mobile / PC / TV)

- Design universally for Mobile, PC, and TV.
- Maximize screen real estate on Desktop. Touch targets on Mobile are a minimum of 48×48 logical pixels — a pre-existing exception is tracked in § 5.
- Hide PC-specific UI controls (window management, explicit fullscreen toggles) on Mobile/TV builds.
- Shared breakpoints live in `build_context_extensions.dart` (`Breakpoints.{mobile,tablet,desktop,wide}` = 600/900/1200/1500), for layout branches that need a true mobile/tablet/desktop split. New screens use `context.isMobile` rather than a new hardcoded `< 600` check — § 5 tracks the current split between migrated and not-yet-migrated call sites.
- **Grid column counts are a separate concern from breakpoints.** Card grids (`SearchResultsScreen`, `WatchlistScreen`) size their columns via `SliverGridDelegateWithMaxCrossAxisExtent`, capped at `context.appCardSizes.gridMaxWidth`/`heroGridMaxWidth` (§ 1.3) — the column count falls out of available width ÷ that cap automatically, rather than a manually maintained breakpoint-to-column-count table. New card grids follow this pattern rather than reintroducing a bespoke breakpoint table.
- **Landscape title constraint:** a title/heading rendered over a full-bleed hero/banner treatment (§ 1.2) must not exceed half the screen's width when `MediaQuery.sizeOf(context).width > height` (landscape) — long titles over wide artwork otherwise crowd out whatever sits beside or below them. `HeroHeaderDelegate`'s `contentMaxWidth` calculation is the canonical example.

## 4. Spatial Navigation & TV (D-pad)

- D-pad navigation is isolated to confirmed TV builds only. NEVER let TV focus logic bleed into standard Mobile/PC pointer/touch interactions — a connected keyboard, gamepad, or Bluetooth remote on Desktop, phone, or iOS is ordinary input there, never a TV signal.
- Manage spatial navigation strictly via `FocusNode` and `FocusTraversalGroup` (in practice, via the `dpad` package's `DpadRegion`/`DpadFocusable`, which wrap these).
- Display visual focus rings ONLY when `dpadModeActive` is true.

**How `dpadModeActive` is resolved** (`InputModeController`) — exactly one signal: a one-time platform check at boot (Android TV / Google TV "leanback" mode), sticky for the process lifetime — a TV's remote is its only input, so there's nothing to detect "switching away" from. Native bridge specifics (channel name, method, platform) live in [ARCHITECTURE.md](ARCHITECTURE.md) § 4.

This deliberately does not reuse Flutter's own `FocusManager.instance.highlightMode`, which defaults to "traditional" (rings visible) on desktop from the very first frame, before any real input has happened — exactly the "D-pad UI bleeding onto PC" bug this mechanism exists to prevent. `dpadModeActive` is `true` if and only if the app is running on a confirmed TV. FORBIDDEN: adding live D-pad/pointer input-sniffing as a second signal — it's what the mechanism above was built specifically to avoid.

**Conventions when adding a new screen or overlay:**

- One `DpadRegion` per *visual section* (a carousel shelf, the settings popup, the theater control bar) — not one giant region per screen. Regions determine where directional focus can "escape" to (e.g., Up from a carousel escapes to the navbar).
- Give a region a `memoryKey` (e.g., `'home.trending'`, `'theater.controls'`) whenever its contents can be rebuilt or the user can navigate away and back — this is what makes "leave and return" land on the same focused card instead of resetting to the first item.
- New screens should have exactly one `autofocus: true`, placed on the single most likely first target (the play button in Theater, the first "up next" episode, the first search result).
- Standard text inputs (`SettingsTextField`, `SearchInput`) are plain `Focus` widgets with a custom `onKeyEvent`, not `DpadFocusable` — arrow keys move the text cursor normally and only hand off to directional focus traversal at the start/end of the field's content. Give a new text field this same boundary-escape pattern rather than wrapping it in `DpadFocusable`.

## 5. Known Inconsistencies (Design Debt)

These are documented as-is per the Living Documentation Rule — NEVER silently rename, resize, or "fix" these as a side effect of an unrelated PR. Raise a dedicated design-system issue/PR if you want to formalize new tiers or complete a migration below. Grouped by which of § 1's four layers each item belongs to.

### 5.1 Foundation

- **Hand-built focusables lack accessibility semantics.** `AnimeCard`, `CalendarCard`, `EpisodeTile`'s header, `TorrentTile`, and similar widgets are `AnimatedContainer` + `DpadFocusable`/`GestureDetector` compositions rather than real Material controls. `dpad` gives them correct D-pad/keyboard focus behavior, but none carry an explicit `Semantics(button: true, label: ...)`, so screen readers (TalkBack/VoiceOver) announce nothing meaningful when focus lands on them.
- **System text-scaling hasn't been explicitly verified.** No `MediaQuery`/`TextScaler` override exists today, which likely means the OS text-size setting is respected by default — unconfirmed on-device across Settings, Watchlist, and Anime Details.
- **The `< 600` → `context.isMobile`/`Breakpoints` migration (§ 3) is incomplete.** `anime_details_screen.dart`, `anime_carousel.dart`, `scheduled_screen.dart`, `settings_menu.dart`, and `navbar.dart` still inline `MediaQuery.sizeOf(context).width < 600` — versus `episode_tile.dart`, `hero_banner.dart`, `torrent_tile.dart`, `search_results_screen.dart`, and `watchlist_cards.dart`'s `ListCard`, which already use `context.isMobile`. Migrate the remaining call sites opportunistically rather than in one sweeping PR.
- **`navbar.dart`'s `_NavIconButton`** (the mobile Search/Menu buttons) is a fixed 44×44, short of § 3's 48×48 minimum mobile touch target.

### 5.2 Structure

- **No Home-screen billboard.** `HeroBanner` only appears on `AnimeDetailsScreen`, after a title's already selected. `HomeScreen` goes straight from its top padding into `AnimeCarousel` shelves, with no featured-title spotlight leading them.
- **No "Continue Watching" shelf on Home.** The underlying data already exists (`getUserWatchlist(status: 'CURRENT')`) but today is reachable only via `WatchlistScreen`'s `CURRENT` tab, not surfaced on Home for logged-in users.
- **Top nav bar vs. left navigation rail on Android TV is an open, undecided question.** `AniStreamNavBar` is a persistent top `Scaffold.appBar`, which avoids the "menu disappears on scroll" antipattern, but a left-hand rail is the more common convention for the dedicated 10-foot TV case specifically.
- **Home's shelves are all global, not personalized.** Trending / Season Popular / All-Time Popular are the only three; genre- or mood-based shelves are a plausible, lower-priority addition using AniList's existing genre-filtered search.

### 5.3 Aesthetic

- **Border radius outliers to § 1.3's tag/small/large scale:**
  - `BatchEpisodePickerOverlay` and `TorrentSearchModal` (both genuine modals) use 16px, not 24px — now one shared literal inside `SelectionModal` rather than two independently hardcoded values, so resolving it is a one-line change whenever this item is formally addressed.
  - `TheaterSettingsMenu` (a floating popup, arguably closer to the 12px "item" category despite being a menu) uses 12px.

  *(`CalendarCard`, the watchlist screen's `ListCard`, and `HeroCard` previously listed here have since converged onto `AppRadii.small`/`AppRadii.tag` — removed from this list accordingly.)*
- **Hardcoded colors:** `hero_banner.dart`'s AniList/MyAnimeList external-link buttons use raw third-party brand colors (`Color(0xFF3DB4F2)`, `Color(0xFF2E51A2)`) rather than `AppPalette` — accepted as-is, since these represent another product's brand identity rather than this app's own palette. Separately, `calendar_card.dart`'s card shadow uses a raw `Color(0x4D000000)` instead of `AppPalette.black.withValues(...)` — this one is a genuine gap, not an intentional exception.
- **`episode_tile.dart`** hardcodes its header `AnimatedContainer`'s duration (150ms) instead of routing it through `perfDuration(uiPerformanceMode, ...)` per § 2's Animation duration rule.
- **`BatchEpisodePickerOverlay` has no glass/blur treatment at all** (§ 1.4) — a flat scrim and flat card surface, expressed as `useGlassEffect: false` on the shared `SelectionModal` widget both this and `TorrentSearchModal` build on. Migrating it onto `AppMaterials`'s tiers, so it opts into the same glass treatment `TorrentSearchModal` uses, is still open.

### 5.4 Accent

*(Formerly tracked two items here — "blur sigma has no named tiers" and `anime_carousel.dart`'s `_NavArrow` bypassing `FrostedContainer` — both resolved via the `AppMaterials` tiers introduced in `core/theme/app_materials.dart`; see § 1.4. Removed from this list accordingly.)*

---
*Last reviewed against the codebase: 2026-08-15. Added a palette color, a blur/radius/card-size value, or a D-pad pattern? Update this file — see [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule.*
