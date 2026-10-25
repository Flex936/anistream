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
- [ ] Migrate remaining `MediaQuery.sizeOf(context).width < 600` call sites to `context.isMobile`: `anime_details_screen.dart`, `anime_carousel.dart`, `scheduled_screen.dart`, `navbar.dart`
- [ ] `navbar.dart`: bump `_NavIconButton` from 44×44 to the documented 48×48 minimum

---

### 15. Reconcile performance-mode alpha swaps with `DESIGN.md` § 2

**Priority:** Low · **Size:** Medium (spans 18 files) · **Ref:** `DESIGN.md` § 5.3

**Context:** At least 22 sites pass `uiPerformanceMode ? a : b` as a `withValues(alpha: ...)` value on scrims, toasts, tooltips, and control-bar gradients. § 2 says not to gate a static value behind performance mode, and records neither this practice nor why it exists.

**Acceptance criteria:**

- [ ] Decision made: allow raising a surface's alpha when performance mode drops its blur, or remove the gating
- [ ] If allowed, § 2 gains one bullet naming the exception and its rationale; if removed, each site uses a single alpha
- [ ] The matching `DESIGN.md` § 5.3 entry removed

**Affected files:** `selection_modal.dart`, `anime_card.dart`, `glass_toast_content.dart`, `anime_details_screen.dart`, `hero_header_compact.dart`, `watchlist_cards.dart`, `search_filter_panel.dart`, `navbar.dart`, `search_input.dart`, `settings_menu.dart`, `anime_carousel.dart`, `calendar_card.dart`, `theater_settings.dart`, `theater_controls.dart`, `theater_player.dart`, `mobile_theater_controls.dart`, `seekbar.dart`, `playback_stall_indicator.dart`

## Platform & Playback

*Unlike the sections above, this one isn't drawn from the design-system audit — it doesn't reference a `DESIGN.md` § 5 entry, since the issue lives in native playback internals, not the design system. Tracked here per explicit request rather than in a separate document; refs point to `ARCHITECTURE.md` § 7 instead.*

*(#9 shipped — see ARCHITECTURE.md § 7. Filing the upstream
media-kit/media-kit issue is still open — candidate for a future
item.)*

---

### 11. Flush `ExoTheaterScreen`'s pending AniList sync on exit

**Priority:** Medium · **Size:** Small · **Ref:** `ARCHITECTURE.md` § 7

**Context:** `AnilistTrackerService` arms a 5 s commit timer once playback passes 90%. `TheaterScreen._exitTheater` calls `flushPendingCommit()` before `dispose()`; `ExoTheaterScreen` only calls `dispose()`, which cancels the armed timer, so leaving within 5 s of crossing 90% loses the AniList sync.

**Acceptance criteria:**

- [ ] `ExoTheaterScreen._exitTheater` awaits `_tracker.flushPendingCommit()` before `Navigator.pop`, matching `TheaterScreen._exitTheater`
- [ ] Back button, Esc, and `PopScope` exits all confirmed to route through `_exitTheater`
- [ ] The matching `ARCHITECTURE.md` § 7 entry removed

**Affected files:** `exo_theater_screen.dart`

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
- [ ] Where the rationale is worth keeping, move it to the matching canonical doc (ARCHITECTURE.md, API.md, or DESIGN.md) and leave a `// See Doc.md § N.` pointer only at the canonical implementation — repeat sites get no comment
- [ ] Comment-only changes — no logic touched in the same pass
- [ ] Work file-by-file or feature-by-feature, not one sweeping PR, matching item #1's convention for large multi-file items

**Affected files:** effectively all of `lib/` — highest-density files: `theater_screen.dart`, `torrent_parser.dart`, `remote_streaming_controller.dart`, `theater_controls.dart`, `torrent_scraper_service.dart`, `styled_subtitle_view.dart`

---

### 12. Remove the dead `screenHPad` getter

**Priority:** Low · **Size:** Small · **Ref:** `ARCHITECTURE.md` § 7

**Context:** `ResponsiveContext.screenHPad` (`build_context_extensions.dart`) has no references anywhere in the repo.

**Acceptance criteria:**

- [ ] The getter and its doc comment deleted
- [ ] The matching `ARCHITECTURE.md` § 7 entry removed

**Affected files:** `build_context_extensions.dart`

---

### 13. Cancel `PlaybackStallController`'s post-drag grace timer on dispose

**Priority:** Low · **Size:** Small · **Ref:** `ARCHITECTURE.md` § 7

**Context:** `endInteraction` starts an untracked `Timer` (`_kPostInteractionGrace`); `dispose()` cancels only `_showTimer`. If the grace timer fires after disposal while playback is stalled, `_reevaluate` arms a show timer whose callback writes to the disposed `visible` notifier — a debug-mode assertion, harmless in release.

**Acceptance criteria:**

- [ ] The grace timer held in a field, replaced (not stacked) on repeat `endInteraction` calls, and cancelled in `dispose()`
- [ ] The matching `ARCHITECTURE.md` § 7 entry removed

**Affected files:** `playback_stall_controller.dart`

---

### 14. Merge `SkipChip` into `PlaybackActionChip`

**Priority:** Low · **Size:** Small · **Ref:** `ARCHITECTURE.md` § 7

**Context:** `SkipChip` and `PlaybackActionChip` both hand-build the same `Material`+`InkWell` pill with the same fade/slide animation, and `SkipChip._activeChapter` repeats `_PlaybackTimelineState._activeSkipChapter`'s chapter lookup. Only the Next Episode chip uses `PlaybackActionChip`.

**Acceptance criteria:**

- [ ] `SkipChip` renders through `PlaybackActionChip` (`visible` driven by the active chapter), leaving one copy of the pill and its animation
- [ ] One skippable-chapter lookup shared by `SkipChip` and `_PlaybackTimelineState`
- [ ] Both chips keep their current look and animation
- [ ] The matching `ARCHITECTURE.md` § 7 entry removed

**Affected files:** `skip_chip.dart`, `playback_action_chip.dart`, `theater_controls.dart`

---

### 16. Fix `HeroHeaderDelegate`'s at-rest title layer

**Priority:** Low-Medium · **Size:** Small · **Ref:** `ARCHITECTURE.md` § 7

**Context:** `_kAtRestFadeRange` is `0.00`, so `crossfadeT` is `1.0` at every scroll offset (`t / 0.00` is `Infinity` for `t > 0` and `NaN` at `t == 0`, which `num.clamp` treats as the maximum). Outside performance mode `atRestOpacity` is therefore always `0`, and the `maxLines: 1` scrolling layer draws the title at rest. A two-line title likely truncates to one line while the meta block still leaves room for two. Not confirmed on-device.

**Acceptance criteria:**

- [ ] Reproduced on a long-titled anime outside performance mode (one line with an ellipsis at rest)
- [ ] At `t == 0` the at-rest layer is fully opaque, and the scrolling layer takes over from the first scrolled pixel (or across a nonzero range)
- [ ] Performance-mode behavior unchanged
- [ ] The matching `ARCHITECTURE.md` § 7 entry removed

**Affected files:** `hero_header_delegate.dart`

---

### 17. Fix `StreamingController`'s batch-detected logging

**Priority:** Low · **Size:** Small · **Ref:** `ARCHITECTURE.md` § 7

**Context:** `StreamingController.initialize` logs "Batch torrent detected — N files" before `_batchFiles` is populated, so it always reports `0`, single-file torrents included. `selectBatchFile` repeats the line at selection time. `RemoteStreamingController` logs it after the list arrives.

**Acceptance criteria:**

- [ ] The `initialize` log removed
- [ ] The batch log emitted once, right after `_resolveFilesAndStartStream` populates `_batchFiles`
- [ ] `selectBatchFile` logs the selected file index instead, or nothing
- [ ] The matching `ARCHITECTURE.md` § 7 entry removed

**Affected files:** `streaming_controller.dart`
