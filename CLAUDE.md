# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FileStash is a macOS application built with SwiftUI that provides a floating file staging area in the bottom-left corner of the screen. Users can drag files/folders from Finder into the staging area, and drag them out later. The app uses drag detection and mouse shake gestures to show/hide the floating window.

## Build & Run Commands

**IMPORTANT**: DO NOT automatically build the project after making changes. Xcode will auto-build when the user runs the app. Only build if explicitly requested by the user.

### Building and Running
```bash
# Open in Xcode
open FileStash.xcodeproj

# Build from command line
xcodebuild -project FileStash.xcodeproj -scheme FileStash -configuration Debug build

# Run from command line (builds and launches)
xcodebuild -project FileStash.xcodeproj -scheme FileStash -configuration Debug

# Clean build
xcodebuild -project FileStash.xcodeproj -scheme FileStash clean
```

### Running in Xcode
- Open FileStash.xcodeproj in Xcode 14+
- Press Cmd+R to build and run
- No special permissions required

## Architecture

### Core Components

**FileStashApp.swift** (FileStash/FileStashApp.swift)
- App entry point using SwiftUI's `@main`
- `AppDelegate` class manages the app lifecycle and coordinates all major subsystems
- Creates and manages the floating `NSWindow` with borderless style and `.floating` level
- Sets up menu bar icon, hotkey monitoring, drag tracking, and click-outside detection
- Window positioning: 10px from screen bottom-left corner
- Drag threshold: 200px from corner triggers window display during drag operations

**FileStashManager.swift** (FileStash/FileStashManager.swift)
- Singleton (`FileStashManager.shared`) managing the file staging list
- `@Published` properties trigger SwiftUI updates: `stashedFiles`, `isExpanded`
- Persists file list to UserDefaults (saves paths, not actual files)
- Handles add/remove/clear operations and file operations (open, reveal in Finder)
- Validates file existence on load to remove stale entries

**FloatingStashView.swift** (FileStash/FloatingStashView.swift)
- Main SwiftUI view rendered in the floating window
- Two states: collapsed (60x60 trigger area) and expanded (280x380 list view)
- Implements drag-and-drop receivers using `.onDrop(of: [.fileURL])`
- File rows support drag-out using `.onDrag` with NSItemProvider
- Context menu and hover actions for each file
- Image preview support for common image formats (PNG, JPG, SVG, etc.)
- Pin/unpin functionality for important files

### Key Design Patterns

**Window Management**
- `NSWindow` with `.borderless` style, transparent background, shadow enabled
- `.floating` level keeps window above others
- `.canJoinAllSpaces` + `.stationary` makes it appear on all desktops
- Alpha animation (0.2s show, 0.3s hide) for smooth transitions

**Event Monitoring**
- Global mouse drag monitor (`.leftMouseDragged`) detects proximity to hot corner
- Global click monitor (`.leftMouseDown`, `.rightMouseDown`) detects clicks outside window
- Mouse shake detection in bottom-left corner to show/hide window
- All monitors properly removed in `applicationWillTerminate`

**State Management**
- `FileStashManager.shared` is the single source of truth for file list and expansion state
- `@ObservedObject` in views creates reactive bindings
- `isExpanded` state synchronized between AppDelegate and FileStashManager

**Permissions**
- No special permissions required (Accessibility permission removed)
- Sandbox relaxed for file access (entitlements configuration)

## File Structure

```
FileStash/
├── FileStashApp.swift          # App entry, AppDelegate, window/event management
├── FileStashManager.swift      # File list state and persistence
├── FloatingStashView.swift     # Main SwiftUI UI (collapsed/expanded states)
├── Assets.xcassets/            # App icon and color assets
├── Info.plist                  # App metadata
└── FileStash.entitlements      # Sandbox and permission configuration
```

## Important Implementation Notes

- **No Special Permissions**: The app no longer requires Accessibility permission. It uses drag detection and mouse shake gestures instead of global hotkeys.
- **File References**: The app stores file paths (strings), not security-scoped bookmarks. Files may become inaccessible if moved/deleted. The manager filters out non-existent files on load.
- **Window Lifecycle**: The floating window is created once at launch and shown/hidden via alpha animations. Never destroyed/recreated during app lifetime.
- **Drag Detection**: The 200px threshold is hardcoded in AppDelegate. Dragging near the corner triggers display, but only during active drag operations.
- **Mouse Shake Detection**: Shaking the mouse in the bottom-left corner (320x470px area) will toggle the window visibility.
- **Thread Safety**: All UI updates from event handlers use `DispatchQueue.main.async` to ensure main thread execution.
- **Event Handler Cleanup**: All monitors and event handlers must be removed in `applicationWillTerminate` to prevent crashes.
- **Image Preview**: Image files are displayed with async-generated thumbnails to avoid blocking the UI thread.
