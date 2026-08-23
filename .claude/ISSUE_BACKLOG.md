# AniStream — Hybrid Design System: Issue Backlog

Generated from the design-system audit tying the codebase to the four-layer model now documented in `DESIGN.md` § 1 (Foundation / Structure / Aesthetic / Accent). Each entry is written as a ready-to-paste GitHub issue — title as the heading, everything below it as the body. Each references the `DESIGN.md` § 5 debt entry it would close, where one exists.

---

## Foundation

### 1. Accessibility semantics audit for hand-built focusables

**Priority:** Medium-High · **Size:** Large (spans many files) · **Ref:** `DESIGN.md` § 5.1

**Context:** `dpad` gives hand-built focusable widgets correct D-pad/keyboard focus behavior, but they aren't real Material controls, so screen readers get no semantic announcement when focus lands on them.

**Acceptance criteria:**

- [ ] `AnimeCard` wrapped with an appropriate `Semantics(button: true, label: ...)`
- [ ] `CalendarCard` wrapped similarly
- [ ] `EpisodeTile`'s header row wrapped similarly (include watched/up-next state in the label)
- [ ] `TorrentTile` wrapped similarly (include seeder count / recommended state in the label)
- [ ] `WatchlistCard` / `HeroCard` / `ListCard` (`watchlist_cards.dart`) wrapped similarly
- [ ] Settings toggle rows (`SettingRowTile`) and the nav bar's icon buttons audited too
- [ ] Pattern documented (a short doc comment, or a note added to `DESIGN.md`) so new hand-built focusables follow it going forward

**Affected files:** `anime_card.dart`, `calendar_card.dart`, `episode_tile.dart`, `torrent_tile.dart`, `watchlist_cards.dart`, `settings_components.dart`, `navbar.dart`

---

### 2. Verify system text-scaling behaves correctly

**Priority:** Low-Medium · **Size:** Small · **Ref:** `DESIGN.md` § 5.1

**Context:** No `MediaQuery`/`TextScaler` override exists today, which likely means OS text-scaling is respected by default — this hasn't been confirmed on a real device.

**Acceptance criteria:**

- [ ] Test with a large system font size set, across Settings, Watchlist, and Anime Details
- [ ] Note any widget that clips or overflows under scaling
- [ ] If any screen deliberately needs scaling disabled, document the exception and why

---

### 10. Extend `dpad` spatial navigation to AnimeDetailsScreen and WatchlistScreen

**Priority:** Medium-High · **Size:** Large · **Ref:** none — see context below

**Context:** Neither `AnimeDetailsScreen` nor `WatchlistScreen` wraps its content in a `DpadRegion`, and the widgets they're built from — `EpisodeTile`, `HeroHeaderBackButton`, `ExternalLinkButton`, `AnimeSynopsisSection`'s toggle, and every card in `watchlist_cards.dart` (`HeroCard`, `ListCard`, `WatchlistCard`) — use `HoverFocusBuilder` (a plain Flutter `FocusableActionDetector`), not `DpadFocusable`. Arrow-key movement on these two screens falls back entirely to Flutter's own default directional traversal, which doesn't cross scope boundaries the way `dpad`'s region-escape does — spatial navigation between these screens and `AniStreamNavBar` doesn't work the way it does on `HomeScreen`/`ScheduledScreen`. This wasn't found by the original design-system audit this backlog is drawn from — it surfaced during a separate D-Pad navbar-escape bug fix — so unlike the items above it has no pre-existing `DESIGN.md` § 5 entry to reference.

**Acceptance criteria:**

- [ ] Decide the approach: wrap each screen in scoped `DpadRegion`(s) while keeping `HoverFocusBuilder`, or migrate the affected widgets to `DpadFocusable` (the latter converges with Issue #1's semantics work on the same widgets)
- [ ] `AnimeDetailsScreen`'s episode list gets a `DpadRegion` with a stable `memoryKey`
- [ ] `WatchlistScreen`'s grid and list layouts get `DpadRegion` wrapping, consistent with how `AnimeCarousel`/`ScheduledScreen`'s shelves are scoped
- [ ] Confirm Up/directional escape reaches `AniStreamNavBar` from both screens (real TV, or via `Dpad.wrap`'s `debugOverlay`)
- [ ] Add a `DESIGN.md` § 5 debt entry (or fold into § 4) once the approach is decided, so this stops being an undocumented gap

**Affected files:** `anime_details_screen.dart`, `episode_tile.dart`, `hero_header_compact.dart`, `external_link_buttons.dart`, `anime_synopsis_section.dart`, `watchlist_screen.dart`, `watchlist_cards.dart`

---

## Structure

### 3. Add a Home-screen billboard / spotlight component

**Priority:** High · **Size:** Medium · **Ref:** `DESIGN.md` § 5.2

**Context:** `HeroBanner` only exists on `AnimeDetailsScreen`, after a title's already been selected. `HomeScreen` currently starts straight into shelves with no featured-title spotlight leading them.

**Acceptance criteria:**

- [ ] New widget (e.g. `HomeBillboard`) renders one anime full-bleed at the top of `HomeScreen`
- [ ] Reuses existing `Anime` data (candidate source: top result of the Trending query, or a dedicated selection rule later)
- [ ] D-pad focusable per § 4's conventions, with its own `DpadRegion`/`memoryKey`
- [ ] Respects `uiPerformanceMode` (blur/shadow/clip gating per § 2)

**Affected files:** new file in `features/home/widgets/`, `home_screen.dart`

---

  *Items #4 and #5 previously tracked here have since been resolved — removed from this list accordingly.*

---

### 6. Add genre/mood-based shelves to Home

**Priority:** Low · **Size:** Medium · **Ref:** `DESIGN.md` § 5.2

**Context:** Current Home shelves (Trending, Season Popular, All-Time Popular) are all global, not personalized. AniList's search already supports genre filtering server-side.

**Acceptance criteria:**

- [ ] One or more genre-based shelves added to `HomeScreen`, reusing `AnimeCarousel`
- [ ] Uses the existing genre-filtered search / `_AnilistCache` caching pattern rather than a new query path

---

## Aesthetic

### 7. Reconcile border-radius outliers

**Priority:** Low · **Size:** Small · **Ref:** `DESIGN.md` § 5.3

**Context:** `BatchEpisodePickerOverlay` (16px) and `TheaterSettingsMenu` (12px) don't match the documented tag/small/large scale.

**Acceptance criteria:**

- [ ] Either migrate both to existing `AppRadii` tiers, or formalize a documented 4th tier if 16px is genuinely a recurring modal size
- [ ] `DESIGN.md` § 5.3 updated to reflect the outcome (remove the entries if resolved, or note the exception explicitly if intentionally kept)

---

### 8. `DESIGN.md` § 5.3 mechanical cleanup sweep

**Priority:** Low · **Size:** Small · **Ref:** `DESIGN.md` § 5.3

**Context:** Several small, independently-reviewable consistency fixes already documented as debt — bundled here since none need separate design review the way the radius/blur formalizations do.

**Acceptance criteria:**

- [ ] `calendar_card.dart`: replace the raw `Color(0x4D000000)` shadow with `AppPalette.black.withValues(alpha: ...)`
- [ ] `episode_tile.dart`: route its hardcoded 150ms duration through `perfDuration(uiPerformanceMode, ...)`
- [ ] Migrate remaining `MediaQuery.sizeOf(context).width < 600` call sites to `context.isMobile`: `anime_details_screen.dart`, `anime_carousel.dart`, `scheduled_screen.dart`, `settings_menu.dart`, `navbar.dart`
- [ ] `navbar.dart`: bump `_NavIconButton` from 44×44 to the documented 48×48 minimum

## Platform & Playback

*Unlike the sections above, this one isn't drawn from the design-system audit — it doesn't reference a `DESIGN.md` § 5 entry, since the issue lives in native playback internals, not the design system. Tracked here per explicit request rather than in a separate document; refs point to `ARCHITECTURE.md` § 7 instead.*

*Item 9 (replace the ineffective automatic freeze mitigation with a manual restart button) has since shipped — see `ARCHITECTURE.md` § 7 for the current mitigation. Removed from this list accordingly. Filing the upstream `media-kit/media-kit` issue described there remains outstanding — worth its own tracked item if this backlog gets a general pass later.*
