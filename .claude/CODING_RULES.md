# AniStream Coding Rules

> **AniStream Docs:** [CLAUDE.md](CLAUDE.md) · **CODING_RULES.md** · [DESIGN.md](DESIGN.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [API.md](API.md) · [README.md](../README.md) · [CONTRIBUTING.md](CONTRIBUTING.md)
> **Covers:** the strict, enforced technical constraints on all Flutter/Dart code in this repo — performance, state management, caching, and code-generation quality standards. **See also:** [CLAUDE.md](CLAUDE.md) § 1 for project overview and working norms; [ARCHITECTURE.md](ARCHITECTURE.md) § 2 for where code implementing these rules lives; [DESIGN.md](DESIGN.md) for the UI/UX rules these performance constraints support.

## 1. Performance & State (Strict)

- Enforce `const` constructors on all static widgets.
- Render collections exclusively via `ListView.builder` or `GridView.builder`. Never map data directly into `children` arrays.
- Any widget returned from a `ListView.builder`/`GridView.builder`/`SliverList`/`SliverGrid` `itemBuilder` — or any other loop producing sibling widgets of the same runtime type — **must** carry an explicit `key:` whenever the underlying data can reorder, filter, insert, or delete between builds (a carousel shelf over a re-fetchable list, a tab-switched watchlist grid). Use `ValueKey(<stable id>)` derived from a field unique *within that specific list* (an `anime.id`, a `MediaListEntry.media.id`) — never the loop index, since the index is exactly what stops being stable across a reorder. Statically fixed-composition children (e.g. `home_screen.dart`'s three named carousels) don't need one: their position and count never change independent of the data.
- This is not just hygiene when `autofocus: true` is involved. `autofocus` requests focus once, when the underlying `State` is first created — it does not re-fire just because a rebuilt widget at the same position now says `autofocus: true`. An unkeyed, data-driven list with an autofocus-on-first-item pattern (a carousel reloaded via retry, a search-results grid rebuilt on a new query, a watchlist tab switch) will silently stop moving focus to the new first item after the first load, with no error and no visual sign anything is wrong.
- Prefer `ValueKey`/`ObjectKey` over `GlobalKey` — reserve `GlobalKey` for reading a descendant's `State` from outside its own subtree, or preserving a `State` object across a move to a genuinely different parent within the same frame; neither applies to an ordinary reorderable/filterable list, and `GlobalKey` carries real overhead (global registry lookup, forced relocation walk) not worth paying otherwise.
- A duplicate-key exception means two siblings *under the same parent* share a key at once — uniqueness only has to hold within that scope. `NavigationController._keyed` (`navigation_controller.dart`) is a deliberate exception to "key from data": it keys every pushed screen off a monotonically incrementing `_sequence`, specifically so navigating to the same screen type twice in a row is never treated as an update-in-place — there the goal is that keys are *never* equal, not that they encode identity.
- Default to `StatelessWidget`. Restrict `StatefulWidget` to local UI mutations.
- Manage state via the two-tier pattern in [ARCHITECTURE.md](ARCHITECTURE.md) § 3: global, app-wide state exclusively via `InheritedNotifier` (the `*Scope` pattern — `SettingsScope`, `InputModeScope`); feature-local state (a single screen's pagination, tab selection, or navigation history) via a plain `ChangeNotifier` controller exposed through `ListenableBuilder`, never `InheritedNotifier`-wrapped. Do not introduce Provider, Riverpod, Bloc, Redux, or any other state-management package — this two-tier pattern is a deliberate architectural choice, not an oversight to "fix."
- Offload blocking I/O and heavy parsing (Regex/XML/JSON) to `compute()` or `Isolate.run()`.
- Implement memory TTL caching for network requests. Serve remote assets via cached image providers.

**What `flutter analyze` actually catches here:** only the first rule above has real analyzer backing — the `flutter_lints` base set enabled in `analysis_options.yaml` includes const-constructor lints, so a missing `const` on a static widget is a genuine, tool-caught warning. The other six are architectural conventions with no equivalent static-analysis rule: nothing flags a `.map()` into a `children:` array, an unnecessary `StatefulWidget`, state managed outside this section's `InheritedNotifier`/`ChangeNotifier` pattern (including introducing a rejected package), un-offloaded parsing, a missing cache, or a missing/index-derived key on a dynamic list item. These six are enforced by code review, not tooling — [CONTRIBUTING.md](CONTRIBUTING.md) § 6's PR checklist is written to reflect this split rather than imply a clean `flutter analyze` run covers all seven.

## 2. Code Quality Directives

- Linter Compliance: satisfy `analysis_options.yaml` in full — see § 1 above for exactly which of these rules `flutter analyze` actually catches versus what's enforced by review only.
- Comment the "why" behind complex logic (Regex, Focus, FFI) — every comment describes the code's **current** behavior only:
  - Never reference the conversational or editorial process behind the code — no "as per the request," "as agreed in Phase 4," "per Track B," or similar. State what the code does and why it's built that way, not which session or turn produced it.
  - Never describe a prior implementation alongside the new one — no "was X," "previously did Y," "the old version used to...". When an implementation changes, delete the stale comment entirely and write a single comment describing only how the current code works.
  - Don't bracket comments in long-dash/box-drawing separators (e.g. `── like this ──`). Plain `//` comments only, with no decorative opening/closing marks.
- Do not hallucinate APIs. Maintain the existing architecture — see [ARCHITECTURE.md](ARCHITECTURE.md) § 2 for the full `lib/` folder tree (`core/`, `data/`, `shared/`, `features/<name>/`) and the rule for where new code belongs.
- Reject unnecessary external dependencies; prioritize native-only solutions and SOLID/DRY principles.

## 3. Scope

This file is Flutter/Dart only. The optional companion server (`anistream_server/`) is a separate Go codebase with its own conventions in [`anistream_server/README.md`](../anistream_server/README.md) — do not apply the rules above to it, and do not fold Go coding standards into this file.

Before considering any non-trivial change finished, check it against [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule — a change that adds a dependency, a folder, a cache, a native bridge, or a design token isn't done until the matching doc is updated (or flagged) alongside it.

---
*Governed by [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule. Last reviewed against the codebase: 2026-08-11. Changed a performance rule, a caching guideline, or a code-quality directive? Update this file — and check whether [CONTRIBUTING.md](CONTRIBUTING.md) § 6's PR checklist needs the same update.*
