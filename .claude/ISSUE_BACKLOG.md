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

  *(#4–#5 resolved — removed.)*

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

*(#9 shipped — see ARCHITECTURE.md § 7. Filing the upstream
media-kit/media-kit issue is still open — candidate for a future
item.)*

## Code Quality

*Like Platform & Playback, not drawn from the design-system audit —
this tracks a coding-rules gap found while updating the doc suite.
Refs point to CODING_RULES.md instead of DESIGN.md § 5.*

---

### 10. Retroactive comment-brevity sweep against CODING_RULES.md § 2

**Priority:** Low · **Size:** Large (spans most of `lib/`) · **Ref:** `CODING_RULES.md` § 2

**Context:** § 2 now caps comments at one line by default (≤2 sentences for a genuinely non-obvious mechanism only), with broader rationale required to move into the owning canonical doc. Most of the codebase predates this rule and still carries multi-paragraph class/method doc comments.

**Acceptance criteria:**

- [ ] Audit each file's comments against the § 2 budget; shorten or delete anything over it
- [ ] Where the rationale is worth keeping, move it to the matching canonical doc (ARCHITECTURE.md § 7, API.md, or DESIGN.md § 5) and leave a `// See Doc.md § N.` pointer in its place
- [ ] Comment-only changes — no logic touched in the same pass
- [ ] Work file-by-file or feature-by-feature, not one sweeping PR, matching item #1's convention for large multi-file items

**Affected files:** effectively all of `lib/` — highest-density starting points: `torrent_parser_worker.dart`, `next_episode_prefetch_controller.dart`, `frosted_container.dart`, `torrent_scraper_service.dart`, `styled_subtitle_view.dart`, `player_configurator.dart`
