# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**TranscribeIt** is a professional desktop application for transcribing **stereo telephone call recordings** on Apple Silicon (M1/M2/M3).

### Key Features
- **Dual-channel speaker separation**: Left and right audio channels are processed separately to distinguish between two speakers
- **On-device transcription**: Uses WhisperKit with Metal GPU acceleration for privacy and speed
- **Timeline visualization**: Synchronized view showing both speakers with clickable segments for audio playback
- **Multi-format export**: SRT, VTT, TXT, DOCX, JSON formats with speaker labels
- **Audio playback controls**: Variable speed, mono/stereo switching, volume boost for low-quality recordings

### Primary Use Case
Processing stereo telephone recordings where:
- **Left channel** = Speaker 1 (caller)
- **Right channel** = Speaker 2 (recipient)

The application is built with **Swift** and uses **WhisperKit** for on-device speech recognition with Metal GPU acceleration.

## Architecture

### Core Services

#### 1. FileTranscriptionService (`Sources/Services/FileTranscriptionService.swift`)
- Handles individual file transcription workflow
- Audio format conversion and normalization
- Real-time progress tracking
- **Key Methods**:
  - `transcribeFile()` - Main transcription pipeline
  - `prepareAudioFile()` - Format conversion and preprocessing
  - `processSegments()` - Segment-by-segment transcription with timestamps

#### 2. BatchTranscriptionService (`Sources/Services/BatchTranscriptionService.swift`)
- Multi-file queue management (currently not used in main UI - single file mode)
- Parallel processing with configurable concurrency
- Batch progress tracking
- **Key Methods**:
  - `addToQueue()` - Adds files to transcription queue
  - `processBatch()` - Manages concurrent transcription jobs
  - `pauseProcessing()` / `resumeProcessing()` - Queue control
- **Note**: Current application workflow processes one file at a time

#### 3. WhisperService (`Sources/Services/WhisperService.swift`)
- WhisperKit integration for on-device transcription
- Metal GPU acceleration through MLX backend
- Performance metrics (Real-Time Factor, transcription speed)
- Support for multiple Whisper model sizes (tiny, base, small, medium, large)
- **Key Methods**:
  - `loadModel()` - Downloads and initializes WhisperKit model
  - `transcribe()` - Transcribes audio with timestamps
  - `verifyMetalAcceleration()` - Checks Metal GPU availability

#### 4. ExportManager (`Sources/Utils/ExportManager.swift`)
- Multi-format export system
- Supported formats:
  - **SRT** - SubRip subtitles with timestamps
  - **VTT** - WebVTT subtitles
  - **TXT** - Plain text with optional timestamps
  - **DOCX** - Microsoft Word document
  - **JSON** - Structured data with full metadata
- **Key Methods**:
  - `export(to:format:)` - Exports transcription to specified format
  - `generateSRT()` / `generateVTT()` - Subtitle generation
  - `generateDOCX()` - Word document creation

### UI Components

#### 1. MainWindow (`Sources/UI/MainWindow.swift`)
- Main transcription interface
- File drag-and-drop support
- Real-time transcription display with synchronized columns:
  - Timestamp column (editable)
  - Transcription text (editable)
  - Waveform visualization
- Audio player controls with waveform scrubbing
- **Features**:
  - Click timestamp to jump to audio position
  - Click waveform to seek audio
  - Edit timestamps and text inline
  - Visual feedback for current playback position

#### 2. MenuBarController (`Sources/UI/MenuBarController.swift`)
- Menu bar integration
- Quick access to:
  - Open files / batch import
  - Recent files
  - Export options
  - Settings
  - Model management

### Audio Processing

#### 1. AudioPlayerManager (`Sources/Utils/AudioPlayerManager.swift`)
- Advanced audio playback with waveform visualization
- Frame-accurate seeking
- Playback speed control
- Waveform generation and caching
- **Key Methods**:
  - `loadAudio()` - Loads audio file and generates waveform
  - `seek(to:)` - Frame-accurate position seeking
  - `setPlaybackSpeed()` - Adjustable playback rate

#### 2. AudioFileNormalizer (`Sources/Utils/AudioFileNormalizer.swift`)
- Audio preprocessing for optimal transcription
- Noise reduction
- Volume normalization
- Format conversion to WhisperKit-compatible format (16kHz mono Float32)
- **Key Methods**:
  - `normalize()` - Full audio preprocessing pipeline
  - `convertFormat()` - Format conversion
  - `applyNoiseReduction()` - Audio cleanup

#### 3. VAD System (Voice Activity Detection)
Multiple VAD implementations for different use cases:
- **SpectralVAD** (`Sources/Utils/SpectralVAD.swift`) - Spectral energy analysis
- **AdaptiveVAD** (`Sources/Utils/AdaptiveVAD.swift`) - Adaptive threshold adjustment
- **VoiceActivityDetector** (`Sources/Utils/VoiceActivityDetector.swift`) - Base VAD interface
- **SilenceDetector** (`Sources/Utils/SilenceDetector.swift`) - Silence trimming

Used for:
- Dual-channel speaker separation
- Automatic silence trimming
- Segment boundary detection

### Vocabulary & Model Management

#### 1. VocabularyManager (`Sources/Utils/VocabularyManager.swift`)
- Custom vocabulary support for improved accuracy
- Domain-specific dictionaries
- Word replacement rules
- **Key Methods**:
  - `loadDictionary()` - Loads custom vocabulary
  - `applyCorrections()` - Post-processing text corrections

#### 2. ModelManager (`Sources/Utils/ModelManager.swift`)
- WhisperKit model download and management
- Multiple model size support (tiny, base, small, medium, large)
- Model switching without restart
- Storage management
- **Key Methods**:
  - `downloadModel()` - Downloads model from Hugging Face
  - `listAvailableModels()` - Shows installed and available models
  - `deleteModel()` - Removes unused models

### System Logging

**LogManager** (`Sources/Utils/LogManager.swift`)
- Unified logging system using Apple's OSLog framework
- Categories: `app`, `file`, `batch`, `transcription`, `export`, `audio`
- Subsystem: `com.transcribeit.app`
- **Viewing logs**:
```bash
# Real-time log stream
log stream --predicate 'subsystem == "com.transcribeit.app"'

# Filter by category
log stream --predicate 'subsystem == "com.transcribeit.app" && category == "transcription"'

# Show last hour
log show --predicate 'subsystem == "com.transcribeit.app"' --last 1h
```

### Permissions

**Required**:
- ✅ Microphone access (AVFoundation) - for audio file processing (required by WhisperKit)

**NOT Required**:
- ❌ Accessibility - not needed for file transcription
- ❌ Input Monitoring - not needed for file transcription

**PermissionManager** (`Sources/Utils/PermissionManager.swift`)
- Simplified permission checker (microphone only)
- Async permission request with user feedback

### User Settings

**UserSettings** (`Sources/Utils/UserSettings.swift`)
- Persistent application configuration using UserDefaults
- Settings:
  - Whisper model selection (tiny/base/small/medium/large)
  - Dual-channel mode (speaker separation)
  - Auto-export on completion
  - Default export format
  - Audio normalization preferences
  - VAD sensitivity

## Development Tasks

### Building the Application

```bash
# Build the application
swift build

# Run the main executable
.build/debug/TranscribeIt

# Build release version
swift build -c release
```

### Building .app Bundle

```bash
# Build signed .app with entitlements
./build_app.sh
```

### Testing Audio Processing

Test files should be placed in a `test_audio/` directory (gitignored):
- Supported formats: MP3, M4A, WAV, AIFF, AAC, FLAC, MP4, MOV
- Test with various sample rates and channel configurations
- Dual-channel files for speaker separation testing

## Common Issues & Debugging

### Model Loading Fails

**Problem**: WhisperKit model download fails

**Solutions**:
1. Check internet connection (models downloaded from Hugging Face)
2. Verify Metal GPU availability:
   ```bash
   log stream --predicate 'subsystem == "com.transcribeit.app" && category == "transcription"'
   ```
3. Clear WhisperKit cache: `~/Library/Caches/whisperkit_models/`
4. Try smaller model first (tiny or base)

### Transcription Quality Issues

**Problem**: Poor transcription accuracy

**Solutions**:
1. Use larger Whisper model (medium or large)
2. Enable audio normalization in settings
3. Check audio quality (16kHz+ sample rate recommended)
4. Add custom vocabulary for domain-specific terms
5. For dual-channel, ensure left/right channels have distinct speakers

### Export Fails

**Problem**: Export to specific format fails

**Solutions**:
1. Check write permissions for export directory
2. For DOCX export, verify sufficient disk space
3. Check logs for specific error:
   ```bash
   log stream --predicate 'subsystem == "com.transcribeit.app" && category == "export"'
   ```

### Audio Player Issues

**Problem**: Waveform not displaying or playback stuttering

**Solutions**:
1. Check audio file format compatibility
2. Verify audio file isn't corrupted
3. Check logs for audio processing errors:
   ```bash
   log stream --predicate 'subsystem == "com.transcribeit.app" && category == "audio"'
   ```
4. Try re-encoding audio file to standard format

### Viewing Application Logs

**Real-time monitoring**:
```bash
# All logs
log stream --predicate 'subsystem == "com.transcribeit.app"' --level debug

# Only errors
log stream --predicate 'subsystem == "com.transcribeit.app" && eventType >= logEventType.error'

# Specific category (file processing)
log stream --predicate 'subsystem == "com.transcribeit.app" && category == "file"'
```

**Historical logs**:
```bash
# Last 30 minutes
log show --predicate 'subsystem == "com.transcribeit.app"' --last 30m

# Export to file
log show --predicate 'subsystem == "com.transcribeit.app"' --last 1h > logs.txt
```

## Key Design Principles

1. **File-based Processing**: Optimized for batch file transcription, not live recording
2. **Professional Features**: Multi-format export, dual-channel support, waveform editing
3. **On-device Processing**: WhisperKit runs entirely on device with Metal GPU acceleration
4. **Minimal Permissions**: Only microphone access required (WhisperKit requirement)
5. **Performance Monitoring**: Real-Time Factor (RTF) tracking for transcription speed
6. **Menu Bar Integration**: Lightweight menu bar app with drag-and-drop support
7. **Editable Output**: All timestamps and transcriptions are editable before export

## Code References

- File transcription: `Sources/Services/FileTranscriptionService.swift:45`
- Batch processing: `Sources/Services/BatchTranscriptionService.swift:67`
- Export formats: `Sources/Utils/ExportManager.swift:32`
- Waveform visualization: `Sources/Utils/AudioPlayerManager.swift:89`
- Speaker separation: `Sources/Services/FileTranscriptionService.swift:123`
- Model management: `Sources/Utils/ModelManager.swift:56`
