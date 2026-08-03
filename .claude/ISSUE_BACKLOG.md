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

### 4. Add a "Continue Watching" shelf to Home

**Priority:** High · **Size:** Medium · **Ref:** `DESIGN.md` § 5.2

**Context:** The data already exists via `getUserWatchlist(status: 'CURRENT')`; it's currently reachable only inside `WatchlistScreen`'s `CURRENT` tab.

**Acceptance criteria:**

- [ ] New shelf appears near the top of `HomeScreen` when `isLoggedIn` is true (mirror the navbar's existing gating)
- [ ] Hidden entirely when logged out
- [ ] Reuses `HeroCard`/`WatchlistCard` visuals (progress bar, "Next: Episode X") rather than a new card design
- [ ] Follows the existing per-tab caching/pagination pattern already used elsewhere

**Affected files:** `home_screen.dart`, possibly a thin wrapper around existing watchlist widgets

---

### 5. Decision: top nav bar vs. left navigation rail for Android TV

**Priority:** Medium · **Size:** Small (decision only) · **Type:** Spike/decision · **Ref:** `DESIGN.md` § 5.2

**Context:** `AniStreamNavBar` is a persistent top bar today, which avoids "menu disappears on scroll," but a left-hand rail is the more common convention for the dedicated 10-foot TV case.

**Acceptance criteria:**

- [ ] Decision recorded: keep the top bar as-is, or design a TV-specific left-rail variant
- [ ] If a rail is chosen, file a separate implementation issue
- [ ] `DESIGN.md` § 5.2 updated to reflect the decision either way

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
- [ ] `episode_tile.dart`: route its two hardcoded durations (150ms, 250ms) through `perfDuration(uiPerformanceMode, ...)`
- [ ] Migrate remaining `MediaQuery.sizeOf(context).width < 600` call sites to `context.isMobile`: `anime_details_screen.dart`, `anime_carousel.dart`, `scheduled_screen.dart`, `settings_menu.dart`, `navbar.dart`
- [ ] `navbar.dart`: bump `_NavIconButton` from 44×44 to the documented 48×48 minimum
- [ ] `search_filter_panel.dart`: remove `autofocus: true` from two of the three `ChoiceChip`s, keeping exactly one

---

## Accent

### 9. Formalize named translucent-material tiers

**Priority:** Medium-High · **Size:** Medium-Large · **Ref:** `DESIGN.md` § 5.4

**Context:** `FrostedContainer` currently takes an arbitrary `sigma` per call site (10/12/16/20/30/40/50) with no semantic tiers — this is the concrete implementation work behind § 1.4's Accent layer.

**Acceptance criteria:**

- [ ] New `core/theme/` file (e.g. `app_materials.dart`) defines 2–3 named tiers as a `ThemeExtension`
- [ ] Existing `FrostedContainer` call sites migrated to the named tiers where they cleanly map; any deliberate outlier left as-is and noted
- [ ] `anime_carousel.dart`'s `_NavArrow` migrated to route through `FrostedContainer` as part of this (closes the other half of § 5.4)
- [ ] Follow-up, tracked separately: once this lands, add the new file to `ARCHITECTURE.md` § 2's folder tree and document the tiers in `DESIGN.md` § 1.4 — doc work that depends on this code existing first
