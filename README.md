# Toybox

Bring your toys to life! Scan real toys in 3D, annotate facial features, watch them animate with googly eyes and breathing, then have a voice conversation with your toy powered by an AI agent.

## Features

- **3D Scanning** — Guided 360° object capture using LiDAR (`ObjectCaptureSession`), fallback multi-photo capture for non-LiDAR devices
- **On-device Reconstruction** — `PhotogrammetrySession` → USDZ model
- **Model Viewer** — Interactive RealityKit orbit viewer (drag to rotate, pinch to zoom)
- **Toy Gallery** — Grid of saved toys, import USDZ from Files, rename, delete
- **Feature Annotation** — Crosshair-based 3D placement of eyes, mouth, nose, body center, head on the model
- **Living Toy Animation** — Procedural googly eyes (white sphere + iris + eyelid), mouth, idle breathing loop, periodic blink cycle, speaking mouth animation
- **AI Conversation** — GPT-4.1 agent via CopilotSDK relay, responds in-character as the toy with configurable personality/age/voice
- **Voice I/O** — Tap-to-talk with `SFSpeechRecognizer` live transcription; responses spoken via `AVSpeechSynthesizer` with persona-matched pitch/rate
- **Gesture Tools** — LLM can trigger wiggle/spin/blink animations on the 3D model via tool calls
- **MCP Server** — Embedded HTTP server on port 9223 for remote UI automation and testing
- **File Sharing** — iTunes/Files app access to Documents folder

## Requirements

- **For scanning:** iPhone with LiDAR sensor (iPhone 12 Pro+, iPhone 17)
- **For viewing/conversation:** Any iPhone running iOS 18+
- Xcode 16+, Swift 6
- **Relay server** for AI agent: `relay.ai.qili2.com:443` (wss via Caddy)

## Architecture

```
ToyboxApp (@main)
├── MCPServer (port 9223, AppAgent tools)
├── AppModel — @Observable state machine
│   States: home → scanning → reconstructing → viewing → annotating → living
│
├── Models/
│   ├── AppModel.swift         — Central state machine, navigation
│   ├── ToyModel.swift         — Codable toy entity (id, name, modelFile, features[])
│   ├── ToyStore.swift         — JSON-backed CRUD (toys.json in Documents/)
│   └── ToyFeature.swift       — Feature kind enum + SIMD3<Float> position
│
├── Scanning/
│   ├── ScanCoordinator.swift      — ObjectCaptureSession lifecycle
│   ├── ScanView.swift             — ObjectCaptureView wrapper + overlay
│   ├── PhotoCaptureView.swift     — AVCaptureSession for non-LiDAR (auto-capture ~36 photos)
│   ├── ReconstructionView.swift   — PhotogrammetrySession progress UI
│   └── CaptureFolderManager.swift — Creates Images/Checkpoint/Models dirs per toy
│
├── Viewer/
│   ├── ToyGallery.swift       — Home grid, scan/import actions
│   ├── ModelViewer.swift      — RealityKit orbit viewer, "Annotate" / "Bring to Life"
│   └── AnnotationView.swift   — Crosshair 3D feature placement
│
├── Animation/
│   ├── LivingToyView.swift    — Full experience: 3D model + chat panel + voice + settings
│   └── ToyAnimator.swift      — Procedural googly eyes/mouth entities, breathing/blink loops
│
├── Agent/
│   ├── PiggyAgentService.swift       — CopilotSDK client → WebSocketTransport → relay
│   │   Model: gpt-4.1, Tools: send_response, ask_user, wiggle, spin, blink
│   │   TTS: AVSpeechSynthesizer with persona voice settings
│   ├── PiggyPersonaSettings.swift    — Age (baby/kid/teen/grown), voice (cute/calm/bright),
│   │   personality string, persisted via UserDefaults
│   └── PiggyVoiceInputService.swift  — SFSpeechRecognizer + AVAudioEngine tap
│
├── tools/reconstruct.swift    — CLI reconstruction tool
├── mcp.sh                     — MCP shell helper (snapshot, tap, type, screenshot, etc.)
└── docs/design.md             — Full design document
```

## The "Living Toy" Experience

The core feature combines three systems in `LivingToyView`:

1. **3D Animation** (`ToyAnimator`) — Procedural googly eye entities (white sphere + iris + eyelid overlay) and mouth are attached at annotated feature positions on the scanned USDZ model. Idle loop includes breathing (scale oscillation) and periodic blinking (eyelid opacity toggle). Speaking mode opens/closes the mouth.

2. **AI Agent** (`PiggyAgentService`) — Connects to relay server via CopilotSDK `WebSocketTransport(host: "relay.ai.qili2.com", port: 443)` (wss). Sends user messages with full persona context (toy name, personality, age, voice style) as system prompt. GPT-4.1 responds in-character. Before replying with `send_response`, the LLM can call gesture tools (wiggle, spin, blink) to animate the 3D model.

3. **Voice I/O** — Tap-to-talk records via `AVAudioEngine` and transcribes with `SFSpeechRecognizer` in real-time. Responses are spoken via `AVSpeechSynthesizer` with pitch/rate from the persona's voice preset (cute=high pitch, calm=low rate, etc.).

## Agent Integration

The agent uses CopilotSDK's `createAgent` pattern (not raw sessions):

- **Transport:** `WebSocketTransport` to `relay.ai.qili2.com:443` (Caddy auto-TLS → relay server on 8765)
- **Model:** `gpt-4.1`
- **Tools injected by agent:**
  - `send_response` — delivers final response text (captured for TTS)
  - `ask_user` — asks follow-up questions
- **App-defined tools:**
  - `wiggle` — wiggles the 3D model
  - `spin` — spins the model
  - `blink` — triggers a blink animation
- **System prompt:** Includes toy name, persona personality, age preset, voice style
- **Audio session:** `.playback` category, `.spokenAudio` mode, `.duckOthers` option

The relay server pools Copilot CLI instances and injects an agent loop system message. The `send_response` tool is the mechanism for the LLM to deliver its final answer back to the app.

## Dependencies

Local Swift packages (relative paths in Xcode project):

| Package | Path | Purpose |
|---------|------|---------|
| **CopilotSDK** | `../copilot-ios/CopilotSDK` | WebSocket transport, sessions, agent API, tool definitions |
| **AppAgent** | `../copilot-ios/AppAgent` | MCP server, UI automation tools (snapshot, tap, type, screenshot) |

No remote SPM dependencies.

## Build & Deploy

```bash
cd toybox

# Build for iOS device
xcodebuild build -scheme Toybox -destination 'generic/platform=iOS' \
  -derivedDataPath build -allowProvisioningUpdates

# Install to device (iPhone 17)
xcrun devicectl device install app --device FC6AEF41-F3A8-5176-8FEB-841232FF2237 \
  build/Build/Products/Debug-iphoneos/Toybox.app

# Launch
xcrun devicectl device process launch \
  --device FC6AEF41-F3A8-5176-8FEB-841232FF2237 com.toybox.app
```

**Signing:** Team `JABNLDLN8G`, identity "Apple Development: CHENG LI (P84M4B2QYY)"

## Device Testing (MCP)

The app embeds an MCP HTTP server on port 9223. Use `mcp.sh` for remote UI automation:

```bash
# Set device IP (iPhone 17 IPv6)
export DEVICE_IP="[fd03:9b8f:6d6f::1]"

# Take UI snapshot (accessibility tree)
./mcp.sh snapshot

# Tap on element by accessibility ref
./mcp.sh tap "Start Scan"

# Type text into focused field
./mcp.sh type "ref" "Hello"

# Take screenshot
./mcp.sh screenshot

# Swipe direction
./mcp.sh swipe up
```

The MCP server uses AppAgent's `AppAgentToolProvider` which exposes tools like `snapshot`, `tap`, `type_text`, `screenshot`, `find_element`, `swipe`, `tap_coordinates`.

## Info.plist Capabilities

| Key | Purpose |
|-----|---------|
| `UIFileSharingEnabled` | iTunes file sharing for 3D models |
| `LSSupportsOpeningDocumentsInPlace` | Files app access |
| `NSLocalNetworkUsageDescription` | MCP server |
| `NSMicrophoneUsageDescription` | Voice input |
| `NSSpeechRecognitionUsageDescription` | Speech-to-text |
| `NSBonjourServices` (`_http._tcp`) | MCP discovery |

## Roadmap

- [x] Phase 1: 3D Scanning & Viewing
- [x] Phase 2: Feature Annotation (eyes, mouth, nose, body, head)
- [x] Phase 3: Animation (googly eyes, breathing, blink, mouth)
- [x] Phase 4: AI Conversation (GPT-4.1 agent + TTS + voice input + gesture tools)
- [ ] Identity persistence across sessions
- [ ] Multi-toy support (different personas per toy)
- [ ] Lip sync matching TTS phonemes
- [ ] AR mode (place living toy in real world)
