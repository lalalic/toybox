# Toybox

Bring your toys to life! Scan them in 3D, watch them move, and talk to them.

## Features (Phase 1 — 3D Scanning MVP)

- **3D Scanning** — Guided 360° object capture using LiDAR
- **On-device Reconstruction** — Builds USDZ 3D model directly on iPhone
- **Model Viewer** — Interactive RealityKit 3D viewer
- **Toy Gallery** — Save and browse your scanned toys

## Requirements

- **For scanning:** iPhone with LiDAR sensor (iPhone 12 Pro+, iPhone 17)
- **For viewing:** Any iPhone running iOS 18+
- Xcode 16+  

## Project Structure

```
toybox/
├── docs/design.md         — Full design document
├── Toybox/                — Source code
│   ├── ToyboxApp.swift    — App entry point
│   ├── ContentView.swift  — Root view / state router
│   ├── Models/            — Data models & persistence
│   ├── Scanning/          — Object capture & reconstruction
│   └── Viewer/            — 3D model viewer & gallery
├── Toybox.xcodeproj/      — Xcode project
└── README.md              — This file
```

## Build

```bash
cd toybox
xcodebuild build -scheme Toybox -destination 'generic/platform=iOS' \
  -derivedDataPath build -allowProvisioningUpdates
```

## Roadmap

- [x] Phase 1: 3D Scanning & Viewing
- [ ] Phase 2: Feature Detection (eyes, mouth, body)
- [ ] Phase 3: Animation (blink, talk, idle)
- [ ] Phase 4: Conversation (LLM + TTS + lip sync)
