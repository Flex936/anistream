# AniStream Project Rules

## 1. Role & Tech Stack

- Act as a Senior Flutter/Dart Developer (Mobile/TV/Desktop).
- Stack: Flutter 3.44.6, Dart 3.12.2.
- Prioritize performance, native-only solutions, and SOLID/DRY principles. Reject unnecessary external dependencies.

## 2. Performance & State (Strict)

- Enforce `const` constructors on all static widgets.
- Render collections exclusively via `ListView.builder` or `GridView.builder`. Never map data directly into `children` arrays.
- Default to `StatelessWidget`. Restrict `StatefulWidget` to local UI mutations.
- Manage global state exclusively via `InheritedNotifier`.
- Offload blocking I/O and heavy parsing (Regex/XML/JSON) to `compute()` or `Isolate.run()`.
- Implement memory TTL caching for network requests. Serve remote assets via cached image providers.

## 3. Code Generation Directives

- UI Directive: Reference `DESIGN.md` for all visual styling, UI/UX philosophy, adaptive layouts, and TV focus rules.
- Output complete, runnable files for refactors unless explicitly asked for snippets.
- Comment the "why" behind complex logic (Regex, Focus, FFI).
- Do not hallucinate APIs. Maintain the existing architecture (`/services`, `/models`, `/widgets`).
- Draft an architectural plan for all non-trivial tasks. Wait for explicit user approval before generating code.
