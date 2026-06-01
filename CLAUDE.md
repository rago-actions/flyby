# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FlyBy is a macOS menu bar app that polls your calendar and shows an airplane animation flying across the screen when a meeting is 5 minutes away. It uses the Claude CLI (`claude -p`) to fetch calendar events via the `calendar_events` tool.

## Build & Run

```bash
swift build              # Build debug binary
swift run                # Build and run
swift run FlyBy --test   # Run with a test animation on launch
```

The built binary lands at `.build/arm64-apple-macosx/debug/FlyBy`.

## Architecture

Single-file app (`Sources/main.swift`) with three components:

- **CalendarPoller** — Polls every 30s by shelling out to `claude -p` requesting calendar events as JSON. Fires a callback when an event is ≤5 min away (deduped by title+timestamp).
- **AirplaneWindow** — Borderless full-screen overlay that animates a ✈️ emoji + banner across the screen at 60fps with eased motion and a sine-wave vertical wobble. Auto-dismisses after 15s.
- **AppDelegate** — Wires poller → animation, sets up the menu bar icon (with "Test Flight" and "Quit" items), and manages the run loop.

## Key Details

- **Platform**: macOS 13+ (uses AppKit directly, no SwiftUI)
- **Swift tools version**: 5.9
- **No dependencies** — pure Swift Package Manager, no third-party libraries
- **External dependency**: Requires `claude` CLI available in PATH for calendar polling
- **Activation policy**: `.accessory` (no dock icon, menu bar only)
- **Window level**: `CGShieldingWindowLevel()` (renders above everything including fullscreen apps)
