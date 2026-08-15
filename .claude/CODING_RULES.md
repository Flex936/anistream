# AniStream Coding Rules

> **AniStream Docs:** [CLAUDE.md](CLAUDE.md) · **CODING_RULES.md** · [DESIGN.md](DESIGN.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [API.md](API.md) · [README.md](../README.md) · [CONTRIBUTING.md](CONTRIBUTING.md)
> **Covers:** the strict, enforced technical constraints on all Flutter/Dart code in this repo — performance, state management, caching, and code-generation quality standards. **See also:** [CLAUDE.md](CLAUDE.md) § 1 for project overview and working norms; [ARCHITECTURE.md](ARCHITECTURE.md) § 2 for where code implementing these rules lives; [DESIGN.md](DESIGN.md) for the UI/UX rules these performance constraints support.

## 1. Performance & State (Strict)

- ALWAYS use `const` constructors on static widgets.
- ALWAYS render collections via `ListView.builder` or `GridView.builder`. NEVER map data directly into a `children:` array.
- A widget from a `ListView.builder`/`GridView.builder`/`SliverList`/`SliverGrid` `itemBuilder` — or any loop producing sibling widgets of the same runtime type — MUST carry an explicit `key:` whenever the underlying data can reorder, filter, insert, or delete between builds.
  - Use `ValueKey(<stable id>)` from a field unique *within that list* (`anime.id`, `MediaListEntry.media.id`) — never the loop index, since the index is exactly what stops being stable across a reorder.
  - Exception: statically fixed-composition children (`home_screen.dart`'s three named carousels) don't need one — their position and count never change independent of the data.
  - This isn't just hygiene when `autofocus: true` is involved: `autofocus` fires once, at `State` creation, and does not re-fire just because a rebuilt widget at the same position now says `autofocus: true`. An unkeyed, data-driven list with an autofocus-on-first-item pattern silently stops moving focus to the new first item after the first load — no error, no visual sign anything is wrong.
- Prefer `ValueKey`/`ObjectKey` over `GlobalKey`. Reserve `GlobalKey` for reading a descendant's `State` from outside its own subtree, or preserving a `State` across a move to a genuinely different parent within the same frame — neither applies to an ordinary reorderable/filterable list, and `GlobalKey` carries real overhead (global registry lookup, forced relocation walk) not worth paying otherwise.
  - Exception: `NavigationController._keyed` (`navigation_controller.dart`) deliberately keys every pushed screen off a monotonically incrementing `_sequence`, specifically so navigating to the same screen type twice in a row is never treated as an update-in-place. The goal there is that keys are *never* equal, not that they encode identity — a duplicate-key violation only means two siblings *under the same parent* share a key, and uniqueness only has to hold within that scope.
- Default to `StatelessWidget`. Restrict `StatefulWidget` to local UI mutations.
- Manage state via the two-tier pattern in [ARCHITECTURE.md](ARCHITECTURE.md) § 3: `InheritedNotifier` (the `*Scope` pattern — `SettingsScope`, `InputModeScope`) for global, app-wide state; a plain `ChangeNotifier` controller exposed through `ListenableBuilder` for feature-local state (a single screen's pagination, tab selection, navigation history) — never `InheritedNotifier`-wrapped.
  - FORBIDDEN: Provider, Riverpod, Bloc, Redux, or any other state-management package. This two-tier pattern is a deliberate architectural choice, not an oversight to "fix."
- ALWAYS offload blocking I/O and heavy parsing (Regex/XML/JSON) to `compute()` or `Isolate.run()`.
- ALWAYS cache network requests with an in-memory TTL. ALWAYS serve remote assets through a cached image provider.

**What `flutter analyze` actually catches here** — the `flutter_lints` base set in `analysis_options.yaml` gives real analyzer backing to exactly one rule above. The other six are architectural conventions with no static-analysis equivalent, enforced by review only — [CONTRIBUTING.md](CONTRIBUTING.md) § 6's PR checklist is written to reflect this split, not to imply a clean `flutter analyze` run covers all seven.

| Rule | Analyzer-enforced? |
| --- | --- |
| `const` constructors on static widgets | Yes — `flutter_lints` catches a missing `const` |
| `ListView.builder`/`GridView.builder`, never `.map()` into `children:` | No |
| Explicit `key:` on dynamic list items | No |
| `ValueKey`/`ObjectKey` over `GlobalKey` | No |
| `StatelessWidget` by default | No |
| Two-tier state pattern (including the rejected-package list) | No |
| Offloaded I/O/parsing, TTL caching | No |

## 2. Code Quality Directives

- ALWAYS satisfy `analysis_options.yaml` in full — see § 1's table above for exactly which rules `flutter analyze` actually catches versus review-only.
- Comment the "why" behind complex logic (Regex, Focus, FFI). Every comment describes the code's **current** behavior only:
  - FORBIDDEN: referencing the conversational or editorial process behind the code — no "as per the request," "as agreed in Phase 4," "per Track B," or similar. State what the code does and why it's built that way, not which session or turn produced it.
  - FORBIDDEN: describing a prior implementation alongside the new one — no "was X," "previously did Y," "the old version used to...". When an implementation changes, delete the stale comment entirely and write one comment describing only how the current code works.
  - FORBIDDEN: bracketing comments in long-dash/box-drawing separators (e.g. `── like this ──`). Plain `//` comments only, no decorative opening/closing marks.
- NEVER hallucinate APIs. Maintain the existing architecture — see [ARCHITECTURE.md](ARCHITECTURE.md) § 2 for the full `lib/` folder tree (`core/`, `data/`, `shared/`, `features/<name>/`) and where new code belongs.
- Reject unnecessary external dependencies. Prioritize native-only solutions and SOLID/DRY principles.

## 3. Scope

This file is Flutter/Dart only. The optional companion server (`anistream_server/`) is a separate Go codebase with its own conventions in [`anistream_server/README.md`](../anistream_server/README.md) — the rules above don't apply to it, and Go conventions don't belong in this file.

Before considering any non-trivial change finished, check it against [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule — a change that adds a dependency, a folder, a cache, a native bridge, or a design token isn't done until the matching doc is updated (or flagged) alongside it.

---
*Governed by [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule. Last reviewed against the codebase: 2026-08-15. Changed a performance rule, a caching guideline, or a code-quality directive? Update this file — and check whether [CONTRIBUTING.md](CONTRIBUTING.md) § 6's PR checklist needs the same update.*
