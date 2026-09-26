# AniStream Design System & UI Specs

> **AniStream Docs:** [CLAUDE.md](CLAUDE.md) · [CODING_RULES.md](CODING_RULES.md) · **DESIGN.md** · [ARCHITECTURE.md](ARCHITECTURE.md) · [API.md](API.md) · [README.md](../README.md) · [CONTRIBUTING.md](CONTRIBUTING.md)
> **Covers:** visual language, performance-mode rules, responsive layout, and TV/D-pad spatial navigation. **See also:** [CODING_RULES.md](CODING_RULES.md) for how these rules are enforced when generating code, [ARCHITECTURE.md](ARCHITECTURE.md) § 2 for where the widgets implementing them live.

## 1. UI/UX Philosophy & Visual Language

AniStream's design language is a deliberate four-layer hybrid — each layer borrows one idea from an existing design system, scoped to what that system does best. No layer bleeds into another's surface, and no system is adopted wholesale.

### 1.1 Foundation — Material widgets + `dpad`

- Build every interactive control (buttons, sliders, dropdowns, toggles, text fields) on a real Flutter Material widget, for its built-in focus behavior and accessibility semantics. NEVER restyle one to just *look* like Material — exceptions tracked in § 5.1.
- Use the shared `AppSegmentedControl` (`shared/widgets/app_segmented_control.dart`, a `SegmentedButton` wrapper) for mutually-exclusive option groups (status filters, tab switchers). NEVER `CupertinoSlidingSegmentedControl` or a hand-rolled tab-row widget.
- Spatial navigation (shelf position memory, directional focus traversal, escape-to-navbar) comes from the `dpad` package (`DpadRegion`/`DpadFocusable`), not Material — full ruleset in § 4.
- Shared responsive infrastructure (`Breakpoints`, `context.isMobile` in `build_context_extensions.dart`) also lives here — see § 3.

### 1.2 Structure — streaming-platform content grammar

- Home, Anime Details, Schedule, Watchlist, and Theater follow mainstream streaming-platform conventions: horizontal shelves for browsing, a full-bleed hero/spotlight for a featured title, minimal persistent chrome, and D-pad-first focus where the focused card is always unambiguous.
- This grammar governs layout only on these content-browsing screens — Settings, the search filter drawer, and the batch-file picker are transactional surfaces that follow § 1.1's plain form conventions instead.
- **Collapsing scroll headers** use `SliverPersistentHeaderDelegate`, not `NestedScrollView` — reserve `NestedScrollView` for a screen with a genuine second, independently-scrolling inner region. Canonical example: `AnimeDetailsScreen`'s `HeroHeaderDelegate` (`features/anime_details/widgets/hero_header_delegate.dart`). Any new collapsing header must:
  - Paint an opaque backing color before any cross-fading layer — an all-`Opacity` header has a real paint gap mid-transition, letting content scrolling up from underneath show through.
  - Reserve `kHeroHeaderNavBarClearance` (96px, matching `HomeScreen`/`ScheduledScreen`'s own top padding) at the top of both expanded and collapsed states — `AniStreamNavBar` stays transparent until scrolled past 20px, so anything above that line has no guaranteed backdrop either way.

  Under `uiPerformanceMode`, hard-swap at the midpoint instead of cross-fading every scrolled pixel (§ 2's animation-duration rule).
- Current gaps against this layer (no Home billboard, no Continue Watching shelf, etc.) are tracked in § 5.2.

### 1.3 Aesthetic — Apple-inspired restraint

Visual restraint, typographic rhythm, and motion quality, in Apple's design spirit — NEVER literal Apple interaction idioms (tab bars, SF Symbols, sheet-based navigation).

- Source all colors from `lib/core/theme/app_palette.dart` (`AppPalette.*`), extending it logically for new shades. NEVER hardcode a color in a widget file — exceptions: § 5.3.
- Source all text styles from `lib/core/theme/app_typography.dart` (`context.appTypography`) rather than hardcoded font sizes/weights — the named tokens are `AppTypography`'s fields. Exceptions: § 5.3.
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

- A translucent-materials system gives floating/overlay surfaces (toasts, popups, panels) depth and hierarchy — the same idea other platforms formalize as Acrylic/Mica or Liquid Glass, without committing to either name.
- This is `BackdropFilter` blur, ALWAYS routed through `FrostedContainer` — never a bare `BackdropFilter` call (§ 2).
- Blur sigma comes from three named tiers in `lib/core/theme/app_materials.dart` (`AppMaterials`), accessed via `context.appMaterials` — the same `ThemeExtension` pattern as `AppRadii`/`AppTypography`/`AppCardSizes`:

  | Tier | Sigma | Used by |
  | --- | --- | --- |
  | `.subtle` | 10px | Small controls (badges, icon buttons, floating pill buttons) |
  | `.standard` | 16px | Content surfaces (dropdowns, popups, menus, full-screen loading overlays) |
  | `.prominent` | 40px | Large panels (side drawers, control bars, toasts) |

- **A full-screen glassmorphic backdrop behind a centered-card modal** (`.prominent` for the backdrop, `.standard` for the card) is this layer's canonical centered-modal treatment, alongside § 1.1's side-panel pattern. `SelectionModal` (`shared/widgets/selection_modal.dart`) is the one shared implementation; it gates the glass treatment behind an explicit `useGlassEffect` flag rather than assuming every centered modal wants it:

  | Widget | `useGlassEffect` | Mount | Dismiss |
  | --- | --- | --- | --- |
  | `TorrentSearchModal` | `true` | Pushed route (`showGeneralDialog<Torrent>`, pops with the chosen `Torrent` — Flutter's own `showDialog<T>` contract) | Own opaque backdrop in front of the route's transparent `ModalBarrier`, with its own tap-to-dismiss handler |
  | `BatchEpisodePickerOverlay` | `false` | Inline branch of `TheaterScreen`'s own state machine, not a pushed route — predates the `AppMaterials` tiers (§ 5.3) | None — no backdrop-dismiss or pop-with-value |

- Toggling `uiPerformanceMode` live changes `FrostedContainer`'s internal ancestor chain, which would otherwise remount `child`'s whole subtree and reset its state — a caller whose `child` holds state worth preserving passes a stable `preservationKey` (`settings_menu.dart`'s `_frostedBodyKey` is the canonical example).
- ALWAYS treat frosted glass as the default finish for floating/content surfaces — flat color is the exception, not the norm.
- NEVER treat this layer as skippable on its own judgment; § 2 is the only thing allowed to turn it off, and it turns it off completely.

## 2. Performance UI Mode

- Performance Mode is an absolute reversion to plain Material — NEVER a partial dial-down of frosted glass or any other effect.
- ALWAYS read `SettingsScope.of(context).uiPerformanceMode` in a visually complex component and remove each effect below outright when true — not lower it.

**Checklist for any new component that renders a visual effect:**

- **Blur** — NEVER call `BackdropFilter` directly. Wrap content in `FrostedContainer(uiPerformanceMode: ...)`, which skips the blur entirely rather than lowering its sigma. A pre-existing exception is tracked in § 5.
- **Clipping** — use `Clip.hardEdge` instead of `ClipRRect`'s default (`Clip.antiAlias`) when `uiPerformanceMode` is true — anti-aliased clipping is a sampled, layer-based operation, hard-edge is a cheap stencil. Applies to every rounded-corner image/card (`AnimeCard`, `TorrentTile`, `WatchlistCard`, `CalendarCard`, `HeroCard`, etc.) — check `clipBehavior` on any new `ClipRRect`. A pre-existing exception is tracked in § 5.
- **Animation duration** — route new `Animated*` widget durations through `perfDuration(uiPerformanceMode, normalDuration)` rather than a bare `Duration`. A zero duration still applies the end state on the next frame with no interpolation and no forced `saveLayer` — what actually matters for hover/focus overlays, opacity fades, and slide transitions. Pre-existing exception: § 5.3.
- **Shadows** — set `boxShadow: null` (not a smaller shadow) when `uiPerformanceMode` is true. A `BoxShadow`, however small, still costs a blur pass.
- **Images** — ALWAYS pass `cacheWidth` sized to the widget's actual rendered width (× ~2–3 for pixel-density headroom); NEVER let `Image.network` decode AniList's `extraLarge` variant at full resolution for a 170dp poster. Drop `filterQuality` to `FilterQuality.low` in performance mode.
- Don't gate a *static* value (a color, a border width) behind performance mode — only gate what costs a compositor layer or a decode: blur, anti-aliased clipping, shadows, non-zero-duration animations, oversized image decodes.

## 3. Responsive Layouts (Mobile / PC / TV)

- Design universally for Mobile, PC, and TV.
- Maximize screen real estate on Desktop.
- Touch targets on Mobile: minimum 48×48 logical pixels — exception tracked in § 5.1.
- Hide PC-specific UI controls (window management, explicit fullscreen toggles) on Mobile/TV builds.
- Shared breakpoints live in `build_context_extensions.dart` (`Breakpoints.{mobile,tablet,desktop,wide}` = 600/900/1200/1500) for layout branches needing a true mobile/tablet/desktop split. New screens use `context.isMobile`, not a hardcoded `< 600` check — § 5.1 tracks the current migration split.
- **Grid column counts are a separate concern from breakpoints.** Card grids (`SearchResultsScreen`, `WatchlistScreen`) size columns via `SliverGridDelegateWithMaxCrossAxisExtent`, capped at `context.appCardSizes.gridMaxWidth`/`heroGridMaxWidth` (§ 1.3) — column count falls out of available width ÷ cap automatically, not a manually maintained breakpoint table. New card grids follow this pattern.
- **Landscape title constraint:** a title over a full-bleed hero/banner (§ 1.2) must not exceed half the screen's width in landscape (`MediaQuery.sizeOf(context).width > height`) — otherwise it crowds out whatever sits beside or below it. Canonical example: `HeroHeaderDelegate`'s `contentMaxWidth` calculation.

## 4. Spatial Navigation & TV (D-pad)

- D-pad navigation is isolated to confirmed TV builds. NEVER let TV focus logic bleed into Mobile/PC pointer/touch — a connected keyboard, gamepad, or Bluetooth remote on Desktop, phone, or iOS is ordinary input there, never a TV signal.
- Manage spatial navigation strictly via `FocusNode` and `FocusTraversalGroup` (in practice, via the `dpad` package's `DpadRegion`/`DpadFocusable`, which wrap these).
- Display visual focus rings ONLY when `dpadModeActive` is true.
- A route stacked on `AppShell` (`TheaterScreen`, `ExoTheaterScreen`, any dialog/bottom sheet on the same Navigator) must not leave the covered screen's `DpadFocusable`s Tab- or D-Pad-reachable — `MaterialPageRoute`'s default `maintainState` keeps it mounted underneath. `AppShell` enforces this via `ExcludeFocus(excluding: !isCurrentRoute)` around its `Scaffold`, keyed off `ModalRoute.of(context)?.isCurrent`.

**How `dpadModeActive` is resolved** (`InputModeController`): exactly one signal — a one-time platform check at boot (Android TV / Google TV "leanback" mode), sticky for the process lifetime, since a TV's remote is its only input. Native bridge specifics (channel name, method, platform): [ARCHITECTURE.md](ARCHITECTURE.md) § 4.

This deliberately skips Flutter's own `FocusManager.instance.highlightMode`, which defaults to "traditional" (rings visible) on desktop from the first frame, before any real input — exactly the "D-pad UI bleeding onto PC" bug this mechanism prevents. `dpadModeActive` is `true` if and only if the app runs on a confirmed TV. FORBIDDEN: adding live D-pad/pointer input-sniffing as a second signal — that's exactly what this mechanism avoids.

**Conventions when adding a new screen or overlay:**

- One `DpadRegion` per *visual section* (a carousel shelf, the settings popup, the theater control bar) — not one giant region per screen. Regions decide where directional focus "escapes" to (e.g., Up from a carousel escapes to the navbar).
- Give a region a `memoryKey` (e.g., `'home.trending'`, `'theater.controls'`) whenever its contents can be rebuilt or the user can leave and return — this is what makes "leave and return" land on the same focused card instead of resetting to the first item.
- New screens get exactly one `autofocus: true`, on the single most likely first target (the play button in Theater, the first "up next" episode, the first search result).
- Standard text inputs (`SettingsTextField`, `SearchInput`) are plain `Focus` widgets with a custom `onKeyEvent`, not `DpadFocusable` — arrow keys move the cursor normally, handing off to directional focus traversal only at the start/end of the field's content. Give a new text field this same boundary-escape pattern rather than wrapping it in `DpadFocusable`.
- Wrap a Material control that traps or fragments arrow-key focus in an outer `Focus` whose `onKeyEvent` handles Left/Right only, so Up/Down bubble to traversal:
  - `Slider` binds all four arrow keys and always reports `handled` — give it a `FocusNode(canRequestFocus: false, skipTraversal: true)` (`SearchFilterPanel`'s two sliders).
  - `SegmentedButton` exposes one focus target per segment — set `descendantsAreFocusable: false` (`AppSegmentedControl`).
- `TheaterScreen`'s keyboard shortcuts register on `HardwareKeyboard.instance`, not the focus chain — its controls subtree sits in an `ExcludeFocus` while auto-hidden, so a focus-bubbling dispatcher would stop receiving events. `ExoTheaterScreen` mirrors the approach.
  - The handler bypasses focus-tree consumption, so a widget with its own arrow handling reports focus upstream (`onSeekbarFocusChange`, `onVolumeFocusChange`) and the handler returns `false` for those keys.
  - It is inactive on TV (`isTvPlatform`, where the same keys drive D-pad traversal) and while a sub-menu is open; Esc/Back always fires.
  - Ctrl+→ (exact 90-second skip) ignores those guards — `Seekbar` ignores Ctrl-held arrows.

## 5. Known Inconsistencies (Design Debt)

Documented as-is per the Living Documentation Rule — NEVER silently rename, resize, or "fix" these as a side effect of an unrelated PR. Raise a dedicated design-system issue/PR to formalize a new tier or complete a migration. Grouped by § 1's four layers.

### 5.1 Foundation

- **Hand-built focusables lack accessibility semantics.** `AnimeCard`, `CalendarCard`, `EpisodeTile`'s header, `TorrentTile`, and similar widgets are `AnimatedContainer` + `DpadFocusable`/`GestureDetector` compositions, not real Material controls — `dpad` gives them correct focus behavior, but none carry a `Semantics(button: true, label: ...)`, so screen readers (TalkBack/VoiceOver) announce nothing on focus.
- **System text-scaling is unverified.** No `MediaQuery`/`TextScaler` override exists, so the OS text-size setting is likely respected by default — not confirmed on-device across Settings, Watchlist, and Anime Details.
- **The `< 600` → `context.isMobile`/`Breakpoints` migration (§ 3) is incomplete.** Still inline `MediaQuery.sizeOf(context).width < 600`: `anime_details_screen.dart`, `anime_carousel.dart`, `scheduled_screen.dart`, `navbar.dart`. Already on `context.isMobile`: `episode_tile.dart`, `hero_banner.dart`, `torrent_tile.dart`, `search_results_screen.dart`, `settings_menu.dart`, `watchlist_cards.dart`'s `ListCard`. Migrate remaining call sites opportunistically, not in one sweeping PR.
- **`navbar.dart`'s `_NavIconButton`** (the mobile Search/Menu buttons) is a fixed 44×44, short of § 3's 48×48 minimum mobile touch target.
- **Theater's playback-action chips aren't D-pad reachable.** `PlaybackActionChip` (`features/theater/widgets/playback_action_chip.dart` — both the OP/ED/preview skip chip and the Next Episode chip) is a plain `Material`+`InkWell`, mouse/touch only, no `DpadFocusable`. A TV remote user can't trigger either; playback just continues naturally instead. Pre-existing for the skip chip, deliberately carried forward into the Next Episode chip rather than fixed as an unrelated side effect.

### 5.2 Structure

- **No Home-screen billboard.** `HeroBanner` only appears on `AnimeDetailsScreen`, after a title's selected — `HomeScreen` goes straight from its top padding into `AnimeCarousel` shelves, no featured-title spotlight leading them.
- **No "Continue Watching" shelf on Home.** The data exists (`getUserWatchlist(status: 'CURRENT')`) but is reachable only via `WatchlistScreen`'s `CURRENT` tab, not surfaced on Home for logged-in users.
- **Top nav bar vs. left navigation rail on Android TV is open.** `AniStreamNavBar` is a persistent top `Scaffold.appBar` — avoids the "menu disappears on scroll" antipattern, but a left-hand rail is the more common convention for 10-foot TV specifically.
- **Home's shelves are all global, not personalized.** Trending / Season Popular / All-Time Popular are the only three; genre- or mood-based shelves are a plausible, lower-priority addition using AniList's existing genre-filtered search.

### 5.3 Aesthetic

- **Border radius outliers to § 1.3's tag/small/large scale:**
  - `BatchEpisodePickerOverlay` and `TorrentSearchModal` (both genuine modals) use 16px, not 24px — one shared literal inside `SelectionModal` now, not two hardcoded values, so fixing it is a one-line change.
  - `TheaterSettingsMenu` (a floating popup, arguably closer to the 12px "item" tier despite being a menu) uses 12px.

  *(Resolved: `CalendarCard`, `ListCard`, `HeroCard` now use `AppRadii.small`/`.tag`.)*

- **Hardcoded colors:** `hero_banner.dart`'s AniList/MyAnimeList link buttons use raw third-party brand colors (`Color(0xFF3DB4F2)`, `Color(0xFF2E51A2)`) instead of `AppPalette` — accepted, since these are another product's brand identity, not this app's palette. `calendar_card.dart`'s card shadow uses a raw `Color(0x4D000000)` instead of `AppPalette.black.withValues(...)` — a genuine gap, not an intentional exception.
- **Typography tokens don't cover every text style:**
  - Token names drift from use sites — `cardTitleCompact` also drives `AppSegmentedControl`'s segment labels (Watchlist's tabs), `cardTitleProminent` `WatchlistScreen`'s `_EmptyPane` title.
  - One-off styles stay plain `TextStyle` literals where no token matches size, weight, or height — 11pt captions, form-field labels, primary CTA text, the poster score badge (deliberately heavier than `metaLabel`), and wrapped error/empty-state text, where `cardSummary`'s `height` would visibly change line spacing. Accepted, not drift.
- **`episode_tile.dart`** hardcodes its header `AnimatedContainer`'s duration (150ms) instead of routing it through `perfDuration(uiPerformanceMode, ...)` per § 2's Animation duration rule.
- **`BatchEpisodePickerOverlay` has no glass/blur treatment** (§ 1.4) — flat scrim, flat card, via `useGlassEffect: false` on the shared `SelectionModal` both it and `TorrentSearchModal` build on. Migrating it onto `AppMaterials`'s tiers is still open.

### 5.4 Accent

*(No open items — resolved via the `AppMaterials` tiers, § 1.4.)*

---
*Last reviewed against the codebase: 2026-09-20. Added a palette color, a blur/radius/card-size value, or a D-pad pattern? Update this file — see [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule.*
