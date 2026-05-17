# ScreenAsk

> A lightweight macOS menubar agent that detects screenshots and surfaces an AI-powered floating HUD — letting users ask questions about anything on their screen.

---

## Build Checklist

- [x] Set app as menubar-first agent (`MenuBarExtra`) and add preferences entry point
- [x] Add persistent settings model for API key, model, watch folder, HUD position, auto-dismiss
- [x] Implement Keychain-backed API key storage
- [x] Implement screenshot folder watcher (FSEvents)
- [x] Build floating HUD panel (thumbnail + prompt + ask/dismiss actions)
- [x] Implement Groq vision request payload + streaming response parsing
- [x] Build response panel UI with live streamed text + copy/dismiss
- [x] Wire end-to-end flow: screenshot detected → HUD → ask AI → stream response
- [x] Add required app configuration (`LSUIElement`, `NSScreenCaptureUsageDescription`)
- [ ] Validate by running manual smoke test (take screenshot -> HUD appears -> response streams)

## UI/UX Polish Checklist

- [x] Move prompt and response into a single HUD window
- [x] Expand HUD height when AI response starts streaming
- [x] Add Enter/Return key submit for prompt input
- [x] Apply modern translucent styling (less opaque, cleaner visual hierarchy)
- [ ] Validate interaction flow (type -> Enter/Ask -> expand -> stream)

## Settings & Controls Checklist

- [x] Add HUD top-right controls (Settings and Close)
- [x] Add secure API key field with show/hide toggle
- [x] Add "Get API key" action beside Groq section
- [x] Add Vision model dropdown with custom add option
- [x] Add Quit Service button in Preferences

## Overview

ScreenAsk is a lightweight macOS menubar app that runs silently in the background. The moment a user takes a screenshot, ScreenAsk detects it and displays a floating HUD near the native thumbnail position. From there, the user can ask any question about the screenshot in natural language and receive a streamed AI response — all without leaving their current context.

---

## Objective

- Give macOS users a zero-friction way to query AI about anything visible on their screen
- Keep the experience entirely native-feeling — no browser, no external app switching
- Use Groq's free-tier API for fast, cost-free LLM inference

---

## Core Features

| Feature | Description |
|---|---|
| Screenshot detection | Watches for new screenshots via FSEvents |
| Floating HUD | Non-intrusive overlay appears bottom-right after every screenshot |
| AI query | User types a question; screenshot is sent to Groq vision model |
| Streamed response | Answer streams into a side panel in real time |
| Menubar agent | App lives in the menubar — no Dock icon, always running |
| Model config | User can paste Groq API key and select model from preferences |

---

## System Architecture

```
┌─────────────────────────────────────────────────────┐
│                   ScreenAsk Agent                    │
│                  (menubar app)                        │
│                                                       │
│  ┌──────────────────────────────────────────────┐    │
│  │ FSEvents Watcher                             │    │
│  │ Watches ~/Desktop or screenshot folder for new .png files         │    │
│  └───────────────────────┬──────────────────────┘    │
│                          │                           │
│                          ▼                           │
│  ┌──────────────────────────────────────────────┐    │
│  │            Floating HUD (NSPanel)            │    │
│  │   - Thumbnail preview of screenshot         │    │
│  │   - Prompt input field                      │    │
│  │   - "Ask AI" button                         │    │
│  └───────────────────────┬──────────────────────┘    │
│                          │                           │
│                          ▼                           │
│  ┌──────────────────────────────────────────────┐    │
│  │            Groq API Client                   │    │
│  │   - Base64 encodes image                    │    │
│  │   - Builds multimodal message payload       │    │
│  │   - Streams response via SSE                │    │
│  └───────────────────────┬──────────────────────┘    │
│                          │                           │
│                          ▼                           │
│  ┌──────────────────────────────────────────────┐    │
│  │            Response Panel (SwiftUI)          │    │
│  │   - Markdown-rendered streamed response     │    │
│  │   - Copy / dismiss controls                 │    │
│  └──────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

---

## Workflow

```
User presses ⌘⇧4 (or any screenshot shortcut)
        │
        ▼
macOS saves screenshot to ~/Desktop (or configured folder)
        │
        ▼
FSEvents detects new .png file in watched directory
        │
        ▼
ScreenAsk reads the file into memory (CGImage)
        │
        ▼
Floating HUD appears bottom-right (300ms delay to clear native thumbnail)
HUD shows: thumbnail preview + prompt input field + "Ask AI" button
        │
        ├── User dismisses → HUD disappears, screenshot kept as normal
        │
        └── User types question + clicks Ask AI
                    │
                    ▼
            Image base64-encoded + prompt assembled
                    │
                    ▼
            POST to Groq API (llama-3.2-11b-vision-preview)
                    │
                    ▼
            Response streams into panel (SSE)
                    │
                    ▼
            User reads response, copies if needed, dismisses
```

---

## Tech Stack

| Layer | Technology | Reason |
|---|---|---|
| Language | Swift 5.9+ | Native macOS, best system API access |
| UI framework | SwiftUI + AppKit | SwiftUI for panels/responses, AppKit (NSPanel) for the overlay |
| Screen detection | FSEvents | Low-overhead file system watching, battery friendly |
| AI backend | Groq API | Free tier, fast inference, supports vision |
| Vision model | llama-3.2-11b-vision-preview | Free on Groq, handles image + text queries |
| Networking | URLSession with async/await | Native, no dependencies needed |
| Markdown rendering | swift-markdown-ui | Renders AI responses with formatting |
| Distribution | Notarized DMG | Required for Screen Recording permission |

---

## Configuration Requirements

### macOS permissions (required at first launch)

| Permission | Why needed | How requested |
|---|---|---|
| Screen Recording | FSEvents needs to read screenshot files | `NSScreenCaptureUsageDescription` in Info.plist |
| Network access | Groq API calls | Automatic (App Sandbox network entitlement) |

### User configuration (Preferences panel)

```
┌─────────────────────────────────────────┐
│  ScreenAsk Preferences                  │
│                                         │
│  Groq API Key   [____________________]  │
│                 Get free key at         │
│                 console.groq.com        │
│                                         │
│  Vision model   [llama-3.2-11b-vision] ▾│
│                                         │
│  Watch folder   [~/Desktop           ] ▾│
│                                         │
│  HUD position   ● Bottom right          │
│                 ○ Bottom left           │
│                                         │
│  Auto-dismiss   [4] seconds             │
│                                         │
│  Launch at login  [✓]                   │
└─────────────────────────────────────────┘
```

### Info.plist keys required

```xml
<key>NSScreenCaptureUsageDescription</key>
<string>ScreenAsk needs screen recording access to detect and read new screenshots.</string>

<key>LSUIElement</key>
<true/>  <!-- Hides app from Dock, menubar-only -->

<key>LSBackgroundOnly</key>
<false/>
```

---

## Project Structure

```
ScreenAsk/
├── App/
│   ├── ScreenAskApp.swift          # App entry point, menubar setup
│   └── AppDelegate.swift           # NSApplicationDelegate, permission checks
│
├── Core/
│   └── FSEventsWatcher.swift       # Watches screenshot folder for new files
│
├── UI/
│   ├── FloatingHUD.swift           # NSPanel overlay, always-on-top
│   ├── HUDView.swift               # SwiftUI view inside the HUD
│   ├── ResponsePanel.swift         # Streaming response display
│   └── PreferencesView.swift       # Settings window
│
├── AI/
│   ├── GroqClient.swift            # API client, SSE streaming
│   ├── MessageBuilder.swift        # Assembles multimodal payloads
│   └── Models.swift                # Request/response model structs
│
├── Utilities/
│   ├── ImageEncoder.swift          # CGImage → base64
│   ├── PermissionManager.swift     # Checks and requests OS permissions
│   └── KeychainManager.swift       # Secure API key storage
│
└── Resources/
    ├── Assets.xcassets             # App icon, menubar icon
    └── Info.plist
```

---

## Groq API Integration

### Endpoint

```
POST https://api.groq.com/openai/v1/chat/completions
```

### Vision request payload

```json
{
  "model": "llama-3.2-11b-vision-preview",
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "type": "image_url",
          "image_url": {
            "url": "data:image/png;base64,{BASE64_IMAGE}"
          }
        },
        {
          "type": "text",
          "text": "{USER_PROMPT}"
        }
      ]
    }
  ],
  "stream": true,
  "max_tokens": 1024
}
```

### Free tier limits (as of 2025)

| Model | Requests/min | Requests/day | Tokens/min |
|---|---|---|---|
| llama-3.2-11b-vision-preview | 30 | 1,000 | 7,000 |

Sufficient for personal use. No credit card required.

---

## Build & Distribution

### Development

```bash
# Clone and open in Xcode
git clone https://github.com/yourname/ScreenAsk.git
open ScreenAsk.xcodeproj

# Required: Xcode 15+, macOS 13+ deployment target
# Sign with your Apple Developer account
```

### Distribution (notarized DMG)

```bash
# Archive in Xcode → Distribute App → Developer ID
# Then notarize via notarytool
xcrun notarytool submit ScreenAsk.dmg \
  --apple-id your@email.com \
  --team-id YOURTEAMID \
  --password @keychain:AC_PASSWORD
```

> A free Apple Developer account allows building and running locally.  
> A paid account ($99/year) is required for notarization and distribution to others.

---

## Future Roadmap

| Phase | Feature |
|---|---|
| v1.0 | Screenshot detection + Groq vision query |
| v1.1 | Conversation history within a session |
| v1.2 | In-app region selection (ScreenCaptureKit) |
| v1.3 | macOS Services menu registration |

---

## Notes & Constraints

- **macOS 13 Ventura minimum** — required for stable ScreenCaptureKit and modern SwiftUI features
- **No App Store initially** — FSEvents + screen recording combination makes App Store sandboxing restrictive; direct notarized DMG is the pragmatic path
- **API key stored in Keychain** — never in UserDefaults or plaintext; use `SecItemAdd` / `SecItemCopyMatching`
