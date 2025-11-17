
@sessions/CLAUDE.sessions.md

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**TranscribeIt** is a professional desktop application for transcribing **stereo telephone call recordings** on Apple Silicon (M1/M2/M3).

### Key Features
- **Dual-channel speaker separation**: Left and right audio channels are processed separately to distinguish between two speakers
- **On-device transcription**: Uses WhisperKit with Metal GPU acceleration for privacy and speed
- **Timeline visualization**: Compressed timeline view with silence gap detection and synchronized dual-speaker display
- **Multi-format export**: SRT, VTT, TXT, DOCX, JSON formats with speaker labels
- **Audio playback controls**: Variable speed (0.5x-2.0x), mono/stereo switching, volume boost (100%-500%)

### Primary Use Case
Processing stereo telephone recordings where:
- **Left channel** = Speaker 1 (caller)
- **Right channel** = Speaker 2 (recipient)

The application is built with **Swift** using **MVVM architecture** and **WhisperKit** for on-device speech recognition with Metal GPU acceleration.

## Architecture Overview

### Code Metrics
- **Total Swift Code**: ~10,720 lines organized into focused modules
- **Average File Size**: ~200 lines
- **Architecture Pattern**: MVVM with Dependency Injection
- **Test Coverage Goal**: >60% for core logic

### Directory Structure

```
Sources/
├── DI/                        # Dependency Injection
│   └── DependencyContainer.swift
├── Protocols/                 # Protocol abstractions for testability
│   ├── VocabularyManagerProtocol.swift
│   ├── UserSettingsProtocol.swift
│   └── ModelManagerProtocol.swift
├── Errors/                    # Typed error handling
│   ├── TranscriptionError.swift
│   ├── WhisperError.swift
│   └── AudioPlayerError.swift
├── Services/                  # Business logic layer
│   ├── WhisperService.swift
│   ├── FileTranscriptionService.swift
│   └── BatchTranscriptionService.swift
├── UI/
│   ├── ViewModels/           # MVVM ViewModels
│   │   ├── FileTranscriptionViewModel.swift
│   │   └── AudioPlayerState.swift
│   ├── Views/                # Modular SwiftUI views
│   │   ├── Transcription/   # Main transcription UI
│   │   ├── Audio/           # Audio player controls
│   │   └── Timeline/        # Timeline visualization
│   ├── MainWindow.swift
│   ├── AppDelegate.swift
│   └── MenuBarController.swift
└── Utils/
    ├── Audio/                # Audio-specific utilities
    │   └── AudioCache.swift  # Actor-based audio caching
    ├── Timeline/             # Timeline compression logic
    │   └── TimelineMapper.swift
    ├── ModelManager.swift
    ├── VocabularyManager.swift
    ├── UserSettings.swift
    ├── AudioPlayerManager.swift
    ├── ExportManager.swift
    └── VAD/                  # Voice Activity Detection

Tests/
├── Mocks/                    # Mock implementations for testing
│   ├── MockVocabularyManager.swift
│   ├── MockUserSettings.swift
│   └── MockModelManager.swift
├── Utils/
│   ├── Timeline/TimelineMapperTests.swift
│   └── VAD/SpectralVADTests.swift
└── UI/ViewModels/FileTranscriptionViewModelTests.swift
```

## Core Architectural Patterns

### 1. Dependency Injection (Service Locator Pattern)

**DependencyContainer** (`Sources/DI/DependencyContainer.swift`):
```swift
public final class DependencyContainer {
    // Shared singletons
    public let modelManager: ModelManager
    public let userSettings: UserSettings
    private let vocabularyManager: VocabularyManagerProtocol
    public let audioCache: AudioCache

    // Service factories
    public func makeWhisperService() -> WhisperService
    public func makeFileTranscriptionService(whisperService:) -> FileTranscriptionService
    public func makeBatchTranscriptionService(whisperService:) -> BatchTranscriptionService
}
```

**Benefits**:
- Single source of truth for dependencies
- Easy to mock for testing
- Clear dependency graph
- Supports both concrete types and protocols

**Usage**:
```swift
// TranscribeItApp.swift
let dependencies = DependencyContainer(
    modelManager: ModelManager.shared,
    userSettings: UserSettings.shared,
    vocabularyManager: VocabularyManager.shared,
    audioCache: AudioCache()
)
```

### 2. Protocol-Oriented Design

Three core protocols enable testability:

**VocabularyManagerProtocol** - Text corrections and custom vocabulary
**UserSettingsProtocol** - Application settings and preferences
**ModelManagerProtocol** - Whisper model management

**Benefits**:
- Enables dependency injection with mock implementations
- Reduces coupling between components
- Clear contracts between layers
- Better IDE support and autocomplete

### 3. MVVM (Model-View-ViewModel)

**FileTranscriptionViewModel** (`Sources/UI/ViewModels/FileTranscriptionViewModel.swift`):
```swift
public class FileTranscriptionViewModel: ObservableObject {
    @Published public var state: TranscriptionState = .idle
    @Published public var progress: Double = 0.0
    @Published public var currentTranscription: FileTranscription?

    public let audioPlayer: AudioPlayerManager

    public func startTranscription(file: URL)
    public func updateProgress(file: String, progress: Double)
    public func setTranscription(file: String, text: String, fileURL: URL)
}
```

**AudioPlayerState** - Structured state management:
```swift
public struct AudioPlayerState: Equatable {
    var playback: PlaybackState      // Play/pause, position, duration
    var audio: AudioState            // Volume, boost
    var settings: AudioSettings      // Speed, mono mode
}
```

**Data Flow**:
```
User Action → View → ViewModel → Service → Model → ViewModel → View
```

### 4. Typed Error Handling

**TranscriptionError** (`Sources/Errors/TranscriptionError.swift`):
```swift
public enum TranscriptionError: LocalizedError {
    case fileNotFound(URL)
    case audioLoadFailed(URL, underlying: Error)
    case modelNotReady
    case transcriptionTimeout(duration: TimeInterval)
    case silenceDetected(URL)
    case emptyTranscription(URL)
    // ... and more

    // Each provides:
    public var errorDescription: String?        // User-friendly Russian message
    public var recoverySuggestion: String?      // Actionable steps
    public var failureReason: String?           // Technical details
}
```

**WhisperError** - Model loading and transcription errors
**AudioPlayerError** - Audio playback and format errors

**Benefits**:
- Type-safe error handling
- Eliminates generic `NSError` usage
- Localized error messages
- Clear error propagation

### 5. Actor-Based Concurrency

**AudioCache** (`Sources/Utils/Audio/AudioCache.swift`):
```swift
public actor AudioCache {
    struct CachedAudio {
        let monoSamples: [Float]                    // 16kHz mono for transcription
        let stereoChannels: (left: [Float], right: [Float])?
        let sampleRate: Double
        let duration: TimeInterval
    }

    func loadAudio(from url: URL) async throws -> CachedAudio
    func isCached(_ url: URL) -> Bool
    func clearCache()
}
```

**Problem Solved**: Audio files were previously loaded 3 times (mono transcription, stereo separation, playback)
**Solution**: Single load with both formats, LRU cache, ~66% reduction in file I/O

## Core Services

### 1. WhisperService (`Sources/Services/WhisperService.swift`)

**Responsibilities**:
- WhisperKit model loading and management
- On-device transcription with Metal GPU
- Performance metrics (Real-Time Factor tracking)
- Audio normalization
- Vocabulary corrections integration
- Context prompt tokenization via WhisperKit tokenizer

**Key Methods**:
```swift
public func loadModel() async throws
public func transcribe(audioSamples: [Float], contextPrompt: String?) async throws -> String
public func verifyMetalAcceleration()
public func reloadModel(newModelSize: String) async throws
```

**Dependencies**: `VocabularyManagerProtocol`, `AudioNormalizer`

**Context Prompt Tokenization**:
When a context prompt is provided to `transcribe()`, it's tokenized using WhisperKit's built-in tokenizer:
```swift
if let tokenizer = whisperKit?.tokenizer {
    promptTokens = tokenizer.encode(text: contextPrompt)
    // Tokens passed to transcribeInternal() for proper context injection
}
```
This ensures the context is properly understood by the Whisper model decoder.

### 2. FileTranscriptionService (`Sources/Services/FileTranscriptionService.swift`)

**Responsibilities**:
- Single file transcription workflow
- Audio format conversion via AudioCache
- Stereo channel separation with VAD
- Context-aware segment transcription with intelligent prompt building
- Real-time progress tracking
- Base context prompt injection for domain/terminology understanding

**Key Methods**:
```swift
public func transcribeFile(url: URL, updateProgress: @escaping (Double) -> Void) async throws -> DialogueTranscription
private func buildContextPrompt(from turns: [DialogueTranscription.Turn], maxTurns: Int? = nil) -> String
private func mergeAdjacentSegments(_ segments: [ChannelSegment], maxGap: TimeInterval) -> [ChannelSegment]
private func extractNamedEntities(from turns: [DialogueTranscription.Turn]) -> [String]
```

**Dependencies**: `WhisperService`, `UserSettingsProtocol`, `AudioCache`

**Flow**:
1. Load audio via AudioCache (checks cache first)
2. Detect voice activity segments with VAD
3. **Post-VAD merge**: Combine adjacent same-speaker segments with gaps < threshold
4. Build context prompt combining:
   - Base context prompt (domain/terminology)
   - Named entities (if enabled): extracted names, companies from recent 20 turns
   - Vocabulary terms (if enabled): custom dictionary terms (up to 15)
   - Recent dialogue history (configurable N turns)
5. Transcribe each segment with context from previous segments
6. Smart truncation: limit to maxContextLength with word-boundary detection and Unicode safety
7. Update ViewModel progress in real-time

**Context Prompt System**:
The service builds intelligent context prompts for each transcription segment:
- **Base context** (`settings.baseContextPrompt`): Domain/terminology context applied to all segments (e.g., "Medical consultation transcript with technical terms")
- **Named entity extraction** (if enabled): Extracts names, companies from recent 20 turns using cached regex patterns
  - Filters stop words (common sentence starters)
  - Limited to recent turns for memory optimization and relevance
- **Vocabulary integration** (if enabled): Includes up to 15 custom terms from enabled dictionaries
  - Controlled by `ContextOptimizationConstants.maxVocabularyTermsInContext`
- **Dialogue history**: Last N turns from previous speakers (configurable via `settings.maxRecentTurns`)
- **Smart truncation**: Context limited to `settings.maxContextLength` with word-boundary detection
  - Finds last space before limit to avoid mid-word cuts
  - Unicode-safe with `limitedBy` parameter
  - Default 600 characters (~200 tokens), configurable 300-700 range
  - Whisper supports up to 224 tokens (~600-800 characters)
  - Debug logging for context composition statistics
- **Post-VAD segment merging**: Combines adjacent same-speaker segments with gaps < `settings.postVADMergeThreshold`
  - Reduces over-segmentation from natural pauses
  - Default 1.5s, configurable 0.5-3.0s range
- **Mono transcription**: Base context prompt applied directly for single-channel audio

**Performance Optimizations**:
- Static regex caching for entity extraction (compiled once at class level)
- Limited entity extraction to recent 20 turns (prevents unbounded memory growth)
- Vocabulary terms capped at 15 to preserve context budget

### 3. BatchTranscriptionService (`Sources/Services/BatchTranscriptionService.swift`)

**Responsibilities**:
- Multi-file queue management
- Parallel processing with configurable concurrency
- Batch progress tracking

**Note**: Currently not used in main UI (single file mode)

## UI Components (MVVM)

### ViewModels

**FileTranscriptionViewModel**:
- Manages transcription state (idle/processing/completed)
- Progress tracking and updates
- Current transcription data
- Audio player integration

**AudioPlayerState**:
- Grouped state management (playback, audio, settings)
- Replaces scattered `@Published` properties
- Equatable for efficient SwiftUI updates

### Views (Modular Composition)

**FileTranscriptionView** (`Sources/UI/Views/Transcription/FileTranscriptionView.swift`):
- Main transcription container
- File selection and drag-and-drop
- Settings panel integration
- Delegates business logic to ViewModel

**TimelineSyncedDialogueView** (`Sources/UI/Views/Timeline/TimelineSyncedDialogueView.swift`):
- Timeline visualization with compression
- Integrates `CompressedTimelineMapper`
- Adaptive scaling based on call duration
- Header with total duration

**TimelineDialogueView** (`Sources/UI/Views/Timeline/TimelineDialogueView.swift`):
- Two-column speaker layout (left/right channels)
- Synchronized turn display
- Click-to-play functionality
- Silence gap indicators

**AudioPlayerView** (`Sources/UI/Views/Audio/AudioPlayerView.swift`):
- Playback controls (play/pause, seek)
- Speed control (0.5x - 2.0x)
- Volume boost (100% - 500%)
- Progress bar with click-to-seek
- Mono/stereo toggle

**SettingsPanel** (`Sources/UI/Views/Transcription/SettingsPanel.swift`):
- Whisper model selection (Tiny through Large-v3)
- Language picker (Auto-detect, Russian, English)
- VAD algorithm/segmentation method picker
- Base context prompt text editor (auto-saves to UserSettings)
- **Context Optimization** section (NEW):
  - Max Context Length slider (300-700 chars) with live value display
  - Recent Turns slider (3-10 turns) with live value display
  - VAD Merge Threshold slider (0.5-3.0s) with formatted display
  - Enable Entity Extraction toggle with tooltip
  - Enable Vocabulary Integration toggle with tooltip
  - All controls use two-way SwiftUI bindings to UserSettings
- Retranscribe button for applying new settings
- Requires both `modelManager` and `userSettings` as dependencies

**View Composition Hierarchy**:
```
FileTranscriptionView
├── HeaderView (file name, status, actions)
├── SettingsPanel (model, language, VAD, base context prompt, context optimization)
├── ProgressSection (model loading, transcription progress)
└── ContentView
    ├── TranscriptionContentView
    │   ├── AudioPlayerView
    │   └── TimelineSyncedDialogueView
    │       └── TimelineDialogueView
    └── EmptyStateView
```

## Key Utilities

### 1. Timeline Compression

**CompressedTimelineMapper** (`Sources/Utils/Timeline/TimelineMapper.swift`):
```swift
public struct CompressedTimelineMapper {
    let minGapToCompress: TimeInterval = 0.5        // Min silence to compress
    let compressedGapDisplay: TimeInterval = 0.15   // Visual display duration
    let silenceGaps: [SilenceGap]

    func visualPosition(for realTime: TimeInterval) -> TimeInterval
    func totalVisualDuration(realDuration: TimeInterval) -> TimeInterval
}
```

**Algorithm**:
1. Find intervals when at least one speaker is talking
2. Merge overlapping activity intervals
3. Detect silence gaps where BOTH speakers are silent
4. Compress long gaps (>0.5s) to 0.15s visually
5. Map real time → visual time

**Example**:
```
BEFORE: [Speaker 1: 0-2s] ----silence (3s)---- [Speaker 2: 5-7s]
AFTER:  [Speaker 1: 0-2s] -0.15s- [Speaker 2: 2.15-4.15s]
```

### 2. Model Management

**ModelManager** (`Sources/Utils/ModelManager.swift`):
- Implements `ModelManagerProtocol`
- Downloads models from Hugging Face
- Manages multiple model sizes (tiny, base, small, medium, large-v2, large-v3)
- Storage management and cleanup

**Recommended Model**: `small` (~250 MB) - best balance of accuracy and performance

### 3. User Settings Management

**UserSettings** (`Sources/Utils/UserSettings.swift`):
- Implements `UserSettingsProtocol` for dependency injection
- Persists all application preferences via UserDefaults
- Uses `@Published` properties for SwiftUI reactivity
- Auto-saves changes via `didSet` observers

**Key Settings**:
- **Model & Language**: Selected Whisper model, transcription language
- **VAD Configuration**: Algorithm type, segmentation mode (VAD/Batch)
- **Base Context Prompt** (`baseContextPrompt`): Domain/terminology context for all transcriptions
  - Stored in: `com.transcribeit.baseContextPrompt`
  - Applied to both mono and stereo transcriptions
  - Combined with dialogue history in `FileTranscriptionService.buildContextPrompt()`
  - Example: "Medical consultation with technical terminology" or "Customer support call center"
- **Custom Prefill Prompt** (`customPrefillPrompt`): Additional vocabulary terms for model priming (separate from base context)
- **Dictionary Selection**: Active vocabulary dictionaries for corrections
- **Quality Enhancement**: Temperature fallback, compression ratio thresholds

**Context Optimization Settings** (NEW):
- **Max Context Length** (`maxContextLength`): 300-700 characters (default: 600)
  - Controls how much context is sent to Whisper decoder
  - Whisper supports up to 224 tokens (~600-800 characters)
  - Stored in: `com.transcribeit.maxContextLength`
- **Max Recent Turns** (`maxRecentTurns`): 3-10 turns (default: 5)
  - Number of previous dialogue turns included in context
  - Adaptive: fewer long turns or more short turns
  - Stored in: `com.transcribeit.maxRecentTurns`
- **Enable Entity Extraction** (`enableEntityExtraction`): Boolean (default: false)
  - Extracts names, companies from dialogue history
  - Adds to context prompt for better recognition
  - Stored in: `com.transcribeit.enableEntityExtraction`
- **Enable Vocabulary Integration** (`enableVocabularyIntegration`): Boolean (default: true)
  - Includes custom vocabulary terms in context
  - Uses terms from VocabularyManager
  - Stored in: `com.transcribeit.enableVocabularyIntegration`
- **Post-VAD Merge Threshold** (`postVADMergeThreshold`): 0.5-3.0 seconds (default: 1.5)
  - Merges adjacent same-speaker segments with gaps below threshold
  - Reduces over-segmentation from natural speech pauses
  - Stored in: `com.transcribeit.postVADMergeThreshold`

**Pattern**: All persisted properties follow the same structure:
```swift
@Published public var baseContextPrompt: String {
    didSet {
        defaults.set(baseContextPrompt, forKey: Keys.baseContextPrompt)
        LogManager.app.info("Base context prompt updated (\(baseContextPrompt.count) characters)")
    }
}
```

### 4. Vocabulary Management

**VocabularyManager** (`Sources/Utils/VocabularyManager.swift`):
- Implements `VocabularyManagerProtocol`
- Custom vocabulary corrections
- Regex-based replacements
- Domain-specific dictionaries

**Default Corrections**: Technical terms (git, API, JSON), brand names (Apple, Microsoft), common Russian speech mistakes

### 5. Audio Processing

**AudioPlayerManager** (`Sources/Utils/AudioPlayerManager.swift`):
- AVAudioEngine-based playback
- Waveform generation and visualization
- Frame-accurate seeking
- Speed and volume control
- Uses `AudioCache` for efficient loading

**AudioFileNormalizer**:
- Noise reduction
- Volume normalization
- Format conversion to WhisperKit-compatible format (16kHz mono Float32)

**VAD System**:
- **SpectralVAD** - Spectral energy analysis
- **AdaptiveVAD** - Adaptive threshold adjustment
- **SilenceDetector** - Silence trimming

Used for dual-channel speaker separation and segment boundary detection.

### 6. Export System

**ExportManager** (`Sources/Utils/ExportManager.swift`):

**Supported Formats**:
- **SRT** - SubRip subtitles with timestamps
- **VTT** - WebVTT subtitles
- **TXT** - Plain text with optional timestamps
- **DOCX** - Microsoft Word document
- **JSON** - Structured data with full metadata

## Testing Infrastructure

### Mock Implementations (`Tests/Mocks/`)

**MockVocabularyManager**:
```swift
public final class MockVocabularyManager: VocabularyManagerProtocol {
    // Call tracking
    public var correctTranscriptionCallCount = 0
    public var correctTranscriptionCalls: [String] = []

    // Stubbed return values
    public var stubbedCorrections: [String: String] = [:]

    // Error simulation
    public var shouldThrowOnLoad = false

    public func reset()
}
```

**MockUserSettings** - Configurable settings for testing
**MockModelManager** - Model state simulation

### Test Structure

```
Tests/
├── Utils/Timeline/TimelineMapperTests.swift
├── Utils/VAD/SpectralVADTests.swift
├── UI/ViewModels/FileTranscriptionViewModelTests.swift
└── Fixtures/audio/  # Test audio files
```

**Running Tests**:
```bash
swift test                    # Run all tests
swift test --parallel        # Parallel execution
```

## Configuration & Constants

All magic numbers extracted to dedicated constant files:
- `TimelineConstants.swift` - Timeline compression, scaling, synchronization
- `TurnCardConstants.swift` - Card styling, padding, colors
- `SilenceIndicatorConstants.swift` - Silence gap visualization
- `TranscriptionViewConstants.swift` - UI layout constants
- `AudioNormalizerConstants.swift` - Audio processing parameters

**Example**:
```swift
enum TimelineConstants {
    enum Compression {
        static let minSilenceGapToCompress: TimeInterval = 0.5
        static let compressedGapDisplayDuration: TimeInterval = 0.15
    }
    enum Scaling {
        static let maxTimelineHeight: CGFloat = 600
        static let defaultPixelsPerSecond: CGFloat = 50
    }
}
```

## Building & Running

### Development Build
```bash
swift build                  # Debug build
.build/debug/TranscribeIt    # Run executable
```

### Release Build
```bash
swift build -c release
```

### Build .app Bundle
```bash
./build_app.sh              # Creates signed .app with entitlements
```

### Testing
```bash
swift test                  # Run all tests
swift test --filter Timeline  # Run specific tests
```

## System Logging

**LogManager** (`Sources/Utils/LogManager.swift`):
- Uses Apple's OSLog framework
- Subsystem: `com.transcribeit.app`
- Categories: `app`, `file`, `batch`, `transcription`, `export`, `audio`

**Viewing Logs**:
```bash
# Real-time monitoring
log stream --predicate 'subsystem == "com.transcribeit.app"' --level debug

# Filter by category
log stream --predicate 'subsystem == "com.transcribeit.app" && category == "transcription"'

# Show last hour
log show --predicate 'subsystem == "com.transcribeit.app"' --last 1h

# Only errors
log stream --predicate 'subsystem == "com.transcribeit.app" && eventType >= logEventType.error'
```

## Common Issues & Solutions

### Model Loading Fails

**Symptoms**: `WhisperError.modelLoadFailed`

**Solutions**:
1. Check internet connection (models from Hugging Face)
2. Verify Metal GPU: `log stream --predicate 'category == "transcription"'`
3. Clear cache: `~/Library/Caches/whisperkit_models/`
4. Try smaller model first (tiny or base)

### Transcription Quality Issues

**Solutions**:
1. Use larger model (small or medium recommended)
2. Enable audio normalization in settings
3. Add custom vocabulary for domain terms
4. Check audio quality (16kHz+ sample rate)
5. For stereo, ensure distinct speakers in left/right channels

### Audio Cache Issues

**Symptoms**: High memory usage

**Check cache statistics**:
```swift
let stats = await audioCache.getStatistics()
print("Cache: \(stats.hitRate)% hit rate, \(stats.currentSize) bytes")
```

**Solutions**:
1. Cache auto-evicts after 5 minutes
2. Max 3 files cached (500 MB limit)
3. Manually clear: `await audioCache.clearCache()`

### Export Fails

**Symptoms**: `TranscriptionError.exportFailed`

**Solutions**:
1. Check write permissions for export directory
2. Verify disk space (especially for DOCX)
3. Check logs: `log stream --predicate 'category == "export"'`

### Timeline Visualization Issues

**Symptoms**: Compressed timeline looks incorrect

**Debug**:
```swift
let mapper = CompressedTimelineMapper(turns: dialogue.turns)
print("Silence gaps detected: \(mapper.silenceGaps.count)")
print("Visual duration: \(mapper.totalVisualDuration(realDuration: duration))")
```

## Design Principles

1. **MVVM Architecture** - Clear separation of business logic and UI
2. **Protocol-Oriented Design** - Testability with protocol abstractions
3. **Dependency Injection** - Service Locator pattern for flexible dependencies
4. **Typed Errors** - Strongly-typed, localized error handling
5. **Actor-Based Concurrency** - Thread-safe audio caching
6. **Composition over Inheritance** - Modular, reusable views
7. **Single Responsibility** - Each file/class has one clear purpose
8. **Constants Extraction** - No magic numbers in code
9. **On-Device Processing** - Privacy-focused, no cloud dependencies
10. **Performance Monitoring** - RTF tracking, cache statistics

## Key Code References

- Dependency injection: `Sources/DI/DependencyContainer.swift`
- File transcription: `Sources/Services/FileTranscriptionService.swift`
  - Context optimization constants: `ContextOptimizationConstants` enum (lines 290-296)
  - Static regex caching: `entityExtractionRegex` (lines 300-305)
  - Context prompt building: `buildContextPrompt()` method (lines 971-1053)
  - Named entity extraction: `extractNamedEntities()` method (lines 931-967)
  - Post-VAD segment merging: `mergeAdjacentSegments()` method (lines 723-760)
- WhisperKit integration: `Sources/Services/WhisperService.swift`
  - Context tokenization: `transcribe(audioSamples:contextPrompt:)` method
- MVVM ViewModel: `Sources/UI/ViewModels/FileTranscriptionViewModel.swift`
- Settings UI: `Sources/UI/Views/Transcription/SettingsPanel.swift` lines 118-179
  - Context Optimization section with 5 controls (sliders and toggles)
- User preferences: `Sources/Utils/UserSettings.swift` lines 383-420
  - 5 context optimization properties with UserDefaults persistence
  - `maxContextLength`, `maxRecentTurns`, `enableEntityExtraction`, `enableVocabularyIntegration`, `postVADMergeThreshold`
- Timeline compression: `Sources/Utils/Timeline/TimelineMapper.swift`
- Audio caching: `Sources/Utils/Audio/AudioCache.swift`
- Typed errors: `Sources/Errors/TranscriptionError.swift`
- Protocol abstractions: `Sources/Protocols/UserSettingsProtocol.swift`
  - Context optimization protocol requirements
- Mock implementations: `Tests/Mocks/MockUserSettings.swift`
  - All context optimization test properties
- Audio player: `Sources/Utils/AudioPlayerManager.swift`
- Model management: `Sources/Utils/ModelManager.swift`

## Future Enhancements

1. **Complete Test Coverage** - Reach >60% for core logic
2. **Integration Tests** - End-to-end transcription workflows
3. **Performance Benchmarks** - AudioCache and VAD performance tests
4. **SwiftUI Previews** - Preview providers for all views
5. **Actor-Based Services** - Convert services to actors for better concurrency
6. **Localization** - Support multiple languages beyond Russian
