# AniStream Project Rules

> 📚 **AniStream Docs:** **CLAUDE.md — overview & index** · [CODING_RULES.md — tech constraints](CODING_RULES.md) · [DESIGN.md — UI/UX rules](DESIGN.md) · [ARCHITECTURE.md — structure & platform](ARCHITECTURE.md) · [API.md — data & caching](API.md) · [README.md — project intro](../README.md) · [CONTRIBUTING.md — PR process](CONTRIBUTING.md)
> **Covers:** project orientation for AI/human contributors, the code-generation workflow norms (plan-first, complete-file output), and the rule that keeps this whole doc suite in sync. **See also:** [CODING_RULES.md](CODING_RULES.md) for the strict, enforced technical constraints on generated code, [DESIGN.md](DESIGN.md) for visual rules, [ARCHITECTURE.md](ARCHITECTURE.md) for where code lives.

## 1. Project Overview & Working Norms

- Act as a Senior Flutter/Dart Developer (Mobile/TV/Desktop) across this codebase.
- Stack: Flutter 3.44.8, Dart 3.12.2 — the definitive version pin. [CODING_RULES.md](CODING_RULES.md) enforces against these versions rather than restating them. *(Still an open item: whether this patch version needs bumping — flagged for verification against the local `pubspec.yaml`/`fvm` config.)*
- This repo is Flutter/Dart at its core, plus an optional companion Go server (`anistream_server/`) for thin clients — see [ARCHITECTURE.md](ARCHITECTURE.md) § 6 and [`anistream_server/README.md`](../anistream_server/README.md). The Go codebase has its own conventions; [CODING_RULES.md](CODING_RULES.md) is Dart-only and doesn't apply to it.
- Draft an architectural plan for all non-trivial tasks. If you are unsure or if there are multiple viable approaches, present the options and ask clarifying questions so I can choose the best path. Wait for explicit user approval before generating code.
- Output complete, runnable files for refactors unless explicitly asked for snippets.
- For the strict, tool- and review-enforced technical rules every generated change must satisfy — performance, state management, caching, linter compliance — see [CODING_RULES.md](CODING_RULES.md) in full; they aren't restated here.

## 2. Documentation & the Living Documentation Rule

This project maintains seven cross-referencing docs: this file, [CODING_RULES.md](CODING_RULES.md), [DESIGN.md](DESIGN.md), [ARCHITECTURE.md](ARCHITECTURE.md), [API.md](API.md), and [CONTRIBUTING.md](CONTRIBUTING.md) live together in `.claude/`, while [README.md](../README.md) lives at the repository root — plus an eighth, narrower-scope doc, [`anistream_server/README.md`](../anistream_server/README.md), covering the standalone Go server in isolation (it doesn't share the other seven docs' cross-linking nav bar, but is governed by the same rule below). All eight are treated as **living documents** — they describe the codebase as it actually is today, not as it was designed to be or will eventually become.

**The rule:** whenever a change to the codebase matches one of the triggers below, proactively name the affected doc(s) and propose the specific edit before or alongside the code change. Don't wait to be asked, and don't silently rewrite documentation without flagging it — the same "plan first, then get approval" discipline in § 1 applies to doc changes, not just code.

| Change | Docs to check |
| --- | --- |
| New/removed dependency in `pubspec.yaml` | [ARCHITECTURE.md](ARCHITECTURE.md); [API.md](API.md) if it's a new data source; [CODING_RULES.md](CODING_RULES.md) if it conflicts with the dependency-rejection or `InheritedNotifier`-only rules there |
| New top-level `lib/` folder, or a new `features/<name>/` module | [ARCHITECTURE.md](ARCHITECTURE.md)'s folder tree |
| New/changed `MethodChannel`, FFI binding, or platform-specific native behavior | [ARCHITECTURE.md](ARCHITECTURE.md) § Native Platform Layer |
| New/changed rule in `analysis_options.yaml`, or a new rule added to [CODING_RULES.md](CODING_RULES.md) directly | [CODING_RULES.md](CODING_RULES.md), [CONTRIBUTING.md](CONTRIBUTING.md)'s PR checklist |
| New external data source, or a changed GraphQL/RSS contract | [API.md](API.md) |
| Changes to the Go server's REST surface or session states | [`anistream_server/README.md`](../anistream_server/README.md), and the condensed summary in [ARCHITECTURE.md](ARCHITECTURE.md) |
| New design token (palette color, radius/blur value, animation timing) or D-pad/focus pattern | [DESIGN.md](DESIGN.md) |
| Changes to `InputModeController` / TV-detection contract | [DESIGN.md](DESIGN.md) § 4, [ARCHITECTURE.md](ARCHITECTURE.md) § Native Platform Layer (Android) |
| New cache, or a changed TTL | [API.md](API.md) § Caching |

If you notice a doc that's already out of sync with the code you're looking at — even one you didn't just change — say so. A stale doc is worse than no doc, since it actively misleads the next reader, human or AI.

---
*This file defines the Living Documentation Rule above; unlike the other seven docs (including [CODING_RULES.md](CODING_RULES.md)), it has no separate file to check itself against. Last reviewed against the codebase: 2026-07-28.*
