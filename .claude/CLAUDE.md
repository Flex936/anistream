# AniStream Project Rules

> 📚 **AniStream Docs:** **CLAUDE.md** · [DESIGN.md](DESIGN.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [API.md](API.md) · [README.md](../README.md) · [CONTRIBUTING.md](CONTRIBUTING.md)
> **Covers:** AI/human coding rules, performance constraints, linter compliance, and the rule that keeps this whole doc suite in sync. **See also:** [DESIGN.md](DESIGN.md) for visual rules, [ARCHITECTURE.md](ARCHITECTURE.md) for where code lives.

## 1. Role & Tech Stack

- Act as a Senior Flutter/Dart Developer (Mobile/TV/Desktop).
- Stack: Flutter 3.44.8, Dart 3.12.2.
- Prioritize performance, native-only solutions, and SOLID/DRY principles. Reject unnecessary external dependencies.

## 2. Performance & State (Strict)

- Enforce `const` constructors on all static widgets.
- Render collections exclusively via `ListView.builder` or `GridView.builder`. Never map data directly into `children` arrays.
- Default to `StatelessWidget`. Restrict `StatefulWidget` to local UI mutations.
- Manage global state exclusively via `InheritedNotifier` (see the `*Scope` pattern described in [ARCHITECTURE.md](ARCHITECTURE.md)'s State Management section — `SettingsScope`, `InputModeScope`).
- Offload blocking I/O and heavy parsing (Regex/XML/JSON) to `compute()` or `Isolate.run()`.
- Implement memory TTL caching for network requests. Serve remote assets via cached image providers.

**What `flutter analyze` actually catches here:** only the first rule above has real analyzer backing — the `flutter_lints` base set enabled in `analysis_options.yaml` includes const-constructor lints, so a missing `const` on a static widget is a genuine, tool-caught warning. The other five are architectural conventions with no equivalent static-analysis rule: nothing flags a `.map()` into a `children:` array, an unnecessary `StatefulWidget`, state bypassing `InheritedNotifier`, un-offloaded parsing, or a missing cache. These five are enforced by code review, not tooling — CONTRIBUTING.md's PR checklist is written to reflect this split rather than imply a clean `flutter analyze` run covers all six.

## 3. Code Generation Directives

- Reference [DESIGN.md](DESIGN.md) for all visual styling, UI/UX philosophy, adaptive layouts, and TV focus rules.
- Linter Compliance: Ensure all generated code strictly satisfies the configuration, strict type-checking, and linter rules defined in `analysis_options.yaml`.
- Output complete, runnable files for refactors unless explicitly asked for snippets.
- Comment the "why" behind complex logic (Regex, Focus, FFI).
- Do not hallucinate APIs. Maintain the existing architecture — see [ARCHITECTURE.md](ARCHITECTURE.md) for the full `lib/` folder tree (`core/`, `data/`, `shared/`, `features/<name>/`) and the rule for where new code belongs.
- Draft an architectural plan for all non-trivial tasks. If you are unsure or if there are multiple viable approaches, present the options and ask clarifying questions so I can choose the best path. Wait for explicit user approval before generating code.
- This project is Flutter/Dart only for the purposes of this file. The optional companion server (`anistream_server/`) is a separate Go codebase with its own conventions in [`anistream_server/README.md`](../anistream_server/README.md) — do not apply the Dart-specific rules above to it, and do not fold Go coding standards into this file.
- Before considering any non-trivial change finished, check it against § 4's Living Documentation Rule below — a change that adds a dependency, a folder, a cache, a native bridge, or a design token isn't done until the matching doc is updated (or flagged) alongside it.

## 4. Documentation & the Living Documentation Rule

This project maintains six cross-referencing docs: this file, [DESIGN.md](DESIGN.md), [ARCHITECTURE.md](ARCHITECTURE.md), [API.md](API.md), and [CONTRIBUTING.md](CONTRIBUTING.md) live together in `.claude/`, while [README.md](../README.md) lives at the repository root — plus a seventh, narrower-scope doc, [`anistream_server/README.md`](../anistream_server/README.md), covering the standalone Go server in isolation (it doesn't share the other six docs' cross-linking nav bar, but is governed by the same rule below). All seven are treated as **living documents** — they describe the codebase as it actually is today, not as it was designed to be or will eventually become.

**The rule:** whenever a change to the codebase matches one of the triggers below, proactively name the affected doc(s) and propose the specific edit before or alongside the code change. Don't wait to be asked, and don't silently rewrite documentation without flagging it — the same "plan first, then get approval" discipline in § 3 applies to doc changes, not just code.

| Change | Docs to check |
| --- | --- |
| New/removed dependency in `pubspec.yaml` | [ARCHITECTURE.md](ARCHITECTURE.md); [API.md](API.md) if it's a new data source; this file if it conflicts with the dependency-rejection or `InheritedNotifier`-only rules above |
| New top-level `lib/` folder, or a new `features/<name>/` module | [ARCHITECTURE.md](ARCHITECTURE.md)'s folder tree |
| New/changed `MethodChannel`, FFI binding, or platform-specific native behavior | [ARCHITECTURE.md](ARCHITECTURE.md) § Native Platform Layer |
| New/changed rule in `analysis_options.yaml` | This file's § 2–3, [CONTRIBUTING.md](CONTRIBUTING.md)'s PR checklist |
| New external data source, or a changed GraphQL/RSS contract | [API.md](API.md) |
| Changes to the Go server's REST surface or session states | [`anistream_server/README.md`](../anistream_server/README.md), and the condensed summary in [ARCHITECTURE.md](ARCHITECTURE.md) |
| New design token (palette color, radius/blur value, animation timing) or D-pad/focus pattern | [DESIGN.md](DESIGN.md) |
| Changes to `InputModeController` / TV-detection contract | [DESIGN.md](DESIGN.md) § 4, [ARCHITECTURE.md](ARCHITECTURE.md) § Native Platform Layer (Android) |
| New cache, or a changed TTL | [API.md](API.md) § Caching |

If you notice a doc that's already out of sync with the code you're looking at — even one you didn't just change — say so. A stale doc is worse than no doc, since it actively misleads the next reader, human or AI.

---
*This file defines the Living Documentation Rule above; it has no separate file to check itself against. Last reviewed against the codebase: 2026-07-28.*
