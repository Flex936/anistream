# AniStream Project Rules

> **AniStream Docs:** **CLAUDE.md** · [CODING_RULES.md](CODING_RULES.md) · [DESIGN.md](DESIGN.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [API.md](API.md) · [README.md](../README.md) · [CONTRIBUTING.md](CONTRIBUTING.md)
> **Covers:** project orientation for AI/human contributors, the code-generation workflow norms, the rule that keeps this doc suite in sync, and the style every doc in it follows. **See also:** [CODING_RULES.md](CODING_RULES.md) for the strict, enforced technical constraints on generated code, [DESIGN.md](DESIGN.md) for visual rules, [ARCHITECTURE.md](ARCHITECTURE.md) for where code lives.

## 1. Project Overview & Working Norms

- Act as a Senior Flutter/Dart Developer (Mobile/TV/Desktop) across this codebase.
- Stack: Flutter ≥3.44.0, Dart ^3.12.2 — matches `pubspec.yaml`'s `environment:` constraint.
  - Dart's constraint is an explicit caret pin; Flutter only has the ≥3.44.0 floor (no exact pin) — that asymmetry is intentional, not a gap.
  - CODING_RULES.md enforces against these versions; not restated there.
- Flutter/Dart at the core, plus an optional companion Go server (`anistream_server/`) for thin clients — see [ARCHITECTURE.md](ARCHITECTURE.md) § 6 and [`anistream_server/README.md`](../anistream_server/README.md).
  - CODING_RULES.md is Dart-only. The Go code has its own conventions and isn't held to it.
- ALWAYS draft a plan before generating code on any non-trivial task, and wait for explicit approval before generating.
  - Multiple viable approaches, or genuine uncertainty? Present the options and ask — don't guess.
- Output complete, runnable files for refactors — snippets only if explicitly requested.
- Docs describe the current state only — never the editing process that produced it.
  - FORBIDDEN: "per Track B," "as agreed in an earlier pass," or naming which internal pass produced a change.
  - OK: noting resolved *product* debt (e.g. [DESIGN.md](DESIGN.md) § 5 marking an item done) — that's product history, not editing history.
  - Same rule for code comments — see [CODING_RULES.md](CODING_RULES.md) § 2.
- Every generated change is held to [CODING_RULES.md](CODING_RULES.md) in full (performance, state management, caching, linter compliance) — not restated here.

## 2. Documentation & the Living Documentation Rule

- Eight living docs, cross-referencing each other as `DocName.md § N`: this file, [CODING_RULES.md](CODING_RULES.md), [DESIGN.md](DESIGN.md), [ARCHITECTURE.md](ARCHITECTURE.md), [API.md](API.md), [CONTRIBUTING.md](CONTRIBUTING.md) (all in `.claude/`), [README.md](../README.md) (repo root), and [`anistream_server/README.md`](../anistream_server/README.md) (narrower scope, no shared nav bar, same rule below). All eight describe the codebase as it actually is today — never as it was designed to be or will eventually become.
- `ISSUE_BACKLOG.md` isn't one of the eight — it's a generated backlog, not a description of current state — but every entry pins a `Ref:` to a [DESIGN.md](DESIGN.md) § 5 sub-section. Renumber § 5 without updating it in the same pass and every reference breaks. See the table below.

**The rule:** a codebase change matching a trigger below gets its doc update proposed alongside it — named explicitly, not silently rewritten, not deferred until asked. Same plan-first discipline as § 1, applied to docs.

| Change | Docs to check |
| --- | --- |
| New/removed dependency in `pubspec.yaml` | [ARCHITECTURE.md](ARCHITECTURE.md) § 2; [API.md](API.md) if it's a new data source; [CODING_RULES.md](CODING_RULES.md) § 1 if it conflicts with the state-management pattern (FORBIDDEN: Provider/Riverpod/Bloc/Redux), or § 2's dependency-rejection rule |
| New top-level `lib/` folder, or a new `features/<name>/` module | [ARCHITECTURE.md](ARCHITECTURE.md) § 2's folder tree |
| New/changed `MethodChannel`, FFI binding, or platform-specific native behavior | [ARCHITECTURE.md](ARCHITECTURE.md) § 4 |
| New/changed rule in `analysis_options.yaml`, or a new rule added to [CODING_RULES.md](CODING_RULES.md) directly | [CODING_RULES.md](CODING_RULES.md), [CONTRIBUTING.md](CONTRIBUTING.md) § 6's PR checklist |
| New external data source, or a changed GraphQL/RSS contract | [API.md](API.md) |
| Changes to the Go server's REST surface or session states | [`anistream_server/README.md`](../anistream_server/README.md), and the condensed summary in [ARCHITECTURE.md](ARCHITECTURE.md) § 6 |
| New design token (palette color, radius/blur value, animation timing) or D-pad/focus pattern | [DESIGN.md](DESIGN.md) |
| Changes to `InputModeController` / TV-detection contract | [DESIGN.md](DESIGN.md) § 4, [ARCHITECTURE.md](ARCHITECTURE.md) § 4 (Android) |
| New cache, or a changed TTL | [API.md](API.md) § 4 |
| Renumbering or restructuring [DESIGN.md](DESIGN.md) § 5's sub-sections | Every `Ref:` line in `ISSUE_BACKLOG.md` — update both in the same pass, or neither |
| Discovered a stale doc, dead code stub, or other unresolved inconsistency | [DESIGN.md](DESIGN.md) § 5 (design debt) or [ARCHITECTURE.md](ARCHITECTURE.md) § 7 (known issues), as applicable |

- ALWAYS flag a stale doc the moment you notice it, even one you didn't just touch. A stale doc misleads worse than no doc — human or AI reader alike.

## 3. Documentation Style

Every doc in this suite — this file included — follows the rules below. Found one that doesn't? That's the § 2 stale-doc case: flag it, or fix it if you're already touching that doc for something else.

- One fact per bullet. If a sentence needs "and" to join two unrelated rules, it's two bullets.
- Imperative, present tense. "Use X," never "we use X" or "you should use X."
- Mark hard constraints explicitly: `ALWAYS`, `NEVER`, `FORBIDDEN`. Anything unmarked allows judgment.
- Rationale is one inline clause, not its own paragraph or section.
- Name exceptions explicitly — never leave them to inference.
- Commands and diagrams go in fenced code blocks, verbatim — nothing else shares the block.
- Cross-references use `DocName.md § N`. Don't invent a second citation format.
- New sections are appended, never inserted mid-document — unless a full repo-wide grep-and-fix pass is explicitly budgeted for that change.
- No editing-process narrative (§ 1 above already covers this — it's law, not a style preference).
- Tables for anything with 3+ parallel rows, instead of prose enumerating them.
- Keep the nav bar, the bold self-reference, and the "Last reviewed" footer on every doc that has them.
- Three sections get no more than a grammar pass, never a restructure: [README.md](../README.md) § 1's origin-story/description prose and § 10 (Legal Disclaimer), and [CONTRIBUTING.md](CONTRIBUTING.md) § 7 (Code of Conduct) — tone, and for § 10 legal precision, matter more than density there. README § 2 (Features) and § 3 (How It Works) can tighten lightly for redundancy, but keep their voice — they're closer to reference content than storytelling. Everything else in the suite follows every rule above.
- If a rewrite makes a doc longer, that's a defect. The goal is density, not volume.

---
*This file defines the Living Documentation Rule and the doc-suite style contract above; unlike the other seven docs (including [CODING_RULES.md](CODING_RULES.md)), it has no separate file to check itself against. Last reviewed against the codebase: 2026-08-15.*
