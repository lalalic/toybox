# Toybox — Bring Your Toy to Life

## Vision

Scan your favorite toy with your iPhone camera, and watch it come alive on your screen. It recognizes its own mouth, eyes, face, and body. It talks to you. It lives in your phone.

**Target toy (v1):** A colorful pig toy.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                   Toybox App                     │
├──────────┬──────────┬───────────┬───────────────┤
│  Scan    │ Feature  │ Animate   │ Converse      │
│  Module  │ Detect   │ Module    │ Module        │
│          │ Module   │           │               │
│ Object   │ Vision   │ RealityKit│ Speech +      │
│ Capture  │ Framework│ Animations│ LLM API       │
└──────────┴──────────┴───────────┴───────────────┘

Shared: ToyModel, ToyStorage, ToyAssetManager
```

## User Flow

```
1. SCAN        ─→  Point camera at toy, guided 360° capture
2. BUILD       ─→  Reconstruct 3D model (USDZ) on-device
3. IDENTIFY    ─→  Detect face, eyes, mouth, body parts
4. ANIMATE     ─→  Attach animation rig (blink, talk, bounce)
5. CONVERSE    ─→  Toy speaks to you (TTS + mouth animation)
```

---

## Phase 1: 3D Scanning Prototype (MVP)

### Scope
- Guided object capture using Apple's ObjectCaptureSession
- On-device reconstruction to USDZ via PhotogrammetrySession
- View reconstructed 3D model in RealityKit viewer
- Save/load scanned toys

### Tech Stack

| Component | Technology | Notes |
|-----------|-----------|-------|
| 3D Capture | `ObjectCaptureSession` (iOS 17+) | Requires LiDAR + A14+ |
| Capture UI | `ObjectCaptureView` (SwiftUI) | Apple's guided capture overlay |
| Reconstruction | `PhotogrammetrySession` | On-device USDZ generation |
| 3D Viewer | `RealityKit` + `RealityView` | Interactive model display |
| Storage | Documents directory | USDZ + metadata per toy |
| UI | SwiftUI | iOS 18+ target |

### Device Matrix

| Device | LiDAR | Scan | View | Notes |
|--------|-------|------|------|-------|
| iPhone 17 | ✅ | ✅ | ✅ | Primary dev device |
| iPhone 12 mini | ❌ | ❌ | ✅ | View-only, test viewer |

### Key Classes (Phase 1)

```
ToyboxApp.swift              — @main entry point
├── Models/
│   ├── ToyModel.swift       — Toy metadata (name, date, model URL)
│   ├── ScanState.swift      — State machine for capture flow
│   └── ToyStore.swift       — Persistence layer
├── Scanning/
│   ├── ScanCoordinator.swift    — Manages ObjectCaptureSession lifecycle
│   ├── ScanView.swift           — ObjectCaptureView wrapper + overlay
│   ├── ReconstructionView.swift — Progress UI during PhotogrammetrySession
│   └── CaptureFolderManager.swift — Image/checkpoint/model directory mgmt
├── Viewer/
│   ├── ModelViewer.swift    — RealityKit 3D model viewer
│   └── ToyGallery.swift     — Grid of all scanned toys
└── Shared/
    ├── ToyAssetManager.swift — File management for toy assets
    └── Extensions.swift
```

### State Machine

```
         ┌─────────┐
         │  Home    │  (Gallery of toys)
         └────┬────┘
              │ "Scan New Toy"
              ▼
         ┌─────────┐
         │  Ready   │  Check ObjectCaptureSession.isSupported
         └────┬────┘
              │ session.start()
              ▼
         ┌──────────┐
         │ Detecting │  Point at object, bounding box appears
         └────┬─────┘
              │ startCapturing()
              ▼
         ┌───────────┐
         │ Capturing  │  ObjectCaptureView guides 360° scan
         └────┬──────┘
              │ session.finish()
              ▼
      ┌────────────────┐
      │ Reconstructing  │  PhotogrammetrySession → USDZ
      └───────┬────────┘
              │ complete
              ▼
         ┌──────────┐
         │ Viewing   │  RealityKit model viewer
         └────┬─────┘
              │ "Save" / "Retake"
              ▼
         ┌─────────┐
         │  Home    │
         └─────────┘
```

### ObjectCaptureSession Configuration

```swift
var configuration = ObjectCaptureSession.Configuration()
configuration.isOverCaptureEnabled = true  // extra images for quality
configuration.checkpointDirectory = checkpointFolder  // crash recovery
```

### Reconstruction Settings

```swift
let session = try PhotogrammetrySession(input: imagesFolder)
try session.process(requests: [
    .modelFile(url: outputURL)  // default detail level
])
// Monitor session.outputs for progress
```

---

## Phase 2: Feature Detection

### Scope
- Detect facial features on the 3D model (eyes, mouth, nose)
- Detect body structure (head, torso, limbs)
- Store feature anchors as part of toy metadata

### Tech Options
| Approach | Pros | Cons |
|----------|------|------|
| Vision framework (2D→3D projection) | Built-in, fast | Requires mapping 2D→3D |
| Manual annotation UI | Accurate, works for any toy | Labor-intensive |
| ML model (custom CoreML) | Scalable, automatic | Training data needed |
| Hybrid: Vision hints + user confirm | Balanced | More complex UI |

### MVP Approach
Start with **manual annotation**: User taps on the 3D model to mark eyes, mouth, body center. Store as 3D anchor points in `ToyModel`. This is robust for any toy shape (pig, bear, robot, etc.).

Later: Train a CoreML model to auto-detect features on toy-like objects.

---

## Phase 3: Animation

### Scope
- Attach animation rig to feature points
- Mouth open/close sync with speech
- Eye blink animation
- Idle animations (breathing, subtle sway)
- Reaction animations (happy, surprised, sleepy)

### Tech
- **RealityKit Transform animations** for simple movements
- **BlendShapes** if the mesh supports them (unlikely from photogrammetry)
- **Bone-based animation**: Programmatically create skeleton from anchor points
- **Shader-based**: Vertex displacement for mouth/eye deformation

### MVP Approach
Use **Transform animations** on sub-regions of the model identified by anchor points:
- Mouth: Scale Y transform at mouth anchor (simulate open/close)
- Eyes: Opacity/scale toggle at eye anchors (blink)
- Body: Gentle oscillation on root transform (idle breathing)

---

## Phase 4: Conversation

### Scope
- Toy has a personality based on what it looks like
- Speech synthesis (AVSpeechSynthesizer or AI TTS)
- Speech recognition for user input
- LLM-powered responses (OpenAI/Claude API)
- Mouth animation synced to speech output

### Personality System
```swift
struct ToyPersonality {
    let name: String           // "Piggy"
    let species: String        // "pig"
    let traits: [String]       // ["cheerful", "curious", "loves snacks"]
    let voicePitch: Float      // 1.2 (higher = cuter)
    let systemPrompt: String   // Generated from above
}
```

---

## Project Structure

```
toybox/
├── docs/
│   └── design.md          ← this file
├── Toybox/                  ← Xcode project
│   ├── ToyboxApp.swift
│   ├── Models/
│   ├── Scanning/
│   ├── Viewer/
│   ├── Shared/
│   └── Assets.xcassets/
├── Toybox.xcodeproj/
├── Shared/                  ← Shared SPM package (future: shared with other apps)
│   ├── Package.swift
│   └── Sources/
└── README.md
```

---

## Open Questions

1. **Reconstruction quality**: How detailed is on-device reconstruction? Need to test with the pig toy.
2. **Feature detection on low-poly mesh**: Photogrammetry output may be too rough for automatic feature detection — manual annotation may be the only viable MVP path.
3. **Animation without rigging**: Can we convincingly animate a photogrammetry mesh without proper bone rigging? Shader-based vertex displacement is the most promising approach.
4. **iPhone 12 mini experience**: Since it can't scan, should we support sharing toys between devices?

---

## Next Steps

1. ✅ Research Apple Object Capture APIs
2. ✅ Study Apple sample code
3. → Create Xcode project with SwiftUI
4. → Implement scanning flow (ObjectCaptureSession + ObjectCaptureView)
5. → Implement reconstruction (PhotogrammetrySession)
6. → Implement model viewer (RealityKit)
7. → Test on iPhone 17 with pig toy
8. → Add toy gallery / persistence
