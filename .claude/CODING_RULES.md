# AniStream Coding Rules

> **AniStream Docs:** [CLAUDE.md](CLAUDE.md) · **CODING_RULES.md** · [DESIGN.md](DESIGN.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [API.md](API.md) · [README.md](../README.md) · [CONTRIBUTING.md](CONTRIBUTING.md)
> **Covers:** the strict, enforced technical constraints on all Flutter/Dart code in this repo — performance, state management, caching, and code-generation quality standards. **See also:** [CLAUDE.md](CLAUDE.md) § 1 for project overview and working norms; [ARCHITECTURE.md](ARCHITECTURE.md) § 2 for where code implementing these rules lives; [DESIGN.md](DESIGN.md) for the UI/UX rules these performance constraints support.

## 1. Performance & State (Strict)

- ALWAYS use `const` constructors on static widgets.
- ALWAYS render collections via `ListView.builder` or `GridView.builder`. NEVER map data directly into a `children:` array.
- Any widget from a `ListView.builder`/`GridView.builder`/`SliverList`/`SliverGrid` `itemBuilder` — or any loop producing sibling widgets of the same runtime type — MUST carry an explicit `key:` if the underlying data can reorder, filter, insert, or delete.
  - Use `ValueKey(<stable id>)` from a field unique *within that list* (`anime.id`, `MediaListEntry.media.id`) — never the loop index, which is exactly what stops being stable across a reorder.
  - Exception: statically fixed-composition children (`home_screen.dart`'s three named carousels) don't need one — their position and count never change independent of the data.
  - This is more than hygiene where `autofocus: true` is involved — `autofocus` fires once, at `State` creation, not on every rebuild. An unkeyed, data-driven list with an autofocus-on-first-item pattern silently stops moving focus to the new first item after the first load, with no error or visual sign anything is wrong.
- Prefer `ValueKey`/`ObjectKey` over `GlobalKey`. Reserve `GlobalKey` for reading a descendant's `State` from outside its own subtree, or preserving `State` across a move to a genuinely different parent in the same frame. Neither applies to an ordinary reorderable/filterable list — `GlobalKey` carries real overhead (registry lookup, forced relocation walk) not worth paying otherwise.
  - Exception: `NavigationController._keyed` (`navigation_controller.dart`) deliberately keys every pushed screen off a monotonically incrementing `_sequence`, so navigating to the same screen type twice in a row is never treated as an update-in-place. The goal is keys that are *never* equal, not keys that encode identity — a duplicate-key violation only means two siblings *under the same parent* share one; uniqueness only needs to hold within that scope.
- Default to `StatelessWidget`. Restrict `StatefulWidget` to local UI mutations.
- Manage state via the two-tier pattern in [ARCHITECTURE.md](ARCHITECTURE.md) § 3:
  - Global, app-wide state — `InheritedNotifier` (the `*Scope` pattern: `SettingsScope`, `InputModeScope`).
  - Feature-local state (a screen's pagination, tab selection, navigation history) — a plain `ChangeNotifier` controller exposed through `ListenableBuilder`, never `InheritedNotifier`-wrapped.
  - FORBIDDEN: Provider, Riverpod, Bloc, Redux, or any other state-management package. This two-tier pattern is a deliberate architectural choice, not an oversight to "fix."
- ALWAYS offload blocking I/O and heavy parsing (Regex/XML/JSON) to `compute()` or `Isolate.run()`.
- ALWAYS cache network requests with an in-memory TTL. ALWAYS serve remote assets through a cached image provider.
- Reserve `Scaffold` for `AppShell`'s persistent chrome, and for the root of a screen pushed via its own `Navigator.push` route with no ancestor `Scaffold`/`Material` (`TheaterScreen`). Use `Material` everywhere else that needs `DefaultTextStyle`/ink but not `AppBar`/`Drawer`/FAB/bottom-sheet chrome.
  - Applies to screens embedded inside `AppShell`'s existing `Scaffold` (`HomeScreen`, `AnimeDetailsScreen`) and to transient overlays (`showGeneralDialog`/`OverlayEntry` modals — `SelectionModal`) alike.
  - NEVER add a second `Scaffold`/`Material` to a widget that already renders inside an ancestor providing one — check the call chain first.

**What `flutter analyze` actually catches here:** the `flutter_lints` base set in `analysis_options.yaml` backs exactly one rule above — the other seven are architectural conventions enforced by review only. [CONTRIBUTING.md](CONTRIBUTING.md) § 6's PR checklist reflects this split; a clean `flutter analyze` run doesn't cover all eight.

| Rule | Analyzer-enforced? |
| --- | --- |
| `const` constructors on static widgets | Yes — `flutter_lints` catches a missing `const` |
| `ListView.builder`/`GridView.builder`, never `.map()` into `children:` | No |
| Explicit `key:` on dynamic list items | No |
| `ValueKey`/`ObjectKey` over `GlobalKey` | No |
| `StatelessWidget` by default | No |
| Two-tier state pattern (including the rejected-package list) | No |
| Offloaded I/O/parsing, TTL caching | No |
| `Scaffold` reserved for screen roots, `Material` elsewhere | No |

## 2. Code Quality Directives

- ALWAYS satisfy `analysis_options.yaml` in full — see § 1's table above for exactly which rules `flutter analyze` actually catches versus review-only.
- Comment the "why" behind complex logic (Regex, Focus, FFI). Every comment describes the code's **current** behavior only:
  - Default to one `//` line — up to 2 sentences only for a genuinely non-obvious mechanism, never for design rationale or anything repeated across call sites (see the table below).
  - FORBIDDEN: referencing the conversational or editorial process behind the code — no "as per the request," "as agreed in Phase 4," "per Track B," or similar. State what the code does and why it's built that way, not which session or turn produced it.
  - FORBIDDEN: describing a prior implementation alongside the new one — no "was X," "previously did Y," "the old version used to...". When an implementation changes, delete the stale comment entirely and write one comment describing only how the current code works.
  - FORBIDDEN: bracketing comments in long-dash/box-drawing separators (e.g. `── like this ──`). Plain `//` comments only, no decorative opening/closing marks.

| Comment case | Budget | Lives in |
| --- | --- | --- |
| Ordinary implementation detail | 1 line | `//` inline |
| Non-obvious mechanism (regex/FFI/focus/isolate) | ≤2 sentences | `//`/`///` inline |
| Design rationale, cross-file pattern, incident history | 0 — no inline prose | Canonical doc + `// See Doc.md § N.` pointer |

- NEVER hallucinate APIs. Maintain the existing architecture — [ARCHITECTURE.md](ARCHITECTURE.md) § 2 has the full `lib/` folder tree (`core/`, `data/`, `shared/`, `features/<name>/`) and where new code belongs.
- Reject unnecessary external dependencies. Prioritize native-only solutions and SOLID/DRY principles.

## 3. Scope

This file is Flutter/Dart only — the optional companion server (`anistream_server/`) is a separate Go codebase with its own conventions in [`anistream_server/README.md`](../anistream_server/README.md). The rules above don't apply to it, and Go conventions don't belong here.

Before considering any non-trivial change finished, check it against [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule — a change that adds a dependency, a folder, a cache, a native bridge, or a design token isn't done until the matching doc is updated (or flagged) alongside it.

---
*Governed by [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule. Last reviewed against the codebase: 2026-09-07. Changed a performance rule, a caching guideline, or a code-quality directive? Update this file — and check whether [CONTRIBUTING.md](CONTRIBUTING.md) § 6's PR checklist needs the same update.*
