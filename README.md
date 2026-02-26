<p align="center">
  <img src="assets/logo.png" alt="MyBuddy Logo" width="120" />
</p>

<h1 align="center">MyBuddy</h1>

<p align="center">
  <strong>A privacy-first AI companion with on-device LLM, voice interaction, 3D avatar, and floating overlay - built with Flutter.</strong>
</p>

<p align="center">
  <a href="#key-features">Features</a> &bull;
  <a href="#architecture">Architecture</a> &bull;
  <a href="#tech-stack">Tech Stack</a> &bull;
  <a href="#getting-started">Getting Started</a> &bull;
  <a href="#configuration">Configuration</a> &bull;
  <a href="#license">License</a>
</p>

---

## Overview

MyBuddy is a conversational AI assistant that runs large language models and speech recognition **entirely on-device**. No cloud APIs, no data leaving the phone. It ships with a 3D animated avatar powered by Unity, a three-layer persistent memory system, Google Calendar integration via natural language, a floating overlay for multitasking, and a polished glassmorphism UI built on Material 3.

---

## Key Features

### On-Device LLM Inference

- Run Gemma, Qwen, DeepSeek, Llama, and Hammer models locally via `flutter_gemma`
- Zero cloud dependency - all inference happens on the user's device
- Configurable temperature, top-K, top-P, max tokens, random seed, and thinking mode
- Serial inference queue prevents concurrent execution and ensures stability
- Function calling support for animation dispatch and calendar event creation

### Voice Interaction

- **Speech-to-Text** - On-device transcription powered by Whisper.cpp (via `whisper_ggml_plus`)
- **Text-to-Speech** - Platform-native TTS with WAV file synthesis for avatar lip-sync
- Hold-to-record interface with automatic transcription and submission
- 100+ supported languages for speech recognition
- Optional CoreML/Metal acceleration on Apple platforms

### 3D Animated Avatar

- Embedded Unity scene renders a 3D character with real-time lip-sync
- 10 character animations: jump, spin, think, clap, chicken dance, thankful, greet, and 3 dance styles
- LLM-triggered animations via function calling - the AI animates itself contextually
- MethodChannel bridge for Flutter-Unity communication

### Three-Layer Persistent Memory

MyBuddy uses a structured memory system that the LLM reads and updates across sessions:

| Layer | Contents |
|-------|----------|
| **Soul** | Core personality, mission, principles, boundaries, response style |
| **Identity** | Assistant name, role, voice/tone, behavior rules |
| **User Profile** | User's name, traits, preferences, goals, facts |

- LLM-driven self-reflection extracts and merges stable facts after each conversation
- User-editable memory with per-field locking and auto-update toggle
- Memory schema versioning with automatic migration from legacy formats

### Floating Overlay Window

- System-level overlay lets the user chat and use voice while in other apps
- Three UI modes: **Minimal**, **Balanced**, and **Avatar-lite**
- Full bidirectional IPC between the overlay process and the main app via `BasicMessageChannel`
- Supports both chat requests and STT requests from the overlay
- Auto-open when the app moves to the background (configurable)
- Draggable and resizable with configurable custom height

### Google Calendar Integration

- Full calendar UI with monthly grid view, event list, and event creation
- Natural language event creation - tell the AI to schedule something and it creates a calendar event via function call
- Google Sign-In with OAuth, full event CRUD via Google Calendar API
- Fetch events by week or month, timezone-aware scheduling

### Smart Notifications

- Scheduled daily reminders with friendly, randomized messages
- Notification scheduling window (9 AM to 8 PM) with 6-day lookahead
- Auto-cancellation when the app is in the foreground
- Timezone-aware scheduling via `flutter_timezone`

### Glassmorphism Design System

A custom set of reusable UI components built on dark-themed Material 3:

- `GlassSurface` - Core backdrop-filter surface with configurable blur and opacity
- `GlassCard` - Frosted-glass card container
- `GlassPanel` - Section panel with glass effect
- `GlassChatBubble` - Chat message bubble
- `GlassIconButton` - Icon button with glass hover/press states
- `GlassPill` - Compact pill-shaped label

---

## Architecture

MyBuddy follows a **feature-first architecture** with a shared core services layer and Riverpod for state management.

```
lib/
├── main.dart                    # Entry point, lifecycle observer, overlay entry
├── app/                         # App-wide controllers & Riverpod providers
│   ├── app_controller.dart      # Central orchestrator (LLM, chat, memory)
│   ├── model_controller.dart    # LLM model catalog, download, selection
│   ├── stt_model_controller.dart# STT model catalog, download, selection
│   ├── providers.dart           # All Riverpod provider definitions
│   └── my_app.dart              # MaterialApp with theme configuration
│
├── core/                        # Domain services (no UI dependencies)
│   ├── audio/                   # Audio recording (16kHz mono WAV)
│   ├── google/                  # Google Auth & Calendar API services
│   ├── llm/                     # LLM inference, function calling, tools, animation types
│   ├── memory/                  # Three-layer persistent memory with LLM-driven reflection
│   ├── model/                   # LLM model catalog, store, and selection persistence
│   ├── notification/            # Scheduled notifications & app lifecycle observer
│   ├── overlay/                 # Overlay service, preferences, chat relay, app proxy
│   ├── stt/                     # STT catalog, store, transcription, language support
│   ├── tts/                     # Text-to-speech WAV synthesis
│   ├── unity/                   # MethodChannel bridge to embedded Unity scene
│   └── utils/                   # Formatting utilities
│
├── features/                    # Feature modules
│   ├── chat/                    # Main conversation UI, composer, transcript, memory editor
│   ├── google_calendar/         # Calendar page, grid, event list, add/edit forms
│   ├── overlay/                 # Floating overlay host app & UI
│   └── settings/                # Settings tabs (General, Personalization, Notifications, LLM, STT)
│
├── shared/                      # Reusable UI components
│   ├── widgets/glass/           # Glassmorphism design system
│   └── utils/                   # Shared utilities (JSON extraction, etc.)
│
packages/
├── whisper_ggml_plus/           # Local Flutter FFI plugin wrapping whisper.cpp
└── flutter_overlay_window/      # Local plugin for system-level overlay windows
```

### Design Patterns

| Pattern | Usage |
|---------|-------|
| **Service Layer** | Each capability is a standalone service class (`LlmService`, `SttService`, `TtsService`, `MemoryService`, `OverlayService`) |
| **Catalog + Store + Selection** | Consistent tri-part model management for both LLM and STT models |
| **Riverpod Providers** | `ChangeNotifierProvider` for reactive state across controllers and services |
| **Generation-Based Cancellation** | Async operations use incrementing counters to discard stale callbacks |
| **Serial Queue** | `LlmService` enqueues inference requests to prevent concurrent execution |
| **Background Isolates** | Memory prompt building, ZIP extraction, and Whisper transcription run off the main thread |
| **Process Proxy** | `OverlayAppProxy` extends `AppController` to relay requests over IPC to the main app process |

### Conversation Flow

```
User holds mic -> Record audio (16kHz WAV)
    -> Whisper.cpp transcription (on-device)
    -> Text auto-submitted to LLM
    -> LLM generates response (+ optional function calls)
    -> Function calls dispatched (animate avatar, create calendar event, update memory)
    -> Response displayed in chat
    -> TTS synthesizes response to WAV
    -> Unity avatar lip-syncs to audio
```

### Overlay Architecture

```
Main App Process                     Overlay Process
+-------------------------+         +-------------------------+
| AppController           |         | OverlayAppProxy         |
| LlmService              |  IPC    | (extends AppController) |
| SttService               <-------> OverlaySttService        |
| OverlayChatRelay         |         | Overlay UI              |
+-------------------------+         +-------------------------+
  BasicMessageChannel (bidirectional JSON messaging)
```

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| **Framework** | Flutter 3+ / Dart ^3.9.2 |
| **State Management** | Riverpod 3.x |
| **LLM Inference** | flutter_gemma (GGML/GGUF models) |
| **Speech-to-Text** | whisper_ggml_plus (whisper.cpp v1.8.3 via FFI) |
| **Text-to-Speech** | flutter_tts (platform-native engines) |
| **3D Avatar** | Embedded Unity (Android via unityLibrary) |
| **Overlay** | flutter_overlay_window (system-level floating window) |
| **Auth** | Google Sign-In + OAuth |
| **Calendar** | Google Calendar API (googleapis) |
| **Notifications** | flutter_local_notifications |
| **HTTP** | Dio (model downloads with progress), http (auth) |
| **Storage** | SharedPreferences, path_provider |
| **Toast/Alerts** | toastification |
| **Design System** | Custom glassmorphism (dark theme, Material 3) |

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (channel stable, Dart ^3.9.2)
- Android Studio or Xcode (for platform builds)
- For Android: NDK `29.0.13113456` (configured automatically)
- For iOS/macOS: Xcode with CoreML support (optional, for STT acceleration)

### Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/newnonsick/MyBuddy.git
   cd MyBuddy
   ```

2. **Install dependencies**

   ```bash
   flutter pub get
   ```

3. **Configure Google API credentials** (see [Configuration](#configuration))

4. **Run the app**

   ```bash
   flutter run
   ```

### First Launch

1. Open **Settings** and navigate to the **LLM** tab
2. Browse the model catalog and download a model (smaller models like Qwen or Gemma variants recommended for first use)
3. Navigate to the **STT** tab and download a Whisper model (tiny or base recommended for faster downloads)
4. Return to the home screen and start chatting

---

## Configuration

### Google Calendar (Optional)

Google Calendar integration requires OAuth credentials:

1. Create a project in the [Google Cloud Console](https://console.cloud.google.com/)
2. Enable the **Google Calendar API**
3. Create OAuth 2.0 credentials (Android client ID and Web/Server client ID)
4. Pass credentials at build time:

   ```bash
   flutter run \
     --dart-define=GOOGLE_CLIENT_ID_ANDROID=<your-android-client-id> \
     --dart-define=GOOGLE_SERVER_CLIENT_ID=<your-server-client-id>
   ```

The `env.json` file in the project root serves as a reference template for the required credential keys.

### Model Catalogs

LLM and STT model catalogs are fetched from remote JSON files hosted on GitHub:

- **LLM Catalog**: `newnonsick/MyBuddy-cfg/llm_models.json`
- **STT Catalog**: `newnonsick/MyBuddy-cfg/stt_models.json`

Models are downloaded from Google Drive or direct URLs and stored locally on the device.

---

## Model Management

### LLM Models

MyBuddy supports multiple LLM architectures through `flutter_gemma`:

| Model Type | Examples |
|------------|----------|
| Gemma | Gemma 2B, Gemma 7B |
| Qwen | Qwen 2.5 series |
| DeepSeek | DeepSeek R1 distills |
| Llama | Llama 3.x variants |
| Hammer | Function-calling specialized |

Each model includes configuration metadata: type, max tokens, token buffer, temperature, top-K/P, random seed, thinking mode, file type, and function call support.

### STT Models

Whisper models are available in multiple sizes:

| Size | Parameters | Use Case |
|------|-----------|----------|
| Tiny | 39M | Fastest, lower accuracy |
| Base | 74M | Good balance for mobile |
| Small | 244M | Higher accuracy |
| Medium | 769M | Near-best accuracy |
| Large v3 Turbo | 809M | Best quality with optimized speed |

On iOS and macOS, optional **CoreML encoder** downloads enable hardware-accelerated inference via the Apple Neural Engine.

### Storage

- LLM models: `<app_documents>/models/`
- STT models: `<app_documents>/stt_models/`
- Registry files track installed models with metadata (size, download date, config)
- Downloads use atomic `.partial` file pattern with progress tracking and cancellation support

---

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| **Android** | Primary | Full feature set including Unity 3D avatar and floating overlay (min SDK 24, target SDK 36) |
| **iOS** | Future Support | Voice and text chat, model management, calendar, and notifications (no overlay, no Unity avatar) |

> **Note**: The Unity 3D avatar integration and floating overlay window are currently configured for Android only. The core conversational AI features work cross-platform without these capabilities.

---

## Dependencies

### Runtime

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | Reactive state management |
| `flutter_gemma` | On-device LLM inference engine |
| `whisper_ggml_plus` | Whisper.cpp FFI for speech-to-text |
| `record` | Audio recording (16kHz mono WAV) |
| `flutter_tts` | Platform text-to-speech synthesis |
| `flutter_overlay_window` | System-level floating overlay windows |
| `dio` | HTTP client for model downloads (progress, cancellation) |
| `http` | HTTP client for authenticated API requests |
| `path_provider` | Platform-specific directory paths |
| `shared_preferences` | Key-value persistence (preferences, model selection, memory) |
| `archive` | ZIP extraction for CoreML model bundles |
| `flutter_local_notifications` | Scheduled local notifications |
| `timezone` / `flutter_timezone` | Timezone-aware notification scheduling |
| `google_sign_in` | Google OAuth authentication |
| `googleapis` | Google Calendar REST API client |
| `extension_google_sign_in_as_googleapis_auth` | OAuth bridge for googleapis |
| `toastification` | In-app toast notifications |

### Local Packages

| Package | Purpose |
|---------|---------|
| `whisper_ggml_plus` | Flutter FFI plugin wrapping whisper.cpp v1.8.3 with support for all model sizes, VAD, and CoreML/Metal acceleration on Apple platforms |
| `flutter_overlay_window` | Flutter plugin for Android system overlay windows with bidirectional data sharing and lifecycle management |

---

## License

This project is licensed under the **Apache License 2.0**. See the [LICENSE](LICENSE) file for details.

Copyright 2026 Thitivath Mongkolgittichot
