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

## Platform & Playback

*Unlike the sections above, this one isn't drawn from the design-system audit — it doesn't reference a `DESIGN.md` § 5 entry, since the issue lives in native playback internals, not the design system. Tracked here per explicit request rather than in a separate document; refs point to `ARCHITECTURE.md` § 7 instead.*

### 9. Replace the ineffective automatic freeze mitigation with a manual restart button

**Priority:** Medium · **Size:** Medium-Large (touches theater player lifecycle, settings, and UI) · **Ref:** `ARCHITECTURE.md` § 7

**Context:** The confirmed Linux/Wayland/NVIDIA video-freeze bug has no reliable mpv-level signal that distinguishes a frozen frame from a healthy one — every property logged is identical either way — so no automatic, timer-based heuristic can ever detect it correctly. Two were tried anyway (same-position seek, then cycling `hwdec`) and both were confirmed ineffective on real affected hardware. Source inspection traced the actual stuck layer to an EGL context inside `media_kit_video`'s Linux plugin that's isolated from Flutter's own and only gets recreated when the underlying `Player` is fully disposed — so the only thing that can actually recover from this is a full `Player`/`VideoController` restart, and since nothing in the app can detect the freeze itself, that restart has to be user-triggered.

**Plan:**

- [ ] Delete `playback_freeze_workaround_controller.dart` entirely. A manually-triggered action has no ongoing pause-duration state to track — the whole reason that class existed was to gate an *automatic* heuristic, which this replaces. The restart becomes a plain method on `_TheaterScreenState`, invoked directly by a button's `onPressed`.
- [ ] Rename `AppSettings.nudgeSeekOnResume` → `showFreezeRecoveryButton` (and its `SharedPreferences` key) — the setting's mechanism has changed shape twice now; a clean rename is warranted since nothing external depends on the old name.
- [ ] Add a settings-gated icon button to `TheaterTopBar` (next to the existing back button, reusing `FrostedIconButton`) — visible only when the setting is on, so unaffected users see zero added UI.
- [ ] On tap: capture `player.state.position`; dispose only `_player` (never `_torrentController` — `StreamingController.dispose()` deletes downloaded torrent pieces, `RemoteStreamingController.dispose()` tears down the remote session; either would force a real re-download instead of a near-instant recovery); rebuild `_player`/`_videoController` **in place within the same `TheaterScreen` State** — `pushReplacement`-ing a new screen was considered and rejected, since it resolves `AnimeDetailsScreen`'s `await Navigator.push(...)` early and would fire `_fetchProgress()` at the wrong time; re-open `_torrentController.streamUrl` (left running, untouched) into the fresh player; seek to the captured position minus a small fixed rewind (clamped to `>= Duration.zero`); resume.
- [ ] `_player`/`_videoController` need to become mutable fields (no longer `late final`). `_autoSkipController`, `_playbackDiagnostics`, `_controlsVisibility`, and the `_posSub` subscription all capture `Player` at construction and need rebuilding against the new instance — extract this into one `_buildPlayerScopedResources()` method used both by `initState` and the restart handler, so there's exactly one construction path rather than two that can drift apart. `_tracker` (`AnilistTrackerService`) doesn't capture `Player` directly and needs no changes.
- [ ] File an upstream issue against `media-kit/media-kit` describing the isolated-EGL-context finding — the root cause isn't fixable from this codebase, and this evidence (confirmed-healthy decode, stuck presentation, exact file/line, platform correlation) is worth reporting regardless of whether the manual-restart mitigation ships.
- [ ] Update `ARCHITECTURE.md` § 7's entry once this ships, since it currently describes the (now superseded) automatic hwdec-cycle mitigation as the current state.

**Affected files:** `lib/core/settings/settings_service.dart`, `lib/features/settings/settings_menu.dart`, `lib/features/theater/services/playback_freeze_workaround_controller.dart` (deleted), `lib/features/theater/theater_screen.dart`, `lib/features/theater/widgets/theater_player.dart`
