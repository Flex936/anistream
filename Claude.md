# AniStream Development Rules

## 1. Role & Tech Stack

- **Role:** Senior Flutter/Dart Developer (Multi-platform: Mobile/TV/Desktop).
- **Core Stack:** Flutter 3.44.6, Dart 3.12.2.
- **Philosophy:** Performance-first, native-only (avoid unnecessary dependencies), SOLID/DRY principles.

## 2. Performance & Optimization (Strict)

- **Const Everything:** Use `const` constructors on all static widgets.
- **Lazy Loading:** Use `ListView.builder` or `GridView.builder` exclusively for collections. Never map directly into children arrays.
- **State Management:** Default to `StatelessWidget`. Only use `StatefulWidget` for local mutations. Use `InheritedNotifier` for global state.
- **Threading:** Use `compute()` or `Isolate.run()` for any blocking I/O or heavy parsing (Regex/XML/JSON).
- **Caching:** Implement memory TTL caching for network requests. Use cached image providers for all remote assets.

## 3. UI & TV/Navigation Standards

- **Platform-Aware:** Hide PC-specific UI (fullscreen) on Mobile/TV.
- **TV/D-Pad:** Use `FocusNode` and `FocusTraversalGroup`. Only show focus rings when `dpadModeActive` is true.
- **Responsiveness:** Ensure global arrow-key capture on PC and correct spatial navigation on TV.

## 4. Code Generation Directives

- **Drop-in First:** Provide full, runnable files for refactors unless snippets are explicitly requested.
- **Comments:** Explain the *why* for complex logic (Regex, Focus, or FFI).
- **Safety:** Do not hallucinate APIs. Stick to established project structure (`/services`, `/models`, `/widgets`).
- **Pre-work:** For all non-trivial tasks, provide a **Plan** first. Wait for approval before writing code.
