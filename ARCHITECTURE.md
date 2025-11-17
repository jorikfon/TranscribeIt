# TranscribeIt Architecture

> Professional macOS application for transcribing stereo telephone call recordings with automatic speaker separation

**Last updated:** November 13, 2025
**Version:** 1.0.0
**Platform:** macOS 14.0+ (Apple Silicon optimized)

---

## Table of Contents

- [Overview](#overview)
- [Architecture Principles](#architecture-principles)
- [System Architecture](#system-architecture)
- [Layer Structure](#layer-structure)
- [Core Components](#core-components)
- [Data Flow](#data-flow)
- [Dependency Injection](#dependency-injection)
- [Error Handling](#error-handling)
- [Performance Optimization](#performance-optimization)
- [Testing Strategy](#testing-strategy)
- [Development Workflow](#development-workflow)

---

## Overview

TranscribeIt is built using modern Swift patterns with a focus on:

- **Modularity**: Clean separation of concerns across layers
- **Testability**: Dependency Injection and protocol-based design
- **Performance**: Metal GPU acceleration and intelligent caching
- **Maintainability**: Well-documented, typed errors, minimal complexity

### Technology Stack

- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI + AppKit (hybrid)
- **ML Framework**: WhisperKit (CoreML + Metal)
- **Audio Processing**: AVFoundation + Accelerate
- **Concurrency**: Swift Concurrency (async/await, actors)
- **Testing**: XCTest
- **Build System**: Swift Package Manager

---

## Architecture Principles

### 1. MVVM Pattern

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│    View     │─────▶│  ViewModel  │─────▶│   Service   │
│  (SwiftUI)  │◀─────│ (ObservableObject)  │             │
└─────────────┘      └─────────────┘      └─────────────┘
                            │
                            ▼
                     ┌─────────────┐
                     │    Model    │
                     │  (Structs)  │
                     └─────────────┘
```

- **View**: Pure SwiftUI views, no business logic
- **ViewModel**: State management, user actions, data transformation
- **Service**: Business logic, API calls, data persistence
- **Model**: Immutable data structures

### 2. Dependency Injection

All services use protocol-based DI for testability:

```swift
// Protocol definition
protocol WhisperServiceProtocol {
    func transcribe(audioSamples: [Float]) async throws -> String
}

// Service accepts protocol, not concrete type
class FileTranscriptionService {
    private let whisperService: WhisperServiceProtocol

    init(whisperService: WhisperServiceProtocol) {
        self.whisperService = whisperService
    }
}
```

### 3. Layered Architecture

```
┌────────────────────────────────────────────┐
│           Presentation Layer               │
│  (Views, ViewModels, UI Components)        │
└────────────────────────────────────────────┘
                    ▼
┌────────────────────────────────────────────┐
│          Business Logic Layer              │
│  (Services, Use Cases, Domain Logic)       │
└────────────────────────────────────────────┘
                    ▼
┌────────────────────────────────────────────┐
│            Data Access Layer               │
│  (Models, Protocols, Utilities)            │
└────────────────────────────────────────────┘
```

---

## System Architecture

### High-Level Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         UI Layer                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  MainWindow  │  │ SettingsView │  │ MenuBarCtrl  │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
│         │                  │                  │               │
│         └──────────────────┴──────────────────┘              │
│                            │                                  │
└────────────────────────────┼──────────────────────────────────┘
                             │
┌────────────────────────────┼──────────────────────────────────┐
│                    ViewModel Layer                            │
│              ┌─────────────────────────────┐                 │
│              │ FileTranscriptionViewModel  │                 │
│              │  - State management         │                 │
│              │  - Progress tracking        │                 │
│              │  - User actions             │                 │
│              └─────────────┬───────────────┘                 │
└────────────────────────────┼──────────────────────────────────┘
                             │
┌────────────────────────────┼──────────────────────────────────┐
│                     Service Layer                             │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐   │
│  │ Transcription │  │    Whisper    │  │     Batch     │   │
│  │    Service    │──│    Service    │  │    Service    │   │
│  └───────┬───────┘  └───────┬───────┘  └───────────────┘   │
│          │                  │                                 │
│          └──────────────────┘                                 │
│                     │                                         │
└─────────────────────┼─────────────────────────────────────────┘
                      │
┌─────────────────────┼─────────────────────────────────────────┐
│                 Utilities Layer                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │   VAD    │  │  Audio   │  │  Cache   │  │  Export  │    │
│  │  System  │  │  Player  │  │  Actor   │  │ Manager  │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
│                                                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │  Model   │  │Vocabulary│  │   Log    │  │  User    │    │
│  │ Manager  │  │ Manager  │  │ Manager  │  │ Settings │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
└──────────────────────────────────────────────────────────────┘
                             │
┌────────────────────────────┼──────────────────────────────────┐
│                      Foundation                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │WhisperKit│  │AVFoundation  │CoreML    │  │  Metal   │    │
│  │(CoreML)  │  │           │  │          │  │   GPU    │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
└──────────────────────────────────────────────────────────────┘
```

---

## Layer Structure

### 1. Presentation Layer (`Sources/UI/`)

Responsible for user interface and user interaction.

#### Structure:
```
Sources/UI/
├── Views/
│   ├── Transcription/        # Main transcription UI
│   │   ├── FileTranscriptionView.swift
│   │   ├── HeaderView.swift
│   │   ├── ContentView.swift
│   │   ├── SettingsPanel.swift
│   │   ├── EmptyStateView.swift
│   │   └── TranscriptionViewConstants.swift
│   ├── Timeline/             # Timeline visualization
│   │   ├── TimelineSyncedDialogueView.swift
│   │   ├── TimelineDialogueView.swift
│   │   ├── CompactTurnCard.swift
│   │   ├── SilenceIndicator.swift
│   │   └── Timeline/TurnCardConstants.swift
│   └── Audio/                # Audio player UI
│       └── AudioPlayerView.swift
├── ViewModels/               # State management
│   ├── FileTranscriptionViewModel.swift
│   └── AudioPlayerState.swift
├── Components/               # Reusable UI components
│   ├── StatusIndicator.swift
│   └── ActionButton.swift
├── MainWindow.swift          # Main window controller
├── MenuBarController.swift   # Menu bar integration
└── SettingsView.swift        # Settings window
```

#### Key Patterns:
- **Component-based**: Small, focused components (<200 lines)
- **ViewBuilder**: Reusable UI building blocks
- **Constants**: Magic numbers extracted to enums
- **@Published**: Minimal state with grouped properties

### 2. Business Logic Layer (`Sources/Services/`)

Core application logic for transcription and processing.

#### Structure:
```
Sources/Services/
├── FileTranscriptionService.swift    # Main transcription orchestrator
├── BatchTranscriptionService.swift   # Multi-file processing
├── WhisperService.swift              # WhisperKit wrapper
└── ServiceConstants.swift            # Shared service constants
```

#### Responsibilities:

**FileTranscriptionService**:
- Orchestrates transcription workflow
- Handles stereo/mono detection
- VAD segmentation coordination
- Real-time progress callbacks
- Audio cache integration

**WhisperService**:
- WhisperKit model management
- Audio transcription with Metal GPU
- Context-aware transcription
- Performance metrics (RTF)

**BatchTranscriptionService**:
- Multi-file queue management
- Concurrent processing
- Batch progress tracking

### 3. Data Access Layer

#### Models (`Sources/Models/` - embedded in services)
- `DialogueTranscription` - Structured dialogue result
- `Turn` - Individual speaker turn
- `Speaker` - Speaker identification

#### Protocols (`Sources/Protocols/`)
```
Sources/Protocols/
├── VocabularyManagerProtocol.swift
├── UserSettingsProtocol.swift
└── ModelManagerProtocol.swift
```

Enable dependency injection and testing.

#### Errors (`Sources/Errors/`)
```
Sources/Errors/
├── TranscriptionError.swift    # File transcription errors
├── WhisperError.swift           # Whisper model errors
└── AudioPlayerError.swift       # Audio playback errors
```

Strongly-typed error handling with recovery suggestions.

### 4. Utilities Layer (`Sources/Utils/`)

Cross-cutting concerns and helper functionality.

#### Structure:
```
Sources/Utils/
├── Audio/
│   ├── AudioCache.swift             # Audio caching actor
│   ├── AudioPlayerManager.swift     # Audio playback
│   ├── AudioFileNormalizer.swift    # Audio preprocessing
│   └── AudioNormalizerConstants.swift
├── Timeline/
│   └── TimelineMapper.swift         # Timeline compression
├── VAD System/
│   ├── VoiceActivityDetector.swift  # Base VAD
│   ├── SpectralVAD.swift            # FFT-based VAD
│   ├── AdaptiveVAD.swift            # Adaptive threshold VAD
│   └── SilenceDetector.swift        # Silence detection
├── ModelManager.swift               # Whisper model management
├── VocabularyManager.swift          # Custom vocabulary
├── UserSettings.swift               # App settings
├── ExportManager.swift              # Multi-format export
├── LogManager.swift                 # Logging system
└── PermissionManager.swift          # System permissions
```

### 5. Dependency Injection (`Sources/DI/`)

```
Sources/DI/
└── DependencyContainer.swift        # Service locator pattern
```

Centralized dependency creation and management.

### 6. Application Entry (`Sources/App/`)

```
Sources/App/
├── TranscribeItApp.swift           # SwiftUI app lifecycle
└── AppDelegate.swift               # NSApplicationDelegate
```

---

## Core Components

### Transcription Pipeline

```
┌──────────────┐
│  User drops  │
│  audio file  │
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────────────┐
│  FileTranscriptionService                │
│  1. Detect channels (mono/stereo)        │
│  2. Load audio → AudioCache               │
│  3. Choose mode (VAD/Batch)              │
└──────┬───────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│  VAD Segmentation (if stereo)            │
│  - SpectralVAD analysis                  │
│  - Separate left/right channels          │
│  - Detect speech segments                │
│  - Sort chronologically                  │
└──────┬───────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│  Context Building & Transcription        │
│  - Build intelligent context prompt:     │
│    * Base context (domain/terminology)   │
│    * Named entities (if enabled)         │
│    * Vocabulary terms (up to 15)         │
│    * Recent dialogue (3-10 turns)        │
│  - WhisperService.transcribe()           │
│  - Apply vocabulary corrections          │
│  - Track progress (callbacks)            │
└──────┬───────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│  DialogueTranscription Result            │
│  - Speaker-separated turns               │
│  - Timestamps for each turn              │
│  - Formatted text                        │
└──────┬───────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│  UI Display                              │
│  - Timeline visualization                │
│  - Editable text/timestamps              │
│  - Audio player synchronization          │
└──────────────────────────────────────────┘
```

### Voice Activity Detection (VAD) System

Three VAD algorithms for different use cases:

#### 1. SpectralVAD (Recommended)
- **Method**: FFT frequency analysis
- **Best for**: Telephone recordings (300-3400 Hz)
- **Accuracy**: Highest for narrowband audio
- **Performance**: ~0.025s for 81s audio (RTF ~0.0003x)

#### 2. AdaptiveVAD
- **Method**: Adaptive energy threshold + ZCR
- **Best for**: Variable quality audio
- **Accuracy**: Good for dynamic environments
- **Performance**: ~0.410s for 81s audio (RTF ~0.005x)

#### 3. Standard VAD
- **Method**: Energy-based threshold
- **Best for**: High-quality recordings
- **Accuracy**: Good for clean audio
- **Performance**: Fastest

**Selection Strategy:**
```swift
// Telephone recordings (most common)
service.vadAlgorithm = .telephone  // SpectralVAD 300-3400 Hz

// Professional recordings
service.vadAlgorithm = .wideband   // SpectralVAD 80-8000 Hz

// Unknown quality
service.vadAlgorithm = .adaptive   // AdaptiveVAD
```

### Audio Cache System

Thread-safe actor-based caching to prevent redundant file loading:

```
┌─────────────────────────────────────────┐
│          AudioCache (Actor)             │
│  ┌───────────────────────────────────┐ │
│  │  Cache Entry:                     │ │
│  │  - monoSamples: [Float]           │ │
│  │  - stereoChannels: (L, R)?        │ │
│  │  - sampleRate: Double             │ │
│  │  - duration: TimeInterval         │ │
│  │  - loadedAt: Date                 │ │
│  └───────────────────────────────────┘ │
│                                          │
│  Strategy: LRU eviction                 │
│  TTL: 5 minutes                         │
│  Max size: 500 MB                       │
│  Max files: 3                           │
└─────────────────────────────────────────┘
```

**Benefits:**
- Eliminates duplicate loads (3x → 1x)
- Shared across services
- Memory-efficient LRU eviction
- Statistics tracking

---

## Data Flow

### Stereo Transcription Flow (Detailed)

```
┌────────────────────────────────────────────────────────────────┐
│ 1. FILE LOADING                                                │
│    FileTranscriptionService.transcribeFileWithDialogue()       │
│    ↓                                                            │
│    Check Whisper model ready (60s timeout)                    │
│    ↓                                                            │
│    Detect channel count: AVAsset → 2 channels                  │
└────────────────┬───────────────────────────────────────────────┘
                 │
┌────────────────▼───────────────────────────────────────────────┐
│ 2. STEREO SEPARATION                                           │
│    prepareStereoChanels(url)                                   │
│    ↓                                                            │
│    AudioCache.loadAudio() → CachedAudio                        │
│    ↓                                                            │
│    Extract channels:                                           │
│      - Left: [Float] (Speaker 1)                               │
│      - Right: [Float] (Speaker 2)                              │
│    ↓                                                            │
│    Duration: samples.count / 16000 Hz                          │
└────────────────┬───────────────────────────────────────────────┘
                 │
┌────────────────▼───────────────────────────────────────────────┐
│ 3. VAD SEGMENTATION                                            │
│    detectAndMergeStereoSegments(left, right)                   │
│    ↓                                                            │
│    SpectralVAD.detectSpeechSegments(left)                      │
│      → [SpeechSegment] with timestamps                         │
│    ↓                                                            │
│    SpectralVAD.detectSpeechSegments(right)                     │
│      → [SpeechSegment] with timestamps                         │
│    ↓                                                            │
│    Merge & sort by startTime:                                  │
│      [ChannelSegment] chronologically ordered                  │
└────────────────┬───────────────────────────────────────────────┘
                 │
┌────────────────▼───────────────────────────────────────────────┐
│ 4. TRANSCRIPTION WITH CONTEXT                                  │
│    transcribeSegmentsInOrder(segments)                         │
│    ↓                                                            │
│    For each segment chronologically:                           │
│      ├─ Check for silence → skip                               │
│      ├─ Build context prompt:                                  │
│      │    * Base context (if configured)                       │
│      │    * Named entities from recent 20 turns (if enabled)   │
│      │    * Vocabulary terms up to 15 (if enabled)             │
│      │    * Last 3-10 dialogue turns (configurable)            │
│      │    * Smart truncation at word boundaries (300-700 chars)│
│      ├─ WhisperService.transcribe(audio, context)             │
│      ├─ VocabularyManager corrections                          │
│      ├─ Create Turn(speaker, text, time)                       │
│      └─ onProgressUpdate callback                              │
└────────────────┬───────────────────────────────────────────────┘
                 │
┌────────────────▼───────────────────────────────────────────────┐
│ 5. RESULT CONSTRUCTION                                         │
│    DialogueTranscription(                                      │
│      turns: [Turn],                                            │
│      isStereo: true,                                           │
│      totalDuration: TimeInterval                               │
│    )                                                            │
└────────────────┬───────────────────────────────────────────────┘
                 │
┌────────────────▼───────────────────────────────────────────────┐
│ 6. UI UPDATE                                                   │
│    FileTranscriptionViewModel                                  │
│    ↓                                                            │
│    @Published state = .completed(dialogue)                     │
│    ↓                                                            │
│    TimelineSyncedDialogueView renders                          │
│    AudioPlayerView loads waveform                              │
└────────────────────────────────────────────────────────────────┘
```

### State Management Flow

```
┌──────────────────────────────────────────┐
│  FileTranscriptionViewModel              │
│                                           │
│  @Published var state: Status            │
│    .idle                                  │
│    .processing(progress, fileName)       │
│    .completed(FileTranscription)         │
│    .error(Error)                         │
└──────────────┬───────────────────────────┘
               │
               │ State changes trigger
               │ SwiftUI view updates
               ▼
┌──────────────────────────────────────────┐
│  FileTranscriptionView                   │
│  (observes ViewModel)                    │
│                                           │
│  body updates automatically:             │
│    - idle: EmptyStateView                │
│    - processing: ProgressView            │
│    - completed: ContentView              │
│    - error: Error alert                  │
└──────────────────────────────────────────┘
```

---

## Dependency Injection

### Container Pattern

```swift
// Sources/DI/DependencyContainer.swift
public class DependencyContainer {
    // Singletons
    public let modelManager: ModelManager
    public let userSettings: UserSettings
    private let audioCache = AudioCache()

    // Factory methods
    public func makeWhisperService() -> WhisperService {
        WhisperService(
            modelSize: modelManager.currentModel,
            vocabularyManager: makeVocabularyManager()
        )
    }

    public func makeFileTranscriptionService() -> FileTranscriptionService {
        FileTranscriptionService(
            whisperService: makeWhisperService(),
            userSettings: userSettings,
            audioCache: audioCache
        )
    }
}
```

### Usage in AppDelegate

```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    private let dependencies = DependencyContainer()

    func performTranscription(files: [URL]) {
        let service = dependencies.makeFileTranscriptionService()
        // Use service...
    }
}
```

### Testing with Mocks

```swift
// Tests/Mocks/MockWhisperService.swift
class MockWhisperService: WhisperServiceProtocol {
    var transcribeCallCount = 0
    var stubbedResult = "Mock transcription"

    func transcribe(audioSamples: [Float]) async throws -> String {
        transcribeCallCount += 1
        return stubbedResult
    }
}

// Test usage
let mockWhisper = MockWhisperService()
let service = FileTranscriptionService(
    whisperService: mockWhisper,
    userSettings: MockUserSettings(),
    audioCache: AudioCache()
)
```

---

## Error Handling

### Typed Errors

All errors are strongly typed with `LocalizedError` conformance:

```swift
// Sources/Errors/TranscriptionError.swift
enum TranscriptionError: LocalizedError {
    case serviceNotInitialized(String)
    case audioLoadFailed(URL, underlying: Error)
    case noAudioTrack(URL)
    case modelNotReady
    case silenceDetected(URL)

    var errorDescription: String? { /* ... */ }
    var recoverySuggestion: String? { /* ... */ }
    var failureReason: String? { /* ... */ }
}
```

### Error Propagation

```
Service Layer
    ↓ throws TranscriptionError
ViewModel Layer
    ↓ catch & convert to @Published state
View Layer
    ↓ display user-friendly alert
```

### Recovery Strategies

```swift
do {
    let dialogue = try await service.transcribeFileWithDialogue(at: url)
} catch TranscriptionError.modelNotReady {
    // Wait and retry
    try await Task.sleep(for: .seconds(5))
    retry()
} catch TranscriptionError.silenceDetected(let url) {
    // Show specific message
    showAlert("File contains only silence: \(url.lastPathComponent)")
} catch {
    // Generic error handling
    showAlert(error.localizedDescription)
}
```

---

## Performance Optimization

### 1. Audio Cache

**Problem**: Same file loaded 3 times (transcription mono + stereo + playback)

**Solution**: Actor-based cache with LRU eviction

**Result**:
- First load: ~5s
- Cached load: <0.1s (50x faster)

### 2. VAD Optimization

**SpectralVAD Performance**:
- 81s audio → 0.025s processing
- Real-Time Factor: 0.0003x
- Uses Accelerate framework for FFT

### 3. Metal GPU Acceleration

WhisperKit uses Metal for transcription:
- Model inference on GPU
- Neural Engine utilization
- Typical RTF: 0.15-0.25x (4-6x faster than real-time)

### 4. Concurrent Processing

```swift
// Parallel segment transcription (if independent)
await withTaskGroup(of: Turn.self) { group in
    for segment in segments {
        group.addTask {
            try await transcribeSegment(segment)
        }
    }

    for await turn in group {
        turns.append(turn)
    }
}
```

### 5. Memory Management

- Streaming audio processing (no full file in memory)
- Automatic cache eviction (LRU)
- Waveform downsampling for display

---

## Testing Strategy

### Test Coverage

Current: **106 tests** (97.9% core logic coverage)

```
Tests/
├── Mocks/                           # 15 tests
│   ├── MockVocabularyManager.swift
│   ├── MockUserSettings.swift
│   ├── MockModelManager.swift
│   └── MockUsageExamples.swift
├── Utils/
│   ├── Timeline/
│   │   └── TimelineMapperTests.swift       # 21 tests
│   ├── VAD/
│   │   ├── SpectralVADTests.swift          # 20 tests
│   │   └── VADIntegrationTests.swift       # 12 tests
│   └── AudioNormalizerTests.swift          # 9 tests
├── UI/
│   └── ViewModels/
│       └── FileTranscriptionViewModelTests.swift  # 27 tests
└── TranscribeItCoreTests.swift      # 2 tests
```

### Test Pyramid

```
         ▲
        ╱ ╲
       ╱ 2 ╲     Integration Tests (VAD, Audio)
      ╱─────╲
     ╱  27   ╲    Unit Tests (ViewModels, Utils)
    ╱─────────╲
   ╱    77     ╲  Component Tests (Mocks, Mappers)
  ╱─────────────╲
 └───────────────┘
```

### Testing Guidelines

**Unit Tests:**
- Test single component in isolation
- Use mocks for dependencies
- Fast execution (<1s)

**Integration Tests:**
- Test component interaction
- Use real audio files (Tests/Fixtures/audio/)
- Validate end-to-end behavior

**Performance Tests:**
- Measure RTF for VAD algorithms
- Track cache hit rates
- Monitor memory usage

---

## Development Workflow

### Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Run app
.build/debug/TranscribeIt

# Build .app bundle
./build_app.sh
```

### Testing

```bash
# Run all tests
swift test

# Run specific test
swift test --filter TimelineMapperTests

# Run with parallel execution
swift test --parallel
```

### Code Quality

**Standards:**
- Max file size: 500 lines
- Max method length: 50 lines
- Magic numbers: Use constants
- Documentation: All public APIs

**Tools:**
- SwiftLint (code style)
- Swift Format (formatting)
- XCTest (testing)

### Git Workflow

```bash
# Feature branch
git checkout -b feature/new-vad-algorithm

# Commit format (conventional commits)
git commit -m "feat: add energy-based VAD algorithm

- Implement energy threshold detection
- Add unit tests for VAD
- Update documentation

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"

# Pull request
gh pr create --title "feat: Energy-based VAD" --body "..."
```

---

## Directory Structure Summary

```
TranscribeIt/
├── Sources/
│   ├── App/                  # Application entry point
│   ├── DI/                   # Dependency injection
│   ├── Errors/               # Typed error definitions
│   ├── Protocols/            # Protocol definitions for DI
│   ├── Services/             # Business logic layer
│   ├── UI/                   # Presentation layer
│   │   ├── Components/       # Reusable UI components
│   │   ├── ViewModels/       # State management
│   │   └── Views/            # SwiftUI views
│   └── Utils/                # Utilities and helpers
│       ├── Audio/            # Audio processing utilities
│       └── Timeline/         # Timeline utilities
├── Tests/                    # Test suite
│   ├── Mocks/                # Mock implementations
│   ├── Utils/                # Utility tests
│   ├── UI/                   # UI tests
│   ├── Integration/          # Integration tests
│   └── Fixtures/             # Test data
├── Package.swift             # SPM configuration
├── CLAUDE.md                 # Development guide
├── ARCHITECTURE.md           # This file
└── README.md                 # User documentation
```

---

## Key Design Decisions

### 1. Why SwiftUI + AppKit Hybrid?

- **SwiftUI**: Modern UI, declarative syntax, easy state management
- **AppKit**: Menu bar integration, advanced window management, file dialogs
- **Hybrid**: Best of both worlds for desktop app

### 2. Why Actor for AudioCache?

- Thread-safe without locks
- Clean async/await integration
- Prevents data races
- Automatic synchronization

### 3. Why Protocol-Based DI?

- Testability: Easy to mock dependencies
- Flexibility: Swap implementations
- Decoupling: Services don't know concrete types
- Refactoring: Change implementations without breaking consumers

### 4. Why Multiple VAD Algorithms?

Different audio qualities require different strategies:
- Telephone: SpectralVAD (narrowband optimized)
- Professional: SpectralVAD (wideband)
- Unknown: AdaptiveVAD (adaptive threshold)

### 5. Why Context in Transcription?

Whisper accuracy improves significantly with context:
- Better name recognition
- Improved terminology consistency
- Reduced hallucinations
- Natural dialogue flow

---

## Future Improvements

### Planned Features
- [ ] Live recording transcription
- [ ] Speaker diarization for mono files
- [ ] Multi-language support (auto-detect)
- [ ] Cloud backup integration
- [ ] Collaboration features

### Technical Debt
- [ ] Add UI tests (XCUITest)
- [ ] Implement undo/redo for edits
- [ ] Add telemetry for performance monitoring
- [ ] Optimize memory usage for large files (>1 hour)

---

## References

### Documentation
- [WhisperKit Documentation](https://github.com/argmaxinc/WhisperKit)
- [Swift Concurrency Guide](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [AVFoundation Audio Programming](https://developer.apple.com/documentation/avfoundation)

### Architecture Patterns
- [MVVM in SwiftUI](https://developer.apple.com/tutorials/swiftui)
- [Dependency Injection in Swift](https://www.swiftbysundell.com/articles/dependency-injection-using-factories-in-swift/)
- [Actor-based Concurrency](https://www.swift.org/blog/swift-5.5-released/)

---

**Document maintained by**: Development Team
**Last reviewed**: November 13, 2025
**Next review**: Quarterly
