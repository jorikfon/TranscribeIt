---
name: h-fix-audio-device-hang-on-change
branch: fix/h-fix-audio-device-hang-on-change
status: pending
created: 2025-11-18
---

# Fix Audio Device Hang on Change

## Problem/Goal
Application freezes when audio devices are disconnected/reconnected (e.g., unplugging headphones). The app becomes unresponsive until the original device is restored, preventing automatic switching to available output devices (laptop speakers).

## Success Criteria
- [ ] Application continues playback when audio device is disconnected (auto-switches to available device)
- [ ] No UI freeze or hang when audio devices are added/removed
- [ ] Graceful error handling with user notification if no output devices available
- [ ] Audio playback resumes automatically after device reconnection
- [ ] Manual testing confirms stable behavior across multiple device changes during playback

## Context Manifest

### How Audio Playback Currently Works: AVAudioEngine Architecture

When a user loads an audio file for playback in TranscribeIt, the application uses a sophisticated AVAudioEngine-based architecture designed for advanced audio processing. Here's the complete flow from file loading to playback:

**Initial File Loading (`loadAudio(from:)` - lines 206-275)**

The `AudioPlayerManager` class (Sources/Utils/AudioPlayerManager.swift) manages all audio playback using AVAudioEngine, a low-level audio processing framework that provides real-time effects processing, volume boost, and variable speed playback. When `loadAudio(from: URL)` is called, the manager first checks if the file is already loaded to avoid redundant processing. If currently playing, it stops the existing playback by calling `playerNode.stop()` and `stopProgressTimer()`. Critically, if the engine is running, it stops the engine with `audioEngine.stop()` (line 223).

The audio file is loaded using AVAudioFile, and for stereo telephone recordings, a sophisticated 65/35 channel mixing is applied via `applyChannelMixing(to:)` (lines 138-186). This mixing creates a more comfortable listening experience for telephone conversations by blending channels: left ear receives 65% left channel + 35% right channel, right ear receives 35% left + 65% right. This mixing operation reads the entire file into an AVAudioPCMBuffer, processes every frame, and writes the result to a temporary .caf file in the system temp directory.

**Audio Graph Configuration**

The audio processing graph is configured in a specific node chain: `playerNode → timePitch → mixer → audioEngine.mainMixerNode → output`. This graph is established by:

1. `disconnectAllNodes()` (lines 100-103) - Clears previous connections to allow reconfiguration
2. `configureAudioGraph(format:)` (lines 110-117) - Establishes the processing chain
3. `applyCurrentSettings()` (lines 122-125) - Syncs UI state (playback rate, volume boost) to audio nodes

The AVAudioEngine is initialized once in `init(audioCache:)` via `setupAudioEngine()` (lines 79-83), which attaches three core nodes:
- `AVAudioPlayerNode` - Plays audio buffers with precise frame control
- `AVAudioUnitTimePitch` - Adjusts playback speed (0.5x-2.0x) without pitch shifting
- `AVAudioMixerNode` - Controls volume with boost capability (100%-500%)

**Playback Execution (`play()` - lines 279-338)**

When the user clicks play, the `play()` method executes a critical sequence. First, it forcibly stops and resets the playerNode if already playing (lines 287-295) to prevent audio stream overlap - this was a critical bug fix documented in the code comments. Then it checks if the audioEngine is running; if not, it attempts to start it with `try audioEngine.start()` (line 303).

**THIS IS WHERE THE HANG OCCURS**: If the audio output device has been disconnected, `audioEngine.start()` throws an error, which is caught and logged (line 305), but the method simply returns without any recovery attempt. The application does not attempt to reconnect to a new output device or notify the user. The engine remains stopped, and the UI shows the play button, but clicking it repeatedly fails silently because the engine cannot start.

The playback mechanism uses `playerNode.scheduleSegment()` to queue audio frames from the current position to the end of the file, with a completion handler that runs on the main thread when playback finishes naturally (lines 321-325). The method calculates the start frame based on `currentTime * sampleRate` and validates it's within file bounds.

**State Management via AudioPlayerState**

The application uses a structured state management pattern via `AudioPlayerState` (Sources/UI/ViewModels/AudioPlayerState.swift), which is an Equatable struct containing three nested structs:
- `PlaybackState` - isPlaying, currentTime, duration, progress
- `AudioState` - volume, volumeBoost, effectiveVolume (computed property)
- `AudioSettings` - playbackRate, pauseOtherPlayersEnabled

This state is published via `@Published var state = AudioPlayerState()` (line 42) and observed by SwiftUI views. The state updates happen on the main thread via explicit `DispatchQueue.main.async` blocks (lines 331-337, 347-354) to guarantee UI synchronization during rapid play/pause clicks.

**Progress Tracking Mechanism**

A Timer-based progress tracking system (`startProgressTimer()` - lines 449-467) fires every 0.1 seconds and updates `currentTime` based on `CACurrentMediaTime() - startTime`. This approach uses high-resolution system time rather than polling the AVAudioPlayerNode for position, which provides smoother UI updates. The timer is invalidated when pausing or stopping.

**Audio Cache Integration**

The manager integrates with an Actor-based AudioCache (Sources/Utils/Audio/AudioCache.swift) for performance optimization. When loading a file, it asynchronously checks the cache via `audioCache.loadAudio(from:)` (lines 229-238). Cache failures are non-critical and logged as debug messages. The cache prevents redundant file loading across three usage contexts: mono transcription, stereo channel separation, and playback.

**Current Error Handling - The Gap**

The current error handling for audio playback is minimal and problematic:

1. **Engine Start Failure** (line 303-307): Catches errors from `audioEngine.start()`, logs them, and returns. No user notification, no recovery attempt, no device switching logic.

2. **No Device Change Monitoring**: The codebase contains ZERO instances of NotificationCenter observers, audio route change notifications, or AVAudioEngine configuration change handlers. A grep search for "AVAudioSession", "NotificationCenter", "audioRouteChange", "deviceChange", and "interruption" returned no matches in the Swift codebase.

3. **No AVAudioEngine.configurationChangeNotification Handling**: AVAudioEngine posts this notification when the audio hardware configuration changes (sample rate change, channel count change, or output device disconnection). The application does not observe this notification.

4. **Synchronous Stop Operations**: `audioEngine.stop()` is called synchronously on the main thread in `loadAudio()`, `pause()`, `stop()`, and `deinit`. If the engine is in a bad state due to device disconnection, these calls could potentially block or fail silently.

**Why The Application Hangs**

When an audio output device (headphones) is disconnected during playback:

1. The AVAudioEngine's output node loses its connection to the hardware
2. The engine may stop itself or enter an error state
3. The playerNode may continue "playing" to a disconnected output
4. The progress timer continues updating `currentTime`, making it appear the playback is progressing
5. When the user clicks pause/play, `audioEngine.start()` throws an error because no valid output device is selected
6. The UI remains responsive (the main thread isn't blocked), but playback controls become non-functional
7. The application never attempts to enumerate available audio devices or switch to the default output (laptop speakers)

The "hang" is actually a stuck state where the engine cannot start, but the application provides no feedback or recovery mechanism. The only way to recover is to reconnect the original device, which allows `audioEngine.start()` to succeed again.

### macOS Audio System Architecture & Device Change APIs

**AVAudioEngine Configuration Change Notification**

macOS provides `AVAudioEngine.configurationChangeNotification` (previously `AVAudioEngineConfigurationChangeNotification` in older APIs), which is posted when:
- The audio hardware sample rate changes
- The number of input or output channels changes
- An audio device is connected or disconnected
- The audio route changes (e.g., switching from headphones to speakers)

This notification is posted on the notification center and should be observed to detect device changes. When received, the recommended practice is to:
1. Stop the engine (`audioEngine.stop()`)
2. Reconfigure the audio graph if needed
3. Restart the engine (`audioEngine.start()`)

**NotificationCenter Pattern for Audio Observation**

The standard Swift pattern for observing audio changes:

```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleConfigurationChange),
    name: .AVAudioEngineConfigurationChange,
    object: audioEngine
)
```

Important: The observer must be removed in `deinit` to prevent memory leaks and crashes.

**AVAudioSession (iOS) vs AVAudioEngine (macOS)**

On iOS, `AVAudioSession` provides extensive APIs for monitoring audio route changes via `AVAudioSessionRouteChangeNotification`. However, on macOS, AVAudioSession is limited. The equivalent functionality is provided through:
- `AVAudioEngine.configurationChangeNotification` for hardware changes
- CoreAudio's `AudioObjectPropertyAddress` for low-level device enumeration
- `AVCaptureDevice` for input device monitoring (less relevant for output-only use cases)

For macOS desktop audio output switching, AVAudioEngine's configuration change notification is the appropriate high-level API.

**Audio Device Enumeration on macOS**

To enumerate available audio output devices on macOS, you need to use CoreAudio's AudioObjectGetPropertyData with `kAudioHardwarePropertyDevices`. However, AVAudioEngine typically handles device selection automatically by connecting to the system's default output device. When you call `audioEngine.start()` after a device disconnection, the engine should automatically connect to the current default output (usually laptop speakers).

**The Key Problem: Why Manual Device Switching Isn't Needed**

The core issue is NOT that we need to manually select a new device - AVAudioEngine will automatically use the system default output when started. The problem is:
1. We don't detect when the configuration has changed
2. We don't attempt to restart the engine when the device changes
3. We leave the engine in a stopped/error state without recovery

### Existing Architectural Patterns in the Codebase

**Singleton Pattern for System Services**

The application uses singleton instances for system-level managers:
- `ModelManager.shared` - Whisper model management
- `UserSettings.shared` - Application preferences
- `VocabularyManager.shared` - Custom vocabulary

However, `AudioPlayerManager` is NOT a singleton - it's instantiated via the DependencyContainer and injected into ViewModels. Each window could potentially have its own instance.

**Dependency Injection via DependencyContainer**

The application uses a Service Locator pattern (Sources/DI/DependencyContainer.swift) where:
- Singletons are stored as properties: `modelManager`, `userSettings`, `vocabularyManager`, `audioCache`
- Services are created via factory methods: `makeWhisperService()`, `makeFileTranscriptionService()`

The AudioPlayerManager is created by FileTranscriptionViewModel:
```swift
public let audioPlayer: AudioPlayerManager

public init(audioCache: AudioCache) {
    self.audioPlayer = AudioPlayerManager(audioCache: audioCache)
}
```

This means notification observers should be set up in `AudioPlayerManager.init()` and removed in `deinit`.

**Actor-Based Concurrency Pattern (AudioCache)**

The AudioCache uses Swift's actor pattern for thread-safe audio data caching. All cache methods are async and automatically serialize access. This pattern is NOT used in AudioPlayerManager, which uses AVAudioEngine on the main thread and explicit `DispatchQueue.main.async` blocks for state updates.

**ObservableObject & @Published Pattern**

AudioPlayerManager conforms to ObservableObject and publishes its state:
```swift
@Published public var state = AudioPlayerState()
```

SwiftUI views (AudioPlayerView) observe this state via `@ObservedObject`. State changes automatically trigger UI updates. When handling audio device changes, we must ensure state updates happen on the main thread.

**Typed Error Handling**

The codebase uses strongly-typed error enums (Sources/Errors/AudioPlayerError.swift) with LocalizedError conformance:
- `loadFailed(Error)` - Wraps underlying file loading errors
- `playbackFailed(String)` - Generic playback failure
- `engineStartFailed(Error)` - AVAudioEngine start failure
- `nodeConnectionFailed(from:to:reason:)` - Audio graph connection errors

Each error provides:
- `errorDescription` - User-friendly Russian message
- `recoverySuggestion` - Actionable steps to resolve
- `failureReason` - Technical details for logging

We should add a new error case for device disconnection scenarios.

**Logging via LogManager**

The application uses Apple's OSLog framework via a custom LogManager (Sources/Utils/LogManager.swift) with structured logging:
- `LogManager.app` - Application-level events
- Categories: app, file, batch, transcription, export, audio

Audio-related events use `LogManager.app` with severity levels: info, debug, success, warning, failure. Device change handling should log to the audio category for filtering.

### Implementation Strategy: What Needs to Connect

**Device Change Detection Hook Point**

The `AudioPlayerManager.setupAudioEngine()` method (line 79) is called once during initialization. This is the ideal location to set up the configuration change observer:

```swift
private func setupAudioEngine() {
    attachAudioNodes()
    configureMixerDefaults()
    setupConfigurationChangeObserver()  // NEW
    LogManager.app.info("AudioPlayerManager: AVAudioEngine настроен")
}
```

The observer should be added after the engine is set up but before any playback occurs.

**Observer Lifecycle Management**

The observer must be stored as a property and removed in deinit:
```swift
private var configurationChangeObserver: NSObjectProtocol?
```

In `deinit` (currently lines 475-482), add:
```swift
if let observer = configurationChangeObserver {
    NotificationCenter.default.removeObserver(observer)
}
```

**Handling Configuration Changes Without Blocking UI**

The configuration change handler will be called on an arbitrary thread (likely a CoreAudio thread). We must dispatch the recovery logic to avoid blocking the audio thread and to ensure thread safety for AVAudioEngine operations.

Strategy:
1. Receive notification on background thread
2. Schedule recovery on main thread via `DispatchQueue.main.async`
3. Check if currently playing (if `state.playback.isPlaying == true`)
4. Stop engine, reconfigure if needed, restart engine
5. If restart fails, update UI state to show error and disable playback controls

**Reconnection Logic Flow**

When AVAudioEngine.configurationChangeNotification is received:

1. **Check Current State**: If not playing or no file loaded, just log and return (no action needed)
2. **Capture Current Position**: Store `currentTime` before stopping to resume from same position
3. **Stop Engine Safely**: Call `audioEngine.stop()` - this should now succeed since we're responding to a configuration change
4. **Attempt Restart**: Try `audioEngine.start()` to reconnect to new default output
5. **Resume Playback**: If start succeeds and we were playing, call `play()` to resume from saved position
6. **Handle Failure**: If start fails (no audio devices available), update state, show user notification

**State Management During Device Changes**

The `AudioPlayerState` struct should potentially be extended with:
- `var audioDeviceConnected: Bool` - Track device connection state
- `var lastError: AudioPlayerError?` - Store last playback error for UI display

Alternatively, we could add a new `@Published var deviceStatus: DeviceStatus` enum:
```swift
enum DeviceStatus {
    case connected
    case disconnected
    case reconnecting
}
```

This allows the UI to show appropriate feedback (e.g., "Audio device disconnected, please connect headphones or speakers").

**UI Feedback Mechanism**

AudioPlayerView (Sources/UI/Views/Audio/AudioPlayerView.swift) should display the device status. Potential approaches:
1. Show a banner/alert when device disconnected
2. Disable playback controls when no device available
3. Display an icon/badge indicating device status
4. Toast notification: "Audio device changed, reconnecting..."

The view observes `audioPlayer.state`, so we can add the device status to the published state.

**Error Recovery vs User Notification**

Two scenarios need different handling:

**Scenario A: Device Disconnected, Alternatives Available**
- Headphones unplugged, laptop speakers available
- Action: Automatically switch to speakers, continue playback seamlessly
- User notification: Optional toast "Switched to built-in speakers"

**Scenario B: No Output Devices Available**
- All devices unplugged, no system audio output
- Action: Pause playback, disable controls
- User notification: "No audio output device detected. Please connect headphones or speakers."

We need to distinguish between these cases. If `audioEngine.start()` succeeds after configuration change, we're in Scenario A. If it fails with a device-related error, we're in Scenario B.

**Testing Strategy for Device Changes**

Manual testing scenarios:
1. Start playback with headphones → Unplug headphones → Verify switches to speakers
2. Start playback with speakers → Plug in headphones (macOS auto-switches) → Verify continues on headphones
3. Unplug all audio devices during playback → Verify graceful pause with error message
4. Play → Pause → Unplug device → Click Play → Verify handles stopped engine gracefully
5. Rapid device switching (plug/unplug multiple times) → Verify no crashes or zombie observers

**Edge Cases to Handle**

1. **Multiple Rapid Configuration Changes**: AVAudioEngine may post multiple notifications in quick succession (e.g., device disconnect followed by auto-connect to default). Use debouncing or state checks to avoid redundant restarts.

2. **Configuration Change While Loading File**: If notification arrives during `loadAudio()`, the engine might be mid-reconfiguration. Check `audioFile != nil` before attempting recovery.

3. **Configuration Change in Deinit**: If AudioPlayerManager is being deallocated during device change, ensure observer is removed before attempting recovery.

4. **Background App Behavior**: If the app is in the background when device changes, macOS may suspend audio operations. Check `NSApplication.isActive` or handle activation notifications.

5. **Sample Rate Mismatches**: Configuration changes can include sample rate changes. The current code connects nodes with `file.processingFormat`, which locks the graph to the file's sample rate. Ensure this doesn't conflict with the new device's sample rate.

### Technical Reference Details

#### AVAudioEngine Notification API

```swift
// Notification name (macOS 10.15+)
extension Notification.Name {
    static let AVAudioEngineConfigurationChange: Notification.Name
}

// Observer setup
NotificationCenter.default.addObserver(
    forName: .AVAudioEngineConfigurationChange,
    object: audioEngine,  // Observe specific engine instance
    queue: nil  // Callback on posting thread (audio thread)
) { [weak self] notification in
    // Handle configuration change
    self?.handleAudioConfigurationChange(notification)
}
```

#### AVAudioEngine Lifecycle Methods

```swift
// Start engine (connects to audio hardware)
func start() throws

// Stop engine (disconnects from hardware)
func stop()

// Reset engine state (clears all buffers)
func reset()

// Pause engine (maintains connection, stops processing)
func pause()

// Check engine state
var isRunning: Bool { get }
```

#### AudioPlayerManager Key Methods & State

```swift
// Located in: Sources/Utils/AudioPlayerManager.swift

class AudioPlayerManager: ObservableObject {
    // PUBLISHED STATE
    @Published public var state = AudioPlayerState()

    // AUDIO GRAPH NODES
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let mixer = AVAudioMixerNode()

    // CRITICAL METHODS FOR DEVICE HANDLING

    // Line 206: Load audio file
    public func loadAudio(from url: URL) throws

    // Line 279: Start playback (FAILS when device disconnected)
    public func play(shouldPauseOtherPlayers: Bool = false)

    // Line 341: Pause playback
    public func pause()

    // Line 358: Stop playback
    public func stop()

    // Line 378: Seek to time (used during device reconnection to restore position)
    public func seek(to time: TimeInterval)

    // Line 79: Setup audio engine (HOOK POINT for observer)
    private func setupAudioEngine()

    // Line 100: Disconnect nodes before reconfiguration
    private func disconnectAllNodes()

    // Line 110: Configure audio graph
    private func configureAudioGraph(format: AVAudioFormat)

    // Line 122: Apply current settings to nodes
    private func applyCurrentSettings()
}
```

#### AudioPlayerError Extension Needed

```swift
// Add to Sources/Errors/AudioPlayerError.swift

public enum AudioPlayerError: LocalizedError {
    // EXISTING CASES...

    // NEW CASES FOR DEVICE HANDLING
    case audioDeviceDisconnected
    case audioDeviceUnavailable
    case configurationChangeFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .audioDeviceDisconnected:
            return "Аудио устройство отключено"
        case .audioDeviceUnavailable:
            return "Нет доступных аудио устройств"
        case .configurationChangeFailed(let error):
            return "Ошибка изменения конфигурации аудио: \(error.localizedDescription)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .audioDeviceDisconnected:
            return "Переключаемся на встроенные динамики..."
        case .audioDeviceUnavailable:
            return "Подключите наушники или динамики для воспроизведения"
        case .configurationChangeFailed:
            return "Перезапустите воспроизведение"
        }
    }
}
```

#### File Locations for Implementation

- **Primary implementation**: `/Users/nb/Developement/TranscribeIt/Sources/Utils/AudioPlayerManager.swift`
  - Add observer setup in `setupAudioEngine()` (after line 82)
  - Add observer property at class level (after line 61)
  - Add handler method `handleAudioConfigurationChange()` (new method around line 484)
  - Add observer cleanup in `deinit` (modify lines 475-482)

- **Error definitions**: `/Users/nb/Developement/TranscribeIt/Sources/Errors/AudioPlayerError.swift`
  - Add new error cases (after line 40)
  - Add error descriptions (after line 70)
  - Add recovery suggestions (after line 101)

- **State management** (optional): `/Users/nb/Developement/TranscribeIt/Sources/UI/ViewModels/AudioPlayerState.swift`
  - Add `deviceStatus` property to AudioState or create new DeviceState struct
  - Add computed properties for UI feedback

- **UI feedback** (optional): `/Users/nb/Developement/TranscribeIt/Sources/UI/Views/Audio/AudioPlayerView.swift`
  - Add device status indicator
  - Add conditional rendering based on device state

- **Testing**: Create new test file `/Users/nb/Developement/TranscribeIt/Tests/Utils/AudioPlayerManagerDeviceTests.swift`
  - Test configuration change handling
  - Test observer lifecycle
  - Test state recovery after device changes

#### Configuration Constants

Consider adding to a new Constants file or extending existing AudioPlayerConstants:

```swift
enum AudioDeviceConstants {
    /// Debounce interval for configuration changes (seconds)
    static let configurationChangeDebounce: TimeInterval = 0.5

    /// Maximum retry attempts for engine restart
    static let maxRestartAttempts: Int = 3

    /// Delay between restart attempts (seconds)
    static let restartRetryDelay: TimeInterval = 0.2

    /// User notification display duration (seconds)
    static let notificationDuration: TimeInterval = 3.0
}
```

### Best Practices for Graceful Audio Device Switching

**1. Non-Blocking Recovery**: Never perform engine restart on the notification callback thread. Always dispatch to main queue for AVAudioEngine operations.

**2. State Preservation**: Save playback position before stopping engine to enable seamless resume. Store `currentTime`, `isPlaying`, and `state.settings.playbackRate`.

**3. Debouncing**: Configuration changes can fire multiple times in rapid succession. Implement debouncing to avoid redundant engine restarts (e.g., using Task.sleep or DispatchQueue.asyncAfter).

**4. Defensive Checks**: Before attempting restart, verify:
   - Audio file is loaded (`audioFile != nil`)
   - File URL is valid (`audioFileURL != nil`)
   - Format is available (`audioFormat != nil`)

**5. User Feedback**: Provide immediate feedback for device changes. Use transient notifications (toast) rather than blocking alerts to maintain playback UX flow.

**6. Error Recovery Hierarchy**:
   - Level 1: Silent recovery (device switch succeeded, continue playing)
   - Level 2: Notify + recover (show toast, resume playback)
   - Level 3: Notify + pause (show error, disable controls until device reconnected)

**7. Testing on Real Hardware**: Simulator does not accurately represent audio device handling. Test on actual macOS hardware with physical device connections/disconnections.

**8. Memory Management**: Ensure observer is properly removed in deinit. Use `[weak self]` in notification closure to prevent retain cycles.

**9. Thread Safety**: AVAudioEngine and AVAudioPlayerNode are NOT thread-safe. All operations must occur on the main thread. The current codebase already follows this pattern with explicit main thread dispatches.

**10. Logging for Debugging**: Log all configuration changes with device-specific details. Use structured logging with correlation IDs to trace device change events through the recovery flow.

### Recommended Implementation Approach

**Phase 1: Detection**
1. Add configuration change observer in `setupAudioEngine()`
2. Add observer cleanup in `deinit`
3. Implement basic handler that logs device changes

**Phase 2: Recovery**
1. Implement engine restart logic in handler
2. Preserve and restore playback state (position, isPlaying)
3. Handle restart failures gracefully

**Phase 3: User Feedback**
1. Add device status to published state
2. Show toast notifications for device changes
3. Update UI to disable controls when no device available

**Phase 4: Edge Case Handling**
1. Add debouncing for rapid changes
2. Handle sample rate mismatches
3. Test background app behavior
4. Add retry logic with exponential backoff

**Phase 5: Testing & Refinement**
1. Manual testing with various device scenarios
2. Add unit tests for state preservation
3. Add integration tests for full recovery flow
4. Performance testing for rapid device switching

## User Notes
Reported issue: When headphones are unplugged during playback, the application hangs and cannot switch to laptop speakers until headphones are plugged back in.

## Work Log
<!-- Updated as work progresses -->
- [2025-11-18] Task created
