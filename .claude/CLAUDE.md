# AniStream Project Rules

> **AniStream Docs:** **CLAUDE.md — overview & index** · [CODING_RULES.md — tech constraints](CODING_RULES.md) · [DESIGN.md — UI/UX rules](DESIGN.md) · [ARCHITECTURE.md — structure & platform](ARCHITECTURE.md) · [API.md — data & caching](API.md) · [README.md — project intro](../README.md) · [CONTRIBUTING.md — PR process](CONTRIBUTING.md)
> **Covers:** project orientation for AI/human contributors, the code-generation workflow norms (plan-first, complete-file output), and the rule that keeps this whole doc suite in sync. **See also:** [CODING_RULES.md](CODING_RULES.md) for the strict, enforced technical constraints on generated code, [DESIGN.md](DESIGN.md) for visual rules, [ARCHITECTURE.md](ARCHITECTURE.md) for where code lives.

## 1. Project Overview & Working Norms

- Act as a Senior Flutter/Dart Developer (Mobile/TV/Desktop) across this codebase.
- Stack: Flutter ≥3.44.0, Dart ^3.12.2 — matching `pubspec.yaml`'s actual `environment:` constraint. Dart carries that caret constraint explicitly; Flutter itself has no exact-patch pin in `pubspec.yaml`, only the ≥3.44.0 floor `pubspec.lock` resolves to. [CODING_RULES.md](CODING_RULES.md) enforces against these versions rather than restating them.
- This repo is Flutter/Dart at its core, plus an optional companion Go server (`anistream_server/`) for thin clients — see [ARCHITECTURE.md](ARCHITECTURE.md) § 6 and [`anistream_server/README.md`](../anistream_server/README.md). The Go codebase has its own conventions; [CODING_RULES.md](CODING_RULES.md) is Dart-only and doesn't apply to it.
- Draft an architectural plan for all non-trivial tasks. If you are unsure or if there are multiple viable approaches, present the options and ask clarifying questions so I can choose the best path. Wait for explicit user approval before generating code.
- Output complete, runnable files for refactors unless explicitly asked for snippets.
- Documentation content describes the codebase and product as they stand today — never the conversational or approval process that produced an edit. Avoid phrasing like "per Track B" or "as agreed in an earlier pass"; state what changed and why it matters to a reader, not which internal editing step produced the change. (Legitimate change-history notes — e.g., [DESIGN.md](DESIGN.md) § 5 marking a design-debt item as resolved — are a different, acceptable thing: they describe resolved *product* debt, not the *editing session* that resolved it.) This same principle governs source-code comments, not just prose documentation — see [CODING_RULES.md](CODING_RULES.md) § 2 for the code-comment-specific version (no session/phase references, no "was X" history, no long-dash comment brackets).
- For the strict, tool- and review-enforced technical rules every generated change must satisfy — performance, state management, caching, linter compliance — see [CODING_RULES.md](CODING_RULES.md) in full; they aren't restated here.

## 2. Documentation & the Living Documentation Rule

This project maintains seven cross-referencing docs: this file, [CODING_RULES.md](CODING_RULES.md), [DESIGN.md](DESIGN.md), [ARCHITECTURE.md](ARCHITECTURE.md), [API.md](API.md), and [CONTRIBUTING.md](CONTRIBUTING.md) live together in `.claude/`, while [README.md](../README.md) lives at the repository root — plus an eighth, narrower-scope doc, [`anistream_server/README.md`](../anistream_server/README.md), covering the standalone Go server in isolation (it doesn't share the other seven docs' cross-linking nav bar, but is governed by the same rule below). All eight are treated as **living documents** — they describe the codebase as it actually is today, not as it was designed to be or will eventually become.

**The rule:** whenever a change to the codebase matches one of the triggers below, proactively name the affected doc(s) and propose the specific edit before or alongside the code change. Don't wait to be asked, and don't silently rewrite documentation without flagging it — the same "plan first, then get approval" discipline in § 1 applies to doc changes, not just code.

| Change | Docs to check |
| --- | --- |
| New/removed dependency in `pubspec.yaml` | [ARCHITECTURE.md](ARCHITECTURE.md) § 2; [API.md](API.md) if it's a new data source; [CODING_RULES.md](CODING_RULES.md) § 1 if it conflicts with the state-management pattern there (including the Provider/Riverpod/Bloc/Redux rejection), or § 2's dependency-rejection rule |
| New top-level `lib/` folder, or a new `features/<name>/` module | [ARCHITECTURE.md](ARCHITECTURE.md) § 2's folder tree |
| New/changed `MethodChannel`, FFI binding, or platform-specific native behavior | [ARCHITECTURE.md](ARCHITECTURE.md) § 4 |
| New/changed rule in `analysis_options.yaml`, or a new rule added to [CODING_RULES.md](CODING_RULES.md) directly | [CODING_RULES.md](CODING_RULES.md), [CONTRIBUTING.md](CONTRIBUTING.md) § 6's PR checklist |
| New external data source, or a changed GraphQL/RSS contract | [API.md](API.md) |
| Changes to the Go server's REST surface or session states | [`anistream_server/README.md`](../anistream_server/README.md), and the condensed summary in [ARCHITECTURE.md](ARCHITECTURE.md) § 6 |
| New design token (palette color, radius/blur value, animation timing) or D-pad/focus pattern | [DESIGN.md](DESIGN.md) |
| Changes to `InputModeController` / TV-detection contract | [DESIGN.md](DESIGN.md) § 4, [ARCHITECTURE.md](ARCHITECTURE.md) § 4 (Android) |
| New cache, or a changed TTL | [API.md](API.md) § 4 |
| Discovered a stale doc, dead code stub, or other unresolved inconsistency | [DESIGN.md](DESIGN.md) § 5 (design debt) or [ARCHITECTURE.md](ARCHITECTURE.md) § 7 (known issues), as applicable |

If you notice a doc that's already out of sync with the code you're looking at — even one you didn't just change — say so. A stale doc is worse than no doc, since it actively misleads the next reader, human or AI.

---
*This file defines the Living Documentation Rule above; unlike the other seven docs (including [CODING_RULES.md](CODING_RULES.md)), it has no separate file to check itself against. Last reviewed against the codebase: 2026-08-03.*
