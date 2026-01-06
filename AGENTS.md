# Repository Guidelines

## Project Structure & Module Organization
- `FileStash/` contains the Swift sources and UI views. Entry point is `FileStashApp.swift`, state/persistence lives in `FileStashManager.swift`, and UI is in `FloatingStashView.swift` and `SettingsView.swift`.
- `FileStash/Assets.xcassets/` holds app icons and color assets.
- `FileStash/Info.plist` and `FileStash/FileStash.entitlements` define runtime settings and permissions.
- `FileStash.xcodeproj/` is the Xcode project; `README.md` is the user-facing guide.

## Build, Test, and Development Commands
- `open FileStash.xcodeproj` (or `xed .`) opens the project in Xcode.
- `xcodebuild -project FileStash.xcodeproj -scheme FileStash -configuration Debug build` builds from the CLI.
- `xcodebuild -project FileStash.xcodeproj -scheme FileStash test` runs tests if a test target is added.
- Run in Xcode with `Cmd + R`; the app needs Accessibility permission for global hotkeys.

## Coding Style & Naming Conventions
- Use 4-space indentation to match existing Swift files.
- Types and views use `PascalCase`; properties, methods, and locals use `camelCase`.
- Name files after the primary type (e.g., `HotKeyManager.swift`).
- No formatter/linter is configured; keep SwiftUI view code small and focused per file.

## Testing Guidelines
- There are no automated tests committed yet.
- If adding tests, create an Xcode test target and place files under `FileStashTests/` or `FileStashUITests/` with names like `FileStashManagerTests.swift`.
- Prefer unit tests for state and persistence logic in `FileStashManager`.

## Commit & Pull Request Guidelines
- This checkout has no `.git` history; use short, imperative commit subjects (e.g., `Add hotkey settings`), optionally with a scope.
- PRs should describe the behavior change, reference related issues, and include screenshots for UI updates.
- Call out any changes to permissions or entitlements.

## Interaction Behavior
- The stash window should appear only via the global hotkey or when a file drag enters the bottom-left hot corner.
- Mouse clicks near the hot corner must not show the window.

## Security & Configuration Tips
- Global hotkeys rely on macOS Accessibility permissions; update user docs if behavior changes.
- File access is via drag/drop; if adding persisted access, document security-scoped bookmark handling.
- Keep `FileStash/FileStash.entitlements` in sync with new capabilities.
