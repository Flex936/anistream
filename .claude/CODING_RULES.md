# AniStream Coding Rules

> **AniStream Docs:** [CLAUDE.md — overview & index](CLAUDE.md) · **CODING_RULES.md — tech constraints** · [DESIGN.md — UI/UX rules](DESIGN.md) · [ARCHITECTURE.md — structure & platform](ARCHITECTURE.md) · [API.md — data & caching](API.md) · [README.md — project intro](../README.md) · [CONTRIBUTING.md — PR process](CONTRIBUTING.md)
> **Covers:** the strict, enforced technical constraints on all Flutter/Dart code in this repo — performance, state management, caching, and code-generation quality standards. **See also:** [CLAUDE.md](CLAUDE.md) § 1 for project overview and working norms; [ARCHITECTURE.md](ARCHITECTURE.md) § 2 for where code implementing these rules lives; [DESIGN.md](DESIGN.md) for the UI/UX rules these performance constraints support.

## 1. Performance & State (Strict)

- Enforce `const` constructors on all static widgets.
- Render collections exclusively via `ListView.builder` or `GridView.builder`. Never map data directly into `children` arrays.
- Default to `StatelessWidget`. Restrict `StatefulWidget` to local UI mutations.
- Manage state via the two-tier pattern in [ARCHITECTURE.md](ARCHITECTURE.md) § 3: global, app-wide state exclusively via `InheritedNotifier` (the `*Scope` pattern — `SettingsScope`, `InputModeScope`); feature-local state (a single screen's pagination, tab selection, or navigation history) via a plain `ChangeNotifier` controller exposed through `ListenableBuilder`, never `InheritedNotifier`-wrapped. Do not introduce Provider, Riverpod, Bloc, Redux, or any other state-management package — this two-tier pattern is a deliberate architectural choice, not an oversight to "fix."
- Offload blocking I/O and heavy parsing (Regex/XML/JSON) to `compute()` or `Isolate.run()`.
- Implement memory TTL caching for network requests. Serve remote assets via cached image providers.

**What `flutter analyze` actually catches here:** only the first rule above has real analyzer backing — the `flutter_lints` base set enabled in `analysis_options.yaml` includes const-constructor lints, so a missing `const` on a static widget is a genuine, tool-caught warning. The other five are architectural conventions with no equivalent static-analysis rule: nothing flags a `.map()` into a `children:` array, an unnecessary `StatefulWidget`, state managed outside this section's `InheritedNotifier`/`ChangeNotifier` pattern (including introducing a rejected package), un-offloaded parsing, or a missing cache. These five are enforced by code review, not tooling — [CONTRIBUTING.md](CONTRIBUTING.md) § 6's PR checklist is written to reflect this split rather than imply a clean `flutter analyze` run covers all six.

## 2. Code Quality Directives

- Linter Compliance: satisfy `analysis_options.yaml` in full — see § 1 above for exactly which of these rules `flutter analyze` actually catches versus what's enforced by review only.
- Comment the "why" behind complex logic (Regex, Focus, FFI).
- Do not hallucinate APIs. Maintain the existing architecture — see [ARCHITECTURE.md](ARCHITECTURE.md) § 2 for the full `lib/` folder tree (`core/`, `data/`, `shared/`, `features/<name>/`) and the rule for where new code belongs.
- Reject unnecessary external dependencies; prioritize native-only solutions and SOLID/DRY principles.

## 3. Scope

This file is Flutter/Dart only. The optional companion server (`anistream_server/`) is a separate Go codebase with its own conventions in [`anistream_server/README.md`](../anistream_server/README.md) — do not apply the rules above to it, and do not fold Go coding standards into this file.

Before considering any non-trivial change finished, check it against [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule — a change that adds a dependency, a folder, a cache, a native bridge, or a design token isn't done until the matching doc is updated (or flagged) alongside it.

---
*Governed by [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule. Last reviewed against the codebase: 2026-07-28. Changed a performance rule, a caching guideline, or a code-quality directive? Update this file — and check whether [CONTRIBUTING.md](CONTRIBUTING.md) § 6's PR checklist needs the same update.*
