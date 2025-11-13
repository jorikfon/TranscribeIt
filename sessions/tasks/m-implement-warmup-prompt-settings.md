---
name: m-implement-warmup-prompt-settings
branch: feature/m-implement-warmup-prompt-settings
status: pending
created: 2025-11-13
---

# Implement Warmup Prompt Settings

## Problem/Goal
Add a settings field for a warmup prompt that will be used to pre-warm the Whisper model before transcription. This should appear in the SettingsPanel near the language and VAD options, with a textarea that auto-saves user input.

## Success Criteria
- [ ] `UserSettings` has a new persisted field for warmup prompt text
- [ ] `SettingsPanel` UI displays a textarea for warmup prompt input with appropriate label
- [ ] Textarea auto-saves changes to UserSettings (using `@AppStorage` or similar)
- [ ] Warmup prompt is integrated into the transcription workflow (passed to WhisperService)
- [ ] UI is positioned logically near language/VAD settings with consistent styling

## Context Manifest

### How Model Warmup and Prefill Currently Work

When WhisperKit loads a model, it supports a "prewarm" option that pre-warms the model for faster first-time execution. This is currently set to `true` in `WhisperService.loadModel()` (line 192). However, this is just model initialization - it's separate from the "prefill prompt" concept.

The **prefill prompt** is a different mechanism used during transcription to provide context to the model. Currently, the application already has a sophisticated prefill system that combines:

1. **Predefined vocabulary dictionaries** - Technical terms from categories like "PHP Development", "IP Telephony", "Cloud & DevOps", etc.
2. **Custom prefill prompt** - User-entered text for additional terms

The flow works like this:

**When transcription happens** (`WhisperService.transcribe()` or `transcribeChunk()`):
- Line 277 and 397: `let prefillPrompt = settings.buildFullPrefillPrompt()`
- This calls `UserSettings.buildFullPrefillPrompt()` (line 357-362)
- Which delegates to `VocabularyDictionariesManager.buildPrefillPrompt()` (line 184-203)
- The manager combines:
  - Custom prompt text from `userSettings.customPrefillPrompt` (if not empty)
  - Up to 100 terms from selected dictionaries, formatted as "Technical vocabulary: term1, term2, ..."
  - Result: "Custom text. Technical vocabulary: PHP, Docker, ..."

**The prefill prompt is then used in DecodingOptions**:
- Line 282-286 (chunk) and 400-412 (full transcription)
- Sets `usePrefillPrompt: usePrefill` and `usePrefillCache: usePrefill`
- WhisperKit uses this to "prime" the decoder with context before transcribing

**Key architectural insight**: The current `customPrefillPrompt` field (line 341-346 in UserSettings.swift) is specifically for adding **additional terms** to supplement the vocabulary dictionaries. It gets combined with dictionary terms in `buildFullPrefillPrompt()`.

### What "Warmup Prompt" Actually Means

Based on the task description and existing architecture, a "warmup prompt" appears to be:
- A **separate** prompt used specifically to warm up the model (potentially before the first transcription)
- Different from the prefill prompt which provides context **during** each transcription
- Should NOT be combined with dictionary terms (unlike customPrefillPrompt)
- Used to exercise the model's decoder path with sample text

The distinction:
- **Prefill prompt** (existing): Context for each transcription segment ("Speaker 1: Hello. Speaker 2: Hi there...")
- **Warmup prompt** (new): Pre-exercise the model once after loading to optimize first-run performance

### Integration Points for Implementation

#### 1. UserSettings - Add Warmup Prompt Storage

**File**: `/Users/nb/Developement/TranscribeIt/Sources/Utils/UserSettings.swift`

**Add to Keys enum** (line 24-36):
```swift
static let warmupPrompt = "com.transcribeit.warmupPrompt"
```

**Add property** (after line 346, near customPrefillPrompt):
```swift
@Published public var warmupPrompt: String {
    didSet {
        defaults.set(warmupPrompt, forKey: Keys.warmupPrompt)
        LogManager.app.info("Warmup prompt updated (\(warmupPrompt.count) characters)")
    }
}
```

**Initialize in init()** (after line 66):
```swift
self.warmupPrompt = defaults.string(forKey: Keys.warmupPrompt) ?? ""
```

**Add to reset()** (line 517):
```swift
warmupPrompt = ""
```

**Why this pattern**: Matches the existing `customPrefillPrompt` pattern (line 341-346) with @Published for SwiftUI reactivity and didSet for immediate UserDefaults persistence.

#### 2. UserSettingsProtocol - Add Protocol Requirement

**File**: `/Users/nb/Developement/TranscribeIt/Sources/Protocols/UserSettingsProtocol.swift`

**Add property** (after line 86, in the "Vocabulary Dictionaries & Language" section):
```swift
/// Warmup prompt for model initialization
var warmupPrompt: String { get set }
```

**Why**: Maintains protocol conformance and enables dependency injection for testing.

#### 3. SettingsPanel UI - Add Warmup Prompt Field

**File**: `/Users/nb/Developement/TranscribeIt/Sources/UI/Views/Transcription/SettingsPanel.swift`

**Current structure**: The SettingsPanel has:
- Title and main VStack (line 14-17)
- HStack with Model picker and Language picker (line 19-55)
- VAD algorithm picker section (line 58-96)
- Retranscribe button (line 99-115)

**Add warmup prompt section** (after line 96, before the retranscribe button):

```swift
// Warmup prompt section
VStack(alignment: .leading, spacing: Constants.labelVerticalSpacing) {
    Text("Model Warmup Prompt")
        .font(.system(size: Constants.labelFontSize, weight: .medium))
        .foregroundColor(.secondary)

    Text("Optional text to warm up the model after loading (improves first transcription)")
        .font(.system(size: Constants.descriptionFontSize))
        .foregroundColor(.secondary.opacity(Constants.descriptionOpacity))

    TextEditor(text: Binding(
        get: { userSettings.warmupPrompt },
        set: { userSettings.warmupPrompt = $0 }
    ))
    .font(.system(size: 12, design: .monospaced))
    .frame(height: 60)
    .border(Color.secondary.opacity(0.2))
}
```

**Pattern reference**: This matches the TextEditor pattern used in SettingsView.swift (line 324-330) for `customPrefillPrompt`. The Binding creates a two-way connection between the UI and UserSettings, with auto-save happening via the `didSet` in UserSettings.

**Why SettingsPanel**: This is the settings UI shown in the FileTranscriptionView during transcription, making it the appropriate place for model-related settings alongside model selection and VAD algorithm.

**Add userSettings binding**: The SettingsPanel needs access to UserSettings. Currently it only has modelManager. Need to add:

```swift
@ObservedObject var userSettings: UserSettings  // Add this property
```

And update the initialization site in FileTranscriptionView.

#### 4. WhisperService - Integrate Warmup Prompt

**File**: `/Users/nb/Developement/TranscribeIt/Sources/Services/WhisperService.swift`

**Integration point**: After model loads successfully in `loadModel()` (after line 195, before verifyMetalAcceleration())

```swift
// Warm up model with warmup prompt if provided
let settings = UserSettings.shared
if !settings.warmupPrompt.isEmpty {
    LogManager.transcription.info("Warming up model with custom prompt (\(settings.warmupPrompt.count) chars)")
    // Create minimal audio (e.g., 1 second of silence) for warmup
    let warmupAudio = [Float](repeating: 0.0, count: 16000) // 1 second of silence at 16kHz

    let warmupOptions = DecodingOptions(
        task: .transcribe,
        language: settings.transcriptionLanguage,
        temperature: 0.0,
        usePrefillPrompt: true,  // Use the warmup prompt
        usePrefillCache: true
    )

    // Note: WhisperKit currently doesn't expose a direct way to set prefill text
    // This may require using the promptText property or similar mechanism
    do {
        let _ = try await whisperKit?.transcribe(
            audioArray: warmupAudio,
            decodeOptions: warmupOptions
        )
        LogManager.transcription.success("Model warmed up successfully")
    } catch {
        LogManager.transcription.warning("Warmup transcription failed (non-critical): \(error)")
    }
}
```

**Important consideration**: Looking at the existing code, `promptText` is a class property (line 68) but it's only logged (line 438) and not actually used by WhisperKit's transcribe() method. The prefill mechanism in WhisperKit works through `DecodingOptions.usePrefillPrompt` flag, but the actual prefill text content is provided via a separate mechanism (likely through the initial prompt tokens).

**Investigation needed**: The TODO comment at line 434 says "Добавить токенизацию промпта когда получим доступ к tokenizer" (Add prompt tokenization when we get access to tokenizer). This suggests the prefill text isn't currently being used properly.

**Recommended approach for warmup**:
1. Use the `promptText` property approach shown in `transcribe(audioSamples:contextPrompt:)` (line 340-354)
2. Temporarily set `self.promptText = settings.warmupPrompt` before warmup
3. Call transcribe with minimal audio (1 second of silence)
4. Restore original `promptText` after warmup

```swift
// Warm up model with warmup prompt if provided
let settings = UserSettings.shared
if !settings.warmupPrompt.isEmpty {
    LogManager.transcription.info("Warming up model with custom prompt (\(settings.warmupPrompt.count) chars)")

    // Save and set warmup prompt
    let originalPrompt = self.promptText
    self.promptText = settings.warmupPrompt

    // Create minimal audio for warmup (1 second of silence at 16kHz)
    let warmupAudio = [Float](repeating: 0.0, count: 16000)

    let warmupOptions = DecodingOptions(
        task: .transcribe,
        language: settings.transcriptionLanguage,
        temperature: 0.0,
        topK: 1,  // Greedy decoding for speed
        usePrefillPrompt: true,
        usePrefillCache: true,
        detectLanguage: false
    )

    do {
        let _ = try await whisperKit?.transcribe(
            audioArray: warmupAudio,
            decodeOptions: warmupOptions
        )
        LogManager.transcription.success("Model warmed up successfully")
    } catch {
        LogManager.transcription.warning("Warmup transcription failed (non-critical): \(error)")
    }

    // Restore original prompt
    self.promptText = originalPrompt
}
```

**Why after line 195**: Model is fully loaded and ready, but before any real transcription. The verifyMetalAcceleration() call is just logging, so warmup can happen before or after it.

#### 5. FileTranscriptionView - Pass UserSettings to SettingsPanel

**File**: `/Users/nb/Developement/TranscribeIt/Sources/UI/Views/Transcription/FileTranscriptionView.swift`

**Current SettingsPanel instantiation** (line 68-74):
```swift
SettingsPanel(
    selectedModel: $selectedModel,
    selectedVADAlgorithm: $selectedVADAlgorithm,
    selectedLanguage: $selectedLanguage,
    modelManager: modelManager,
    onRetranscribe: handleRetranscribe
)
```

**Update to include userSettings** (line 68-75):
```swift
SettingsPanel(
    selectedModel: $selectedModel,
    selectedVADAlgorithm: $selectedVADAlgorithm,
    selectedLanguage: $selectedLanguage,
    modelManager: modelManager,
    userSettings: userSettings,  // Add this parameter
    onRetranscribe: handleRetranscribe
)
```

**Context**: FileTranscriptionView already has `userSettings` as a property (line 58 shows it being passed to HeaderView), so we just need to pass it through to SettingsPanel as well.

### Technical Reference Details

#### Data Persistence Pattern
- **UserDefaults key prefix**: `com.transcribeit.*`
- **@Published properties**: Trigger SwiftUI view updates automatically
- **didSet observers**: Persist to UserDefaults immediately (no manual save button needed)
- **Protocol requirement**: Must add to UserSettingsProtocol for testability

#### UI Component Patterns
- **TextEditor**: Multi-line text input, bound directly to UserSettings property
- **Binding<String>**: Two-way binding pattern: `Binding(get:set:)`
- **Auto-save**: Changes to TextEditor trigger UserSettings didSet automatically
- **Styling**: Monospaced font at 12pt, height 60-80, border with secondary color at 0.2 opacity
- **Constants**: All dimensions defined in TranscriptionViewConstants.swift

#### WhisperService Decoding Options
```swift
public struct DecodingOptions {
    var task: Task = .transcribe
    var language: String? = nil
    var temperature: Float = 0.0
    var temperatureIncrementOnFallback: Float? = nil
    var temperatureFallbackCount: Int? = nil
    var topK: Int = 5  // Beam search width
    var usePrefillPrompt: Bool = true
    var usePrefillCache: Bool = true
    var detectLanguage: Bool = false
    var compressionRatioThreshold: Float? = nil
    var logProbThreshold: Float? = nil
    var noSpeechThreshold: Float? = nil
}
```

#### File Locations Summary
1. **UserSettings**: `/Users/nb/Developement/TranscribeIt/Sources/Utils/UserSettings.swift`
   - Add Keys.warmupPrompt (line ~35)
   - Add @Published property (after line 346)
   - Initialize in init() (after line 66)
   - Add to reset() (line 517)

2. **UserSettingsProtocol**: `/Users/nb/Developement/TranscribeIt/Sources/Protocols/UserSettingsProtocol.swift`
   - Add protocol requirement (after line 86)

3. **SettingsPanel**: `/Users/nb/Developement/TranscribeIt/Sources/UI/Views/Transcription/SettingsPanel.swift`
   - Add userSettings ObservedObject property (after line 10)
   - Add warmup prompt UI section (after line 96)

4. **WhisperService**: `/Users/nb/Developement/TranscribeIt/Sources/Services/WhisperService.swift`
   - Add warmup logic after model load (after line 195)

5. **TranscriptionViewConstants**: May need new constants for warmup section styling (optional, can reuse existing SettingsPanel constants)

#### Mock Implementation Requirements

**File**: `/Users/nb/Developement/TranscribeIt/Tests/Mocks/MockUserSettings.swift`

**Add property** (after line 123, in the "Vocabulary Dictionaries & Language" section):
```swift
public var warmupPrompt: String = ""
```

**Add to reset() method** (line 171, after customPrefillPrompt reset):
```swift
warmupPrompt = ""
```

**Why**: MockUserSettings implements UserSettingsProtocol, so it must include all protocol requirements. The mock uses simple property storage without UserDefaults persistence.

### Potential Issues & Considerations

1. **WhisperKit Prefill API**: The exact API for setting prefill text during warmup may differ from transcription context. The `promptText` property approach (line 68, 438) is used for context prompts, but warmup may need a different approach.

2. **Warmup Timing**: Running warmup transcription adds ~0.5-2 seconds to model load time. This is acceptable but should be logged clearly.

3. **Silent Audio**: Using 1 second of silence for warmup is simple but may not fully exercise the decoder. Consider using a short (~3 seconds) pre-recorded audio sample instead if warmup effectiveness is insufficient.

4. **FileTranscriptionView location**: Need to locate this file to update SettingsPanel instantiation. Likely in `/Users/nb/Developement/TranscribeIt/Sources/UI/Views/Transcription/`

5. **Distinction from customPrefillPrompt**: The UI should make clear that:
   - **Warmup prompt**: One-time model warmup after loading
   - **Custom prefill prompt** (in SettingsView): Added to every transcription with dictionary terms

### Architecture Alignment

This implementation follows the established patterns:
- ✅ MVVM: UI binds to UserSettings (ViewModel/Model)
- ✅ Protocol-oriented: UserSettingsProtocol updated for testability
- ✅ Dependency Injection: UserSettings injected via DependencyContainer
- ✅ @Published reactivity: SwiftUI auto-updates when settings change
- ✅ Immediate persistence: UserDefaults updates in didSet
- ✅ Constants extraction: Can reuse SettingsPanel constants
- ✅ Typed error handling: WhisperService already handles transcription errors
- ✅ Logging: LogManager.transcription for warmup operations

## User Notes
<!-- Any specific notes or requirements from the developer -->

## Work Log
<!-- Updated as work progresses -->
- [YYYY-MM-DD] Started task, initial research
