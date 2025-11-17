---
name: m-implement-context-optimization-long-calls
branch: feature/m-implement-context-optimization-long-calls
status: pending
created: 2025-11-17
---

# Optimize Context Building for Long Phone Calls

## Problem/Goal

Current context prompt system in `FileTranscriptionService` has limitations for long telephone conversations (>10 minutes):

1. **Limited context size**: Only 300 characters (≈75 tokens), while Whisper supports up to 224 tokens (≈600-800 characters)
2. **Fixed recent turns**: Always takes last 5 turns regardless of their length or relevance
3. **No entity extraction**: Missing names, companies, and technical terms mentioned earlier in conversation
4. **Character-based truncation**: Cuts context mid-word instead of smart boundary detection
5. **Static base context**: Doesn't adapt to conversation topics

This causes quality degradation in long calls where:
- Proper names get mis-recognized repeatedly
- Domain terminology is forgotten between segments
- Important context from earlier conversation is lost

**Goal**: Implement smart context building that maximizes Whisper's 224-token context window for improved transcription quality in long phone calls.

## Success Criteria

**Core Context Optimizations:**
- [ ] Context prompt expanded from 300 to 600-700 characters (≈200 tokens)
- [ ] Smart truncation by word boundaries instead of character count
- [ ] Adaptive turn selection: 3-10 recent turns based on content length
- [ ] Named entity extraction (names, companies) from conversation history
- [ ] Vocabulary terms integration into context prompt
- [ ] Post-VAD segment merging for gaps <1.5 seconds
- [ ] Adaptive Whisper parameters: temperature, beam search, quality thresholds

**A/B Testing & Multi-Window Support:**
- [ ] User-configurable context parameters in SettingsPanel:
  - [ ] Max context length slider (300-700 characters)
  - [ ] Max recent turns slider (3-10 turns)
  - [ ] Enable/disable named entity extraction toggle
  - [ ] Enable/disable vocabulary integration toggle
  - [ ] Post-VAD merge threshold slider (0.5-3.0 seconds)
- [ ] Multi-window transcription mode:
  - [ ] New transcription window created each time file is selected
  - [ ] Each window maintains independent settings snapshot
  - [ ] Side-by-side comparison of transcription results
  - [ ] Window title shows settings used (e.g., "call.mp3 - Context:700ch, Turns:8")
- [ ] Comparison UI elements:
  - [ ] Diff highlighting between transcription windows
  - [ ] Quality metrics per window (RTF, segment count, errors)
  - [ ] Export comparison report (settings + results)

**Technical Requirements:**
- [ ] All changes maintain backward compatibility with existing tests
- [ ] Performance impact: <5% RTF increase, context building <100ms per segment
- [ ] Settings changes trigger re-transcription warning (avoid accidental overwrites)
- [ ] Multi-window state persistence (windows survive app restart)

## Context Manifest
<!-- Added by context-gathering agent -->

### How the Current Context System Works

**Entry Point: FileTranscriptionService.transcribeSegmentsInOrder()**

When a stereo phone call is transcribed, the system processes speech segments in chronological order. For each segment (a single speaker's utterance), the service builds a context prompt to help Whisper understand what's being discussed.

The flow starts at **FileTranscriptionService.swift lines 777-837** (`transcribeSegmentsInOrder()`). For each segment:

1. **Segment Selection** (line 792-798): Loops through all `ChannelSegment` objects (which contain audio samples, speaker ID, and timestamps)
2. **Silence Filtering** (line 801-803): Skips segments containing only silence using `SilenceDetector`
3. **Context Building** (line 806): Calls `buildContextPrompt(from: turns, maxTurns: 5)`
4. **Transcription with Context** (line 812-815): Passes the context to WhisperService

**Context Building Logic: FileTranscriptionService.buildContextPrompt() (lines 841-873)**

This is the CORE function that needs optimization. Current implementation:

```swift
private func buildContextPrompt(from turns: [DialogueTranscription.Turn], maxTurns: Int = 5) -> String {
    var contextParts: [String] = []

    // 1. Base context prompt (domain/terminology)
    let baseContextPrompt = self.userSettings.baseContextPrompt
    if !baseContextPrompt.isEmpty {
        contextParts.append(baseContextPrompt)
    }

    // 2. Recent dialogue history (last N turns)
    let recentTurns = Array(turns.suffix(maxTurns))
    if !recentTurns.isEmpty {
        let dialogueContext = recentTurns.map { turn in
            let speakerName = turn.speaker == .left ? "Speaker 1" : "Speaker 2"
            return "\(speakerName): \(turn.text)"
        }.joined(separator: " ")
        contextParts.append(dialogueContext)
    }

    // 3. Truncation (PROBLEM: cuts at character 300, mid-word)
    let fullContext = contextParts.joined(separator: ". ")
    let maxLength = 300  // HARDCODED LIMIT
    if fullContext.count > maxLength {
        let endIndex = fullContext.index(fullContext.startIndex, offsetBy: maxLength)
        return String(fullContext[..<endIndex]) + "..."  // BAD: cuts mid-word
    }

    return fullContext
}
```

**Key Limitations:**
- **Fixed 300 character limit** (line 866): Whisper supports up to 224 tokens (~600-800 chars), so we're only using ~40% of available context
- **Fixed 5 turns** (line 851): Doesn't adapt to turn length (5 short turns vs 5 long turns very different)
- **Character-based truncation** (line 868): Cuts mid-word instead of at word boundaries
- **No entity extraction**: Names mentioned 20 turns ago are forgotten
- **No vocabulary integration**: Custom terms from VocabularyManager not used

### How Context Reaches WhisperKit

**WhisperService.transcribe() (lines 338-354)**

When `FileTranscriptionService` calls `whisperService.transcribe(audioSamples: segmentAudio, contextPrompt: contextPrompt)`, this happens:

```swift
public func transcribe(audioSamples: [Float], contextPrompt: String? = nil) async throws -> String {
    // 1. Tokenize context prompt using WhisperKit's built-in tokenizer
    var promptTokens: [Int]? = nil
    if let context = contextPrompt, !context.isEmpty {
        if let tokenizer = whisperKit?.tokenizer {
            promptTokens = tokenizer.encode(text: context)  // line 343
            LogManager.transcription.debug("Tokenized context: \(promptTokens?.count ?? 0) tokens")
        }
    }

    // 2. Pass to internal transcription
    let result = try await transcribeInternal(audioSamples: audioSamples, promptTokens: promptTokens)
    return result
}
```

**WhisperService.transcribeInternal() (lines 361-498)**

The tokenized context is passed to WhisperKit's `DecodingOptions`:

```swift
let options = DecodingOptions(
    task: .transcribe,
    language: settings.transcriptionLanguage,
    temperature: 0.0,
    temperatureIncrementOnFallback: useQualityMode && settings.useTemperatureFallback ? 0.2 : 0.0,
    topK: useQualityMode ? 5 : 1,
    usePrefillPrompt: usePrefill,
    usePrefillCache: usePrefill,
    detectLanguage: false,
    promptTokens: promptTokens,  // ← CONTEXT INJECTED HERE (line 414)
    compressionRatioThreshold: useQualityMode ? settings.compressionRatioThreshold : nil,
    logProbThreshold: useQualityMode ? settings.logProbThreshold : nil,
    noSpeechThreshold: useQualityMode ? 0.6 : nil
)

let results = try await whisperKit.transcribe(
    audioArray: processedSamples,
    decodeOptions: options
)
```

**Important:** WhisperKit's `DecodingOptions.promptTokens` expects an `[Int]?` (tokenized array), NOT a string. The tokenization MUST happen before passing to WhisperKit. The current system correctly does this at **WhisperService.swift line 343**.

### User Settings System: Where Context Parameters Live

**UserSettings.swift** - The single source of truth for all application preferences. Uses `@Published` properties with `didSet` observers for automatic UserDefaults persistence.

**Current Context-Related Settings:**

```swift
// Line 36: Base context prompt (domain/terminology for all segments)
@Published public var baseContextPrompt: String {
    didSet {
        defaults.set(baseContextPrompt, forKey: Keys.baseContextPrompt)
        LogManager.app.info("Base context prompt updated (\(baseContextPrompt.count) characters)")
    }
}

// Line 335: Selected dictionaries for vocabulary
@Published public var selectedDictionaryIds: [String] {
    didSet {
        defaults.set(selectedDictionaryIds, forKey: Keys.selectedDictionaryIds)
    }
}

// Line 342: Custom prefill prompt (separate from context)
@Published public var customPrefillPrompt: String {
    didSet {
        defaults.set(customPrefillPrompt, forKey: Keys.customPrefillPrompt)
    }
}
```

**Where to Add New Settings:**

Add these properties to `UserSettings.swift` around line 356 (after `baseContextPrompt`):

```swift
// New context optimization settings
private enum ContextKeys {
    static let maxContextLength = "com.transcribeit.maxContextLength"
    static let maxRecentTurns = "com.transcribeit.maxRecentTurns"
    static let enableEntityExtraction = "com.transcribeit.enableEntityExtraction"
    static let enableVocabularyIntegration = "com.transcribeit.enableVocabularyIntegration"
    static let postVADMergeThreshold = "com.transcribeit.postVADMergeThreshold"
}

@Published public var maxContextLength: Int {
    didSet {
        defaults.set(maxContextLength, forKey: ContextKeys.maxContextLength)
    }
}
// ... etc
```

**UserSettingsProtocol.swift** must also be updated (lines 88-92) to include these properties in the protocol definition for dependency injection.

### Settings UI: Where Users Configure Context

**SettingsPanel.swift (lines 99-117)** - Current base context prompt UI:

```swift
VStack(alignment: .leading, spacing: Constants.labelVerticalSpacing) {
    Text("Base Context Prompt")
        .font(.system(size: Constants.labelFontSize, weight: .medium))

    Text("Base context prompt used for all transcriptions...")
        .font(.system(size: Constants.descriptionFontSize))

    TextEditor(text: Binding(
        get: { userSettings.baseContextPrompt },
        set: { userSettings.baseContextPrompt = $0 }
    ))
    .font(.system(size: 12, design: .monospaced))
    .frame(height: 60)
    .border(Color.secondary.opacity(0.2))
}
```

**Where to Add New Controls:**

Insert new section AFTER the base context prompt section (after line 117), BEFORE the "Retranscribe" button (before line 118):

```swift
// Context Optimization Settings
VStack(alignment: .leading, spacing: Constants.labelVerticalSpacing) {
    Text("Context Optimization")
        .font(.system(size: Constants.labelFontSize, weight: .medium))

    // Max context length slider
    HStack {
        Text("Max Context Length: \(userSettings.maxContextLength) chars")
        Slider(value: Binding(
            get: { Double(userSettings.maxContextLength) },
            set: { userSettings.maxContextLength = Int($0) }
        ), in: 300...700, step: 50)
    }

    // Max recent turns slider
    HStack {
        Text("Recent Turns: \(userSettings.maxRecentTurns)")
        Slider(value: Binding(
            get: { Double(userSettings.maxRecentTurns) },
            set: { userSettings.maxRecentTurns = Int($0) }
        ), in: 3...10, step: 1)
    }

    // Toggles for entity extraction and vocabulary
    Toggle("Extract Named Entities", isOn: $userSettings.enableEntityExtraction)
    Toggle("Include Vocabulary Terms", isOn: $userSettings.enableVocabularyIntegration)

    // Post-VAD merge threshold
    HStack {
        Text("VAD Merge Threshold: \(String(format: "%.1f", userSettings.postVADMergeThreshold))s")
        Slider(value: $userSettings.postVADMergeThreshold, in: 0.5...3.0, step: 0.1)
    }
}
```

**Important:** `SettingsPanel` requires both `modelManager` and `userSettings` as `@ObservedObject` dependencies (lines 10-11). Changes to `userSettings` automatically trigger SwiftUI updates.

### Multi-Window Architecture: How to Support A/B Testing

**Current Single-Window System:**

**AppDelegate.swift (lines 211-244)** creates ONE `MainWindow`:

```swift
private func openMainWindow() {
    let window = MainWindow(audioCache: dependencies.audioCache)

    window.onStartTranscription = { [weak self, weak window] files in
        guard let self = self, let window = window else { return }
        self.performTranscription(files: files, window: window)
    }

    window.onClose = { [weak self] _ in
        self?.mainWindow = nil
        NSApp.terminate(nil)  // ← CLOSES ENTIRE APP
    }

    self.mainWindow = window  // ← SINGLE WINDOW REFERENCE
    window.makeKeyAndOrderFront(nil)
}
```

**MainWindow.swift (lines 32-87)** is an `NSWindow` subclass with ONE `FileTranscriptionViewModel`:

```swift
public class MainWindow: NSWindow, NSWindowDelegate {
    public var viewModel: FileTranscriptionViewModel  // ← SINGLE VIEWMODEL

    public init(contentRect: NSRect, styleMask: ..., audioCache: AudioCache) {
        self.viewModel = FileTranscriptionViewModel(audioCache: audioCache)
        super.init(contentRect: contentRect, ...)

        let swiftUIView = FileTranscriptionView(viewModel: viewModel, ...)
        let hosting = NSHostingController(rootView: swiftUIView)
        self.contentView = hosting.view
    }
}
```

**Problem:** Each new file selection REPLACES the current transcription. Cannot compare side-by-side.

**Solution: Window Manager Pattern**

Create `TranscriptionWindowManager.swift` to manage multiple windows:

```swift
class TranscriptionWindowManager {
    private var windows: [UUID: MainWindow] = [:]
    private let dependencies: DependencyContainer

    func createWindow(for fileURL: URL, settingsSnapshot: TranscriptionSettings) -> MainWindow {
        let windowID = UUID()
        let window = MainWindow(audioCache: dependencies.audioCache)

        // Generate window title with settings
        window.title = "\(fileURL.lastPathComponent) - Ctx:\(settingsSnapshot.maxContextLength)ch/T:\(settingsSnapshot.maxRecentTurns)/E:\(settingsSnapshot.enableEntityExtraction ? "on" : "off")"

        // Store settings snapshot in window
        window.settingsSnapshot = settingsSnapshot

        // Don't close app when window closes
        window.onClose = { [weak self] closedWindow in
            self?.windows.removeValue(forKey: windowID)
            // Don't terminate app unless all windows closed
        }

        windows[windowID] = window
        return window
    }
}
```

**Integration with AppDelegate:**

Replace single `mainWindow` property with `windowManager`:

```swift
private var windowManager: TranscriptionWindowManager?

func applicationDidFinishLaunching(_ notification: Notification) {
    windowManager = TranscriptionWindowManager(dependencies: dependencies)
}

// When user selects file:
func openTranscriptionForFile(_ url: URL) {
    let settingsSnapshot = TranscriptionSettings.capture(from: dependencies.userSettings)
    let window = windowManager.createWindow(for: url, settingsSnapshot: settingsSnapshot)
    window.makeKeyAndOrderFront(nil)
    startTranscription(in: window, file: url)
}
```

**Settings Snapshot Pattern:**

```swift
struct TranscriptionSettings {
    let maxContextLength: Int
    let maxRecentTurns: Int
    let enableEntityExtraction: Bool
    let enableVocabularyIntegration: Bool
    let postVADMergeThreshold: TimeInterval
    let modelSize: String
    let vadAlgorithm: String

    static func capture(from userSettings: UserSettingsProtocol) -> TranscriptionSettings {
        return TranscriptionSettings(
            maxContextLength: userSettings.maxContextLength,
            maxRecentTurns: userSettings.maxRecentTurns,
            // ... capture all settings
        )
    }
}
```

### VAD Segmentation: Post-VAD Merge Logic

**Current VAD Implementation:**

**SpectralVAD.swift (lines 94-172)** - Detects speech segments using FFT analysis:

```swift
public func detectSpeechSegments(in samples: [Float]) -> [SpeechSegment] {
    // 1. Slide FFT window across audio (line 106)
    var position = 0
    while position + parameters.fftSize <= samples.count {
        let window = Array(samples[position..<(position + parameters.fftSize)])

        // 2. Calculate speech energy in frequency range (300-3400 Hz for telephone)
        let (speechEnergy, totalEnergy) = calculateSpeechEnergy(windowedSamples, fftSetup: fftSetup)

        position += hopSize
    }

    // 3. Adaptive threshold calculation (line 121)
    let threshold = calculateAdaptiveThreshold(metrics: metrics)

    // 4. Segment detection with silence gaps (lines 130-158)
    for metric in metrics {
        let isSpeech = energyRatio >= threshold

        if isSpeech {
            if currentSegmentStart == nil {
                currentSegmentStart = metric.time
            }
        } else {
            if let start = currentSegmentStart {
                let silenceDuration = metric.time - lastSpeechTime

                // Only split if silence >= minSilenceDuration (0.5s for telephone)
                if silenceDuration >= parameters.minSilenceDuration {
                    segments.append(segment)
                    currentSegmentStart = nil
                }
            }
        }
    }
}
```

**VAD Parameters (lines 39-47)** - Telephone preset:

```swift
public static let telephone = Parameters(
    fftSize: 512,
    minSpeechDuration: 0.3,      // Min segment length
    minSilenceDuration: 0.5,     // Min gap to split segments  ← CURRENT SPLIT THRESHOLD
    speechFreqMin: 300,
    speechFreqMax: 3400,
    speechEnergyRatio: 0.25
)
```

**Problem:** VAD splits on ANY silence >= 0.5s. In natural speech, people pause mid-sentence. This creates many short segments (e.g., "Hello..." [0.6s pause] "...how are you?" becomes 2 segments instead of 1).

**Where Segments Are Used:**

**FileTranscriptionService.detectAndMergeStereoSegments() (lines 731-775)** combines left and right channel segments, but doesn't merge adjacent same-speaker segments:

```swift
// Add left channel segments
for segment in leftSegments {
    allSegments.append(ChannelSegment(
        segment: segment,
        channel: 0,
        speaker: .left,
        audioSamples: extractSegmentAudio(segment, from: left)
    ))
}

// Add right channel segments
for segment in rightSegments {
    allSegments.append(ChannelSegment(..., speaker: .right, ...))
}

// Sort by time
allSegments.sort(by: { $0.segment.startTime < $1.segment.startTime })
```

**Solution: Post-VAD Merge Function**

Insert AFTER line 773 (after sorting), BEFORE returning:

```swift
// Post-VAD merge: combine adjacent same-speaker segments with gap < threshold
allSegments = mergeAdjacentSegments(allSegments, maxGap: userSettings.postVADMergeThreshold)

private func mergeAdjacentSegments(_ segments: [ChannelSegment], maxGap: TimeInterval) -> [ChannelSegment] {
    guard segments.count > 1 else { return segments }

    var merged: [ChannelSegment] = []
    var currentSegment = segments[0]

    for i in 1..<segments.count {
        let nextSegment = segments[i]

        // Check if same speaker and gap small enough
        let gap = nextSegment.segment.startTime - currentSegment.segment.endTime
        if currentSegment.speaker == nextSegment.speaker && gap < maxGap {
            // Merge: extend current segment to include next segment
            let mergedAudio = currentSegment.audioSamples + nextSegment.audioSamples
            currentSegment = ChannelSegment(
                segment: SpeechSegment(
                    startTime: currentSegment.segment.startTime,
                    endTime: nextSegment.segment.endTime
                ),
                channel: currentSegment.channel,
                speaker: currentSegment.speaker,
                audioSamples: mergedAudio
            )
        } else {
            // Different speaker or gap too large - finalize current segment
            merged.append(currentSegment)
            currentSegment = nextSegment
        }
    }
    merged.append(currentSegment)  // Don't forget last segment

    LogManager.app.info("Post-VAD merge: \(segments.count) → \(merged.count) segments")
    return merged
}
```

### Testing Infrastructure: Patterns to Follow

**MockUserSettings.swift** - Test mock pattern:

```swift
public final class MockUserSettings: UserSettingsProtocol {
    // Call tracking for verification
    public var buildFullPrefillPromptCallCount = 0

    // Properties with default values
    public var baseContextPrompt: String = ""
    public var maxContextLength: Int = 300  // ← ADD NEW PROPERTIES HERE
    public var maxRecentTurns: Int = 5

    public func reset() {
        baseContextPrompt = ""
        maxContextLength = 300
        buildFullPrefillPromptCallCount = 0
    }
}
```

**Test File Pattern (FileTranscriptionViewModelTests.swift):**

```swift
@testable import TranscribeItCore

final class FileTranscriptionViewModelTests: XCTestCase {
    var viewModel: FileTranscriptionViewModel!
    var mockSettings: MockUserSettings!

    override func setUp() {
        super.setUp()
        mockSettings = MockUserSettings()
        viewModel = FileTranscriptionViewModel(audioCache: AudioCache())
    }

    override func tearDown() {
        viewModel = nil
        mockSettings = nil
        super.tearDown()
    }

    func testContextBuildingWithCustomLength() {
        // Arrange
        mockSettings.maxContextLength = 500
        mockSettings.maxRecentTurns = 8

        // Act
        // ... test logic

        // Assert
        XCTAssertEqual(mockSettings.buildFullPrefillPromptCallCount, 1)
    }
}
```

**Test Requirements for This Task:**

1. **Context building tests** (add to new file `Tests/Services/FileTranscriptionServiceTests.swift`):
   - Test 300 vs 700 character limits
   - Test word boundary truncation
   - Test entity extraction
   - Test vocabulary integration

2. **Settings persistence tests** (add to new file `Tests/Utils/UserSettingsTests.swift`):
   - Verify all new settings save to UserDefaults
   - Verify settings survive app restart

3. **Post-VAD merge tests** (add to existing `Tests/Utils/VAD/VADIntegrationTests.swift`):
   - Test merging adjacent same-speaker segments
   - Test threshold behavior (0.5s vs 3.0s)
   - Verify different speakers NOT merged

### Technical Reference Details

#### Key File Locations

**Context Building:**
- `Sources/Services/FileTranscriptionService.swift` lines 841-873 (buildContextPrompt)
- `Sources/Services/FileTranscriptionService.swift` lines 777-837 (transcribeSegmentsInOrder)

**WhisperKit Integration:**
- `Sources/Services/WhisperService.swift` lines 338-354 (transcribe with context)
- `Sources/Services/WhisperService.swift` lines 361-498 (transcribeInternal with DecodingOptions)

**User Settings:**
- `Sources/Utils/UserSettings.swift` lines 18-531 (main implementation)
- `Sources/Protocols/UserSettingsProtocol.swift` lines 1-112 (protocol definition)
- `Tests/Mocks/MockUserSettings.swift` lines 1-195 (test mock)

**Settings UI:**
- `Sources/UI/Views/Transcription/SettingsPanel.swift` lines 1-144

**Window Management:**
- `Sources/App/AppDelegate.swift` lines 211-244 (openMainWindow)
- `Sources/UI/MainWindow.swift` lines 32-124 (NSWindow subclass)
- `Sources/UI/ViewModels/FileTranscriptionViewModel.swift` lines 1-134

**VAD Segmentation:**
- `Sources/Utils/SpectralVAD.swift` lines 94-272 (segment detection)
- `Sources/Services/FileTranscriptionService.swift` lines 731-775 (detectAndMergeStereoSegments)
- `Sources/Utils/VoiceActivityDetector.swift` lines 56-82 (SpeechSegment struct)

#### Data Structures

**SpeechSegment** (VoiceActivityDetector.swift lines 56-82):
```swift
public struct SpeechSegment {
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public var duration: TimeInterval { endTime - startTime }
    public var startSample: Int { Int(startTime * 16000) }
    public var endSample: Int { Int(endTime * 16000) }
}
```

**DialogueTranscription.Turn** (FileTranscriptionService.swift lines 7-43):
```swift
public struct Turn: Identifiable {
    public let id = UUID()
    public let speaker: Speaker  // .left or .right
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public var duration: TimeInterval { endTime - startTime }
}
```

**ChannelSegment** (FileTranscriptionService.swift lines 668-674):
```swift
private struct ChannelSegment {
    let segment: SpeechSegment
    let channel: Int  // 0 = left, 1 = right
    let speaker: DialogueTranscription.Turn.Speaker
    let audioSamples: [Float]
}
```

#### WhisperKit DecodingOptions

Used in WhisperService.swift line 404-418:

```swift
let options = DecodingOptions(
    task: .transcribe,
    language: settings.transcriptionLanguage,  // "ru", "en", or ""
    temperature: 0.0,
    temperatureIncrementOnFallback: 0.2,  // if quality mode enabled
    temperatureFallbackCount: 5,
    topK: 5,  // beam search width (1 = greedy)
    usePrefillPrompt: true,
    usePrefillCache: true,
    detectLanguage: false,
    promptTokens: [Int]?,  // ← TOKENIZED CONTEXT (max 224 tokens)
    compressionRatioThreshold: 2.4,
    logProbThreshold: -1.0,
    noSpeechThreshold: 0.6
)
```

**Important:** `promptTokens` must be tokenized using `whisperKit.tokenizer.encode(text: contextPrompt)` BEFORE passing to DecodingOptions.

#### Configuration Requirements

**UserDefaults Keys** (add to UserSettings.Keys enum):
```swift
private enum Keys {
    static let maxContextLength = "com.transcribeit.maxContextLength"
    static let maxRecentTurns = "com.transcribeit.maxRecentTurns"
    static let enableEntityExtraction = "com.transcribeit.enableEntityExtraction"
    static let enableVocabularyIntegration = "com.transcribeit.enableVocabularyIntegration"
    static let postVADMergeThreshold = "com.transcribeit.postVADMergeThreshold"
}
```

**Default Values:**
- `maxContextLength`: 600 characters (start conservative, allow up to 700)
- `maxRecentTurns`: 5 (current behavior, allow 3-10)
- `enableEntityExtraction`: false (opt-in feature)
- `enableVocabularyIntegration`: true (helpful by default)
- `postVADMergeThreshold`: 1.5 seconds (balance between over-splitting and over-merging)

#### Performance Requirements

- Context building must complete in <100ms per segment (measured at line 809 in FileTranscriptionService)
- Total RTF (Real-Time Factor) increase <5% (measured in WhisperService.transcribeInternal)
- Post-VAD merge should complete in <50ms for typical call (measure before/after segment count)

### Implementation Strategy Notes

**Phase 1: Core Context Optimization** (can be done independently)
1. Add new properties to UserSettings, UserSettingsProtocol, MockUserSettings
2. Modify `buildContextPrompt()` to use new parameters
3. Implement smart word-boundary truncation
4. Add entity extraction helper
5. Integrate vocabulary terms from VocabularyManager

**Phase 2: Settings UI** (depends on Phase 1)
1. Add sliders and toggles to SettingsPanel
2. Wire up Bindings to UserSettings properties
3. Test auto-save behavior

**Phase 3: Post-VAD Merge** (independent of Phases 1-2)
1. Implement `mergeAdjacentSegments()` function
2. Add call in `detectAndMergeStereoSegments()`
3. Add logging for before/after segment count

**Phase 4: Multi-Window Support** (most complex, do last)
1. Create TranscriptionWindowManager class
2. Create TranscriptionSettings snapshot struct
3. Modify AppDelegate to use window manager
4. Update MainWindow.onClose to not terminate app
5. Add window title generation with settings display

**Phase 5: Testing** (throughout)
- Write tests BEFORE implementing features (TDD)
- Run tests after each phase
- Add integration tests for full workflow

## User Notes

### A/B Testing Workflow

**Scenario**: Testing different context settings on same audio file

1. **Open first transcription:**
   - Select audio file → Window 1 opens
   - Configure settings: Context=300ch, Turns=5, Entity extraction=OFF
   - Start transcription → Window shows "call.mp3 - Ctx:300ch/T:5/E:off"

2. **Open second transcription (same file):**
   - Select same audio file → Window 2 opens (parallel to Window 1)
   - Configure different settings: Context=700ch, Turns=10, Entity extraction=ON
   - Start transcription → Window shows "call.mp3 - Ctx:700ch/T:10/E:on"

3. **Compare results:**
   - Both windows visible side-by-side
   - Diff highlighting shows text differences
   - Metrics panel: RTF, accuracy indicators, segment count
   - Export comparison report for analysis

### Multi-Window Architecture

**Key Design Decisions:**
- Each window = independent `FileTranscriptionViewModel` instance
- Settings snapshot captured at transcription start (immutable per window)
- Windows identified by: `fileURL + settingsHash + timestamp`
- Window manager tracks all open transcriptions
- NSWindow subclass: `TranscriptionComparisonWindow`

### Settings Panel Additions

**New Controls (SettingsPanel.swift):**

```
┌─ Context Optimization Settings ─────────┐
│                                          │
│ Max Context Length: [====●====] 700 ch  │
│                     300        700       │
│                                          │
│ Recent Turns Count: [==●======] 8 turns │
│                     3          10        │
│                                          │
│ ☑ Extract named entities                │
│ ☑ Include vocabulary terms              │
│                                          │
│ VAD Merge Threshold: [===●===] 1.5 sec  │
│                      0.5       3.0       │
│                                          │
│ [Reset to Defaults]  [Apply]            │
└──────────────────────────────────────────┘
```

**Behavior:**
- Changes don't apply to active transcriptions
- "Retranscribe" button shows warning: "Settings changed. Current window will keep old settings. New window will use new settings."
- Presets dropdown: "Quality Mode", "Speed Mode", "Balanced" (quick apply common configs)

## Work Log
<!-- Updated as work progresses -->
- [YYYY-MM-DD] Started task, initial research
