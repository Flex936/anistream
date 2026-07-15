# AniStream Design System & UI Specs

## 1. UI/UX Philosophy & Visual Language

- Execute a premium, Apple/Spotify-inspired UI/UX. Prioritize clean layouts, deep contrasts, and seamless transitions.
- Source all colors strictly from `lib/core/theme/app.palette.dart`. Extend this palette logically if new shades are required. NEVER hardcode color values in widget files.
- Enforce a strictly scaled typography system. Avoid hardcoded font sizes.
- Standardize border radiuses (e.g., 12px for list items, 24px for modals/bottom sheets).
- Utilize Glassmorphism heavily for overlays, toasts, and floating elements using `BackdropFilter` with standardized blur levels.

## 2. Performance UI Mode

- Read the active performance state when building visually complex components.
- Auto-downgrade expensive rendering when performance mode is active. (e.g., Replace `BackdropFilter` glassmorphism with flat, semi-transparent fallback colors).

## 3. Responsive Layouts (Mobile / PC / TV)

- Design universally for Mobile, PC, and TV.
- Maximize screen real estate on Desktop. Ensure touch targets are a minimum of 48x48 logical pixels on Mobile.
- Hide PC-specific UI controls (e.g., window management, explicit fullscreen toggles) on Mobile/TV builds.

## 4. Spatial Navigation & TV (D-Pad)

- Isolate D-Pad navigation exclusively to TV builds or when a physical controller is explicitly connected. Do NOT let TV focus logic bleed into standard Mobile/PC pointer/touch interactions.
- Manage spatial navigation strictly via `FocusNode` and `FocusTraversalGroup`.
- Display visual focus rings ONLY when `dpadModeActive` is true.
