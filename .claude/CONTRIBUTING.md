# Contributing to AniStream

> 📚 **AniStream Docs:** [CLAUDE.md](CLAUDE.md) · [DESIGN.md](DESIGN.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [API.md](API.md) · [README.md](../README.md) · **CONTRIBUTING.md**
> **Covers:** how to contribute — setup pointers, coding standards, the PR checklist, and the Code of Conduct. **See also:** [CLAUDE.md](CLAUDE.md) for the exact rules a PR is held to, [DESIGN.md](DESIGN.md) for UI/UX contributions, [ARCHITECTURE.md](ARCHITECTURE.md) for where new code belongs.

Thanks for considering a contribution — AniStream is maintained by a small team (plus AI-assisted development), and outside contributions genuinely help. This guide covers how to get set up, what's expected of a PR, and where the project's other rules live so nothing here is duplicated.

## Ways to Contribute

- **Bug reports** — open an issue with repro steps, your platform (Windows/Linux/macOS/Android/Android TV/iOS), and logs if you have them (see `AppLogger`'s output directory, printed at startup).
- **Feature requests** — open an issue describing the use case before writing code; for anything non-trivial, a short discussion up front avoids a PR that doesn't fit the architecture.
- **Design work** — proposals for new UI should be framed against [DESIGN.md](DESIGN.md)'s existing tokens and TV/D-pad rules, not introduced ad hoc in a single widget.
- **Documentation** — this project treats its docs — the six cross-referencing docs split across `.claude/` and the repository root, plus [`anistream_server/README.md`](../anistream_server/README.md) — as living documents (see [CLAUDE.md](CLAUDE.md)'s Living Documentation Rule). Doc-only PRs that correct drift between the docs and the code are genuinely welcome.
- **Code** — see below.

## Getting Set Up

Follow [README.md](../README.md)'s **Developer & System Setup** and **Getting Started (Development)** sections for your OS — not duplicated here to avoid the two drifting apart. If you're working on the optional Go server, its own build/run instructions are in [`anistream_server/README.md`](../anistream_server/README.md).

## Coding Standards

Every PR is held to [CLAUDE.md](CLAUDE.md) §§ 2–3 and the lint configuration in `analysis_options.yaml` in full — both are non-negotiable, not style suggestions, and neither is restated here.

- Run `flutter analyze` before opening a PR — it should come back clean. Note that `analyze` only mechanically enforces part of CLAUDE.md § 2 (see that section for exactly which rule and which are review-only); this is why the checklist below has a separate line for the rest.
- If you believe a specific lint should be suppressed for a good reason, use a scoped `// ignore: <rule>` with a comment explaining why, not a blanket rule change in `analysis_options.yaml`.
- New code goes where [ARCHITECTURE.md](ARCHITECTURE.md) § 2's folder-placement rule says it goes — don't introduce a new top-level folder without discussing it first.
- **This project is Flutter/Dart only for the purposes of this file.** If you're contributing to the companion Go server (`anistream_server/`), its own conventions live in [`anistream_server/README.md`](../anistream_server/README.md), not here.

## UI/Design Contributions

Every UI change is held to [DESIGN.md](DESIGN.md) in full — not restated here.

- [DESIGN.md](DESIGN.md) § 5 documents a handful of known blur-sigma and border-radius inconsistencies. **Please don't "fix" these incidentally inside an unrelated PR** — if you want to formalize new design tokens, open a dedicated design-system issue/PR so the change (and its visual impact across every affected screen) can be reviewed on its own.

## Documentation Updates

If your change matches a trigger in [CLAUDE.md](CLAUDE.md)'s Living Documentation Rule table (new dependency, new folder, new native bridge, new data source, new cache, new design token, etc.), update the relevant `.md` file(s) **in the same PR**. A reviewer will ask for this if it's missing.

## Pull Request Checklist

- [ ] `flutter analyze` passes with no new warnings/errors
- [ ] Widgets/state also follow CLAUDE.md § 2's review-only conventions (collection rendering, `StatelessWidget`-by-default, `InheritedNotifier`-only state, offloaded parsing) — these aren't caught by `analyze`, so check them manually
- [ ] New/changed widgets follow [DESIGN.md](DESIGN.md) (colors, radii, blur, D-pad focus rules as applicable)
- [ ] New files are placed per [ARCHITECTURE.md](ARCHITECTURE.md)'s folder rule
- [ ] Any networking/scraping change is reflected in [API.md](API.md)
- [ ] Any doc-affecting change (see above) has a matching doc update in this PR
- [ ] Commit messages and the PR description explain the *why*, not just the *what* — matching this codebase's own comment style for non-obvious logic (regex, focus traversal, FFI boundaries)

## Code of Conduct

This project follows the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating, you're expected to uphold it — be respectful, assume good faith, and keep disagreements about code and design, not people.

## License

By contributing, you agree that your contributions are licensed under the project's **GNU General Public License v3.0 (GPLv3)** — see [README.md](../README.md) § License and the `LICENSE` file at the repository root.

---
*Last reviewed against the codebase: 2026-07-28. Changed the PR checklist, the design-debt list, or the license? Update this file too.*
