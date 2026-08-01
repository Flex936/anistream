# Contributing to AniStream

> **AniStream Docs:** [CLAUDE.md — overview & index](CLAUDE.md) · [CODING_RULES.md — tech constraints](CODING_RULES.md) · [DESIGN.md — UI/UX rules](DESIGN.md) · [ARCHITECTURE.md — structure & platform](ARCHITECTURE.md) · [API.md — data & caching](API.md) · [README.md — project intro](../README.md) · **CONTRIBUTING.md — PR process**
> **Covers:** how to contribute — setup pointers, coding standards, the PR checklist, and the Code of Conduct. **See also:** [CODING_RULES.md](CODING_RULES.md) for the exact rules a PR is held to, [DESIGN.md](DESIGN.md) for UI/UX contributions, [ARCHITECTURE.md](ARCHITECTURE.md) § 2 for where new code belongs.

Thanks for considering a contribution — AniStream is maintained by a small team (plus AI-assisted development), and outside contributions genuinely help. This guide covers how to get set up, what's expected of a PR, and where the project's other rules live so nothing here is duplicated.

## 1. Ways to Contribute

- **Bug reports** — open an issue with repro steps, your platform (Windows/Linux/macOS/Android/Android TV/iOS), and logs if you have them (see `AppLogger`'s output directory, printed at startup).
- **Feature requests** — open an issue describing the use case before writing code; for anything non-trivial, a short discussion up front avoids a PR that doesn't fit the architecture.
- **Design work** — proposals for new UI should be framed against [DESIGN.md](DESIGN.md) § 1's existing tokens and § 4's TV/D-pad rules, not introduced ad hoc in a single widget.
- **Documentation** — this project treats its docs — the seven cross-referencing docs split across `.claude/` and the repository root, plus [`anistream_server/README.md`](../anistream_server/README.md) — as living documents (see [CLAUDE.md](CLAUDE.md) § 2, the Living Documentation Rule). Doc-only PRs that correct drift between the docs and the code are genuinely welcome.
- **Code** — see below.

## 2. Getting Set Up

Follow [README.md](../README.md) § 4 (**Developer & System Setup**) and § 5 (**Getting Started (Development)**) for your OS — not duplicated here to avoid the two drifting apart. If you're working on the optional Go server, its own build/run instructions are in [`anistream_server/README.md`](../anistream_server/README.md).

## 3. Coding Standards

Every PR is held to [CODING_RULES.md](CODING_RULES.md) and the lint configuration in `analysis_options.yaml` in full — both are non-negotiable, not style suggestions, and neither is restated here.

- Run `flutter analyze` before opening a PR — it should come back clean. Note that `analyze` only mechanically enforces part of [CODING_RULES.md](CODING_RULES.md) § 1 (see that section for exactly which rule and which are review-only); this is why the checklist below has a separate line for the rest.
- If you believe a specific lint should be suppressed for a good reason, use a scoped `// ignore: <rule>` with a comment explaining why, not a blanket rule change in `analysis_options.yaml`.
- New code goes where [ARCHITECTURE.md](ARCHITECTURE.md) § 2's folder-placement rule says it goes — don't introduce a new top-level folder without discussing it first.
- **This project is Flutter/Dart only for the purposes of this file.** If you're contributing to the companion Go server (`anistream_server/`), its own conventions live in [`anistream_server/README.md`](../anistream_server/README.md), not here.

## 4. UI/Design Contributions

Every UI change is held to [DESIGN.md](DESIGN.md) in full — not restated here.

- [DESIGN.md](DESIGN.md) § 5 documents a handful of known blur-sigma and border-radius inconsistencies. **Please don't "fix" these incidentally inside an unrelated PR** — if you want to formalize new design tokens, open a dedicated design-system issue/PR so the change (and its visual impact across every affected screen) can be reviewed on its own.

## 5. Documentation Updates

If your change matches a trigger in [CLAUDE.md](CLAUDE.md) § 2's Living Documentation Rule table (new dependency, new folder, new native bridge, new data source, new cache, new design token, etc.), update the relevant `.md` file(s) **in the same PR**. A reviewer will ask for this if it's missing.

## 6. Pull Request Checklist

- [ ] `flutter analyze` passes with no new warnings/errors
- [ ] Widgets/state also follow [CODING_RULES.md](CODING_RULES.md) § 1's review-only conventions (collection rendering, `StatelessWidget`-by-default, `InheritedNotifier`-only state, offloaded parsing, network-request caching) — these aren't caught by `analyze`, so check them manually
- [ ] New/changed widgets follow [DESIGN.md](DESIGN.md) (colors, radii, blur, D-pad focus rules as applicable)
- [ ] New files are placed per [ARCHITECTURE.md](ARCHITECTURE.md) § 2's folder rule
- [ ] Any networking/scraping change is reflected in [API.md](API.md)
- [ ] Any doc-affecting change (see above) has a matching doc update in this PR
- [ ] Commit messages and the PR description explain the *why*, not just the *what* — matching this codebase's own comment style for non-obvious logic (regex, focus traversal, FFI boundaries)

## 7. Code of Conduct

This project follows the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating, you're expected to uphold it — be respectful, assume good faith, and keep disagreements about code and design, not people.

## 8. License

By contributing, you agree that your contributions are licensed under the project's **GNU General Public License v3.0 (GPLv3)** — see [README.md](../README.md) § 9 and the `LICENSE` file expected at the repository root (its presence there is currently pending verification).

---
*Last reviewed against the codebase: 2026-07-28. Changed the PR checklist (§ 6), the design-debt list (DESIGN.md § 5), or the license (§ 8)? Update this file too.*
