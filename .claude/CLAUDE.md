# AniStream Project Rules

> **AniStream Docs:** **CLAUDE.md** · [CODING_RULES.md](CODING_RULES.md) · [DESIGN.md](DESIGN.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [API.md](API.md) · [README.md](../README.md) · [CONTRIBUTING.md](CONTRIBUTING.md)
> **Covers:** project orientation, code-generation workflow norms, the Living Documentation Rule, and doc-suite style. **See also:** [CODING_RULES.md](CODING_RULES.md) for enforced technical constraints on generated code, [DESIGN.md](DESIGN.md) for visual rules, [ARCHITECTURE.md](ARCHITECTURE.md) for where code lives.

## 1. Project Overview & Working Norms

- Act as a Senior Flutter/Dart Developer (Mobile/TV/Desktop) across this codebase.
- Stack: Flutter ≥3.44.0 (floor only, no exact pin — deliberate), Dart ^3.12.2 (caret-pinned), per `pubspec.yaml`. [CODING_RULES.md](CODING_RULES.md) enforces against these versions; not restated here.
- Flutter/Dart at the core, plus an optional Go server (`anistream_server/`) for thin clients ([ARCHITECTURE.md](ARCHITECTURE.md) § 6, [`anistream_server/README.md`](../anistream_server/README.md)) — [CODING_RULES.md](CODING_RULES.md) is Dart-only; the Go code has its own conventions.
- ALWAYS draft a plan before generating code on any non-trivial task.
- ALWAYS wait for explicit approval before generating. Present options and ask when multiple approaches are viable or real uncertainty exists — never guess.
- Output complete, runnable files for refactors — snippets only if explicitly requested.
- Docs describe current state only, never the editing process that produced it.
  - FORBIDDEN: "per Track B," "as agreed in an earlier pass," or naming the pass that produced a change.
  - OK: noting resolved *product* debt (e.g. [DESIGN.md](DESIGN.md) § 5 marking an item done) — that's product history, not editing history.
  - Same rule applies to code comments — [CODING_RULES.md](CODING_RULES.md) § 2.
- Every generated change is held to [CODING_RULES.md](CODING_RULES.md) in full (performance, state management, caching, linter compliance) — not restated here.

## 2. Documentation & the Living Documentation Rule

- Eight living docs cross-reference each other as `DocName.md § N` — this file, [CODING_RULES.md](CODING_RULES.md), [DESIGN.md](DESIGN.md), [ARCHITECTURE.md](ARCHITECTURE.md), [API.md](API.md), and [CONTRIBUTING.md](CONTRIBUTING.md) in `.claude/`, plus root [README.md](../README.md) and [`anistream_server/README.md`](../anistream_server/README.md) (narrower scope, no shared nav bar, same rule applies). Full index: [README.md](../README.md) § 1.
- All eight describe the codebase as it actually is today — never as designed or planned.
- `ISSUE_BACKLOG.md` isn't one of the eight — a generated backlog, not a state description.
- Every `ISSUE_BACKLOG.md` entry pins a `Ref:` to a [DESIGN.md](DESIGN.md) § 5 sub-section, or another canonical doc's section for items outside the design-system audit (see its Platform & Playback / Code Quality sections).
- NEVER renumber [DESIGN.md](DESIGN.md) § 5 without updating every matching `Ref:` in the same pass — see the trigger table below.

**The rule:** when a change matches a trigger below, propose the matching doc update alongside it — named explicitly, never silently rewritten or deferred. Same plan-first discipline as § 1, applied to docs.

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

- ALWAYS flag a stale doc the moment you notice it, even one you didn't just touch — it misleads worse than no doc at all.

## 3. Documentation Style

Every doc in this suite, including this one, follows the rules below. A violation is the § 2 stale-doc case: flag it, or fix it while already touching that doc for something else.

- One fact per bullet. If a sentence needs "and" to join two unrelated rules, it's two bullets.
- Imperative, present tense. "Use X," never "we use X" or "you should use X."
- Mark hard constraints explicitly: `ALWAYS`, `NEVER`, `FORBIDDEN`. Anything unmarked allows judgment.
- Rationale is one inline clause, not its own paragraph or section.
- Name exceptions explicitly — never leave them to inference.
- Commands and diagrams go in fenced code blocks, verbatim — nothing else shares the block.
- Before/after code examples use two separate plain code blocks (full "before," then full "after") — never a unified diff. Diff markers aren't copy-pasteable; two clean blocks are.
- Cross-references use `DocName.md § N`. Don't invent a second citation format.
- New sections are appended, never inserted mid-document — unless a full repo-wide grep-and-fix pass is explicitly budgeted for the change.
- No editing-process narrative (§ 1 already covers this — it's law, not a style preference).
- Tables for anything with 3+ parallel rows, instead of prose enumerating them.
- Keep the nav bar, the bold self-reference, and the "Last reviewed" footer on every doc that has them.
- Voice-locked, grammar pass only: [README.md](../README.md) §§ 1 and 10, [CONTRIBUTING.md](CONTRIBUTING.md) § 7 — tone (and, for § 10, legal precision) matters more than density here.
- Light touch only: [README.md](../README.md) §§ 2–3 — tighten redundancy, keep the voice; closer to reference content than storytelling.
- Everything else in the suite follows every rule above.
- If a rewrite makes a doc longer, that's a defect. The goal is density, not volume.

---
*This file defines the Living Documentation Rule and doc-suite style contract — unlike the other seven docs, it has no separate file to check itself against. Last reviewed against the codebase: 2026-09-05.*
