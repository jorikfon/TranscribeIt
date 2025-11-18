# TranscribeIt

**Professional desktop application for transcribing stereo telephone call recordings on Apple Silicon**

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014.0+-blue.svg)](https://www.apple.com/macos)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-Required-black.svg)](https://www.apple.com/mac/)

---

## 🎯 Overview

TranscribeIt is a native macOS application designed specifically for **transcribing stereo telephone call recordings** using on-device AI powered by WhisperKit and Metal GPU acceleration. Perfect for call centers, customer support analysis, and telephone conversation documentation.

## ✨ Key Features

### 🎙️ **Dual-Channel Speaker Separation**
- Left and right audio channels processed separately to distinguish between two speakers
- Timeline visualization showing both speakers side-by-side
- Synchronized view with precise timestamps for each speaker

### 🚀 **On-Device Transcription**
- Privacy-focused processing using WhisperKit with Metal GPU acceleration
- No cloud services - everything runs locally on your Mac
- Real-Time Factor (RTF) tracking for transcription speed monitoring

### 📋 **Copy-to-Clipboard**
- Hover over any transcript segment to reveal copy button
- One-click copying of individual utterances
- Visual feedback with checkmark confirmation

### ⚙️ **Real-Time Configuration**
- Change settings without restarting transcription
- **Whisper Models**: Tiny, Base, Small, Medium, Large-v2, Large-v3
- **Languages**: Auto-detect, Russian, English
- **Base Context Prompt**: Provide domain/terminology context to improve accuracy (e.g., "Medical consultation" or "Technical support call")
- **Segmentation Methods**:
  - 7 VAD algorithms (Spectral, Adaptive, Standard)
  - Batch mode (fixed-size chunks)

### 🎚️ **Advanced Audio Controls**
- Variable speed playback (0.5× to 2.0×)
- Mono/Stereo toggle
- Volume boost (100% to 500%) for low-quality recordings
- Waveform scrubbing and visualization
- **Automatic audio device switching**: Seamlessly switches to available output when headphones unplugged

### 💾 **Multi-Format Export**
- **SRT** - SubRip subtitles with speaker labels
- **VTT** - WebVTT subtitles
- **TXT** - Plain text with optional timestamps
- **DOCX** - Microsoft Word document with formatting
- **JSON** - Structured data with full metadata

### 🎨 **Native macOS UI**
- Beautiful SwiftUI interface
- Dark mode support
- Responsive design
- Menu bar integration

## Installation

### Requirements
- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1, M2, M3, or later)
- Microphone permission (required by WhisperKit framework)

### Download

1. Download the latest release from [Releases](https://github.com/yourusername/TranscribeIt/releases)
2. Drag **TranscribeIt.app** to your Applications folder
3. Launch and grant microphone permission when prompted

### Building from Source

```bash
# Clone repository
git clone https://github.com/yourusername/TranscribeIt.git
cd TranscribeIt

# Build
swift build -c release

# Or build .app bundle
./build_app.sh
```

## Quick Start

### Transcribe a Single File

1. Launch TranscribeIt (menu bar icon appears)
2. Click menu bar icon → **Open File...**
3. Select your audio/video file
4. Transcription starts automatically with current settings
5. **Adjust settings in real-time** (click gear icon):
   - Change Whisper model (Tiny → Large)
   - Select language (Auto/Russian/English)
   - Add base context prompt for domain-specific terminology
   - Choose segmentation method (VAD algorithms or Batch mode)
   - Click **Retranscribe** to restart with new settings
6. Edit timestamps/text as needed
7. Copy individual segments (hover to reveal copy button)
8. Export to your preferred format

### Adjusting Transcription Settings

**In-Window Settings Panel** (click gear icon):

- **Whisper Model**: Choose between Tiny, Base, Small, Medium, Large-v2, Large-v3
- **Language**: Auto-detect, Russian, or English
- **Segmentation Method**:
  - **VAD Algorithms**:
    - Spectral (Telephone, Wideband, Default)
    - Adaptive (Low Quality, Aggressive)
    - Standard (Low Quality, High Quality)
  - **Batch Mode**: Fixed-size chunks (alternative to VAD)

Settings are saved automatically and apply immediately when you click **Retranscribe**.

### Dual-Channel Speaker Separation

1. Prepare stereo audio with Speaker 1 on left channel, Speaker 2 on right channel
2. Open file in TranscribeIt
3. Transcription automatically processes both channels separately
4. Timeline shows both speakers side-by-side with labels

## Usage Guide

### User Interface Overview

**Main Transcription Window**:
- **Top Bar**: File information and status indicators
  - Current Whisper model (e.g., "small")
  - Language (RU/EN/Auto with globe icon)
  - VAD/Batch mode indicator
  - Gear icon (click to open settings panel)
- **Timeline**: Dual-column view showing both speakers
  - Timestamps (editable)
  - Transcript text (editable)
  - Hover over any segment to reveal copy button
- **Waveform Player**: Audio visualization with playback controls
  - Click waveform to seek
  - Playback speed slider (0.5× - 2.0×)
  - Mono/Stereo toggle
  - Volume boost control

**Settings Panel** (gear icon):
- Model selection dropdown
- Language picker
- Segmentation method picker
- Retranscribe button

### Choosing a Whisper Model

| Model | Speed | Accuracy | RAM Usage | Recommended For |
|-------|-------|----------|-----------|-----------------|
| Tiny | Fastest | Good | ~1 GB | Quick drafts, testing |
| Base | Fast | Better | ~1.5 GB | General use, long files |
| Small | Medium | Very Good | ~2 GB | Balanced quality/speed |
| Medium | Slow | Excellent | ~5 GB | Professional work |
| Large | Slowest | Best | ~10 GB | Maximum accuracy |

First run downloads the selected model (~100MB-2GB depending on size).

### Keyboard Shortcuts

- **⌘O** - Open file
- **⌘B** - Batch import
- **⌘E** - Export current transcription
- **⌘,** - Settings
- **Space** - Play/Pause audio
- **⌘←/→** - Seek backward/forward 5 seconds

### Editing Transcriptions

- **Edit timestamps**: Click timestamp cell, type new value (format: `00:00.000`)
- **Edit text**: Click transcription cell, make changes
- **Copy segment**: Hover over any transcript segment to reveal copy button in top-right corner
  - Click to copy text to clipboard
  - Visual confirmation with checkmark icon
- **Jump to audio**: Click timestamp to seek audio to that position
- **Scrub audio**: Click waveform to jump to any position
- **Playback speed**: Use speed slider (0.5x - 2.0x)

### Custom Vocabulary

Add domain-specific terms to improve accuracy:

1. Open Settings (⌘,)
2. Navigate to **Vocabulary** tab
3. Select predefined dictionaries (VoIP, Telephony, Technical, Medical, etc.)
4. Add custom terms in the text field
5. Vocabulary applies to all future transcriptions

**Example custom terms**: MikoPBX, Asterisk, company names, technical jargon

## Advanced Features

### In-Window Settings Panel

Access transcription settings without leaving the main window:

1. Click the **gear icon** in the status bar
2. Change model, language, or segmentation method
3. Click **Retranscribe** to restart with new settings
4. Settings automatically saved for future sessions

**Status Bar Indicators**:
- **Model**: Shows current Whisper model (e.g., "small")
- **Language**: Globe icon with language code (RU/EN/Auto)
- **VAD/Batch**: Current segmentation method

### Segmentation Methods

**VAD (Voice Activity Detection)** - Automatically detects speech segments:
- **Spectral**: Frequency analysis
  - Telephone (8kHz optimized)
  - Wideband (16kHz optimized)
  - Default (balanced)
- **Adaptive**: Dynamic threshold adjustment
  - Low Quality (for noisy recordings)
  - Aggressive (fast detection)
- **Standard**: Traditional energy-based
  - Low Quality (relaxed thresholds)
  - High Quality (strict thresholds)

**Batch Mode** - Fixed-size chunks (alternative to VAD):
- Processes audio in fixed 30-second segments
- More predictable processing time
- Good for continuous speech without pauses

### Audio Normalization

Enabled by default. Automatically:
- Normalizes volume levels
- Reduces background noise
- Converts to optimal format for WhisperKit

Configure in application settings if working with pre-processed audio.

### Model Management

Manage downloaded Whisper models in Settings:
- View installed models with sizes and performance metrics
- Download additional models (tiny → large)
- Delete unused models to free disk space
- Switch models in real-time during transcription
- Models stored in `~/Library/Caches/whisperkit_models/`

## Performance Tips

### Optimize Transcription Speed
1. Use smaller Whisper model (tiny/base) for faster processing
2. Close other GPU-intensive applications
3. Ensure Mac is plugged in (performance mode)
4. Process shorter files in batches rather than very long files

### Improve Accuracy
1. Use larger Whisper model (medium/large-v3)
2. Select correct language instead of auto-detect
3. Choose appropriate VAD algorithm for your audio:
   - Telephone recordings → Spectral Telephone
   - High-quality audio → Standard High Quality
   - Noisy audio → Adaptive Low Quality
4. Add custom vocabulary for technical terms
5. Use dual-channel mode for multi-speaker recordings
6. Enable audio normalization for low-quality recordings

## Troubleshooting

### Transcription Quality Issues

**Problem**: Inaccurate transcriptions

**Solutions**:
- Click gear icon and try larger Whisper model (Medium/Large-v3)
- Select correct language (Russian/English) instead of Auto-detect
- Try different VAD algorithms for your audio type
- Add custom vocabulary for specialized terms in Settings → Vocabulary
- Check audio quality (clear speech, minimal background noise)
- Enable audio normalization

### Export Failures

**Problem**: Export fails or produces empty file

**Solutions**:
- Check write permissions for export folder
- Ensure sufficient disk space
- Try different export format
- Check logs: `log stream --predicate 'subsystem == "com.transcribeit.app"'`

### Model Download Issues

**Problem**: Whisper model fails to download

**Solutions**:
- Check internet connection
- Try smaller model first (tiny/base)
- Clear model cache: `~/Library/Caches/whisperkit_models/`
- Check Hugging Face availability (models hosted there)

### Audio Player Problems

**Problem**: Waveform not showing or playback stuttering

**Solutions**:
- Verify audio file format is supported
- Try re-encoding file to standard format (MP3/WAV)
- Check audio file isn't corrupted
- Restart TranscribeIt

**Problem**: Playback stops when headphones unplugged

**Solutions**:
- App automatically switches to laptop speakers - playback should resume automatically
- Check device status banner in audio player for connection state
- If status shows "unavailable", connect headphones or speakers
- Playback position is preserved during device changes

## Privacy & Security

### Data Privacy
- **100% On-Device Processing** - All transcription happens locally using WhisperKit
- **No Cloud Services** - No audio or transcriptions sent to external servers
- **No Analytics** - No usage tracking or data collection
- **Local Storage Only** - All files and models stored on your Mac

### Permissions
- **Microphone** - Required by WhisperKit framework (not actually used for recording in TranscribeIt)
- **File Access** - Only files you explicitly select for transcription

## Technical Details

### Architecture
- **Language**: Swift 5.9+
- **Minimum macOS**: 14.0 (Sonoma)
- **AI Engine**: WhisperKit 0.9.0+
- **GPU Acceleration**: Metal via MLX backend
- **Audio Framework**: AVFoundation

### Supported Audio Formats
- **Input**: MP3, M4A, WAV, AIFF, AAC, FLAC
- **Video**: MP4, MOV (audio track extracted)
- **Processing Format**: 16kHz mono Float32 (internal)

### File Locations
- **Application**: `/Applications/TranscribeIt.app`
- **Models Cache**: `~/Library/Caches/whisperkit_models/`
- **Settings**: `~/Library/Preferences/com.transcribeit.app.plist`
- **Logs**: viewable via Console.app (subsystem: `com.transcribeit.app`)

## Command-Line Interface

TranscribeIt supports batch transcription via CLI with JSON output.

### Basic Usage

```bash
# Transcribe single file
build/TranscribeIt.app/Contents/MacOS/TranscribeIt --batch audio.mp3 --json

# Transcribe multiple files
build/TranscribeIt.app/Contents/MacOS/TranscribeIt --batch file1.mp3 file2.mp3 --json

# Specify Whisper model
build/TranscribeIt.app/Contents/MacOS/TranscribeIt --batch audio.mp3 --model small --json

# Enable VAD for speaker separation
build/TranscribeIt.app/Contents/MacOS/TranscribeIt --batch call.mp3 --vad --json

# Process directory of files
build/TranscribeIt.app/Contents/MacOS/TranscribeIt --batch ~/Downloads/audio/*.mp3 --json > results.json
```

### CLI Options

| Option | Description |
|--------|-------------|
| `--batch <files...>` | Batch transcription mode (required) |
| `--json` | Output results as JSON (default) |
| `--gui` | Display results in GUI window |
| `--model <name>` | Whisper model: tiny, base, small, medium, large-v2, large-v3 |
| `--vad` | Enable VAD (speaker separation for stereo) |
| `--no-vad` | Disable VAD (plain text output) |

### JSON Output Format

```json
[
  {
    "file": "audio.mp3",
    "status": "success",
    "transcription": {
      "mode": "vad",
      "dialogue": [
        {"speaker": "Speaker 1", "timestamp": "00:12", "text": "Hello"},
        {"speaker": "Speaker 2", "timestamp": "00:15", "text": "Hi there"}
      ]
    },
    "metadata": {
      "model": "small",
      "vadEnabled": true,
      "duration": 45.2
    }
  }
]
```

For detailed CLI documentation, see [CLI_README.md](CLI_README.md).

## Development

### Building
```bash
swift build
```

### Running
```bash
.build/debug/TranscribeIt
```

### Testing
Place test audio files in `test_audio/` (gitignored):
```bash
mkdir test_audio
cp ~/Music/sample.mp3 test_audio/
```

### Debugging
View real-time logs:
```bash
log stream --predicate 'subsystem == "com.transcribeit.app"' --level debug
```

## Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## License

[Your License Here]

## Credits

- **WhisperKit** - On-device speech recognition (Argmax, Inc.)
- **OpenAI Whisper** - Base speech recognition model
- **Apple Metal** - GPU acceleration framework

## Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/TranscribeIt/issues)
- **Documentation**: [Wiki](https://github.com/yourusername/TranscribeIt/wiki)

---

**TranscribeIt** - Professional transcription, privately on your Mac.
