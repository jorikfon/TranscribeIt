# TranscribeIt

Professional audio and video transcription application for macOS, optimized for Apple Silicon (M1/M2/M3).

## Features

### Core Functionality
- **Batch File Processing** - Transcribe multiple audio/video files simultaneously
- **Multi-Format Support** - MP3, M4A, WAV, AIFF, AAC, FLAC, MP4, MOV
- **On-Device Processing** - Complete privacy with local WhisperKit AI (no cloud services)
- **Metal GPU Acceleration** - Optimized for Apple Silicon performance

### Advanced Transcription
- **Dual-Channel Mode** - Automatic speaker separation for stereo recordings
- **Multiple Whisper Models** - Choose from tiny, base, small, medium, or large models
- **Custom Vocabulary** - Add domain-specific terms for improved accuracy
- **Audio Normalization** - Automatic preprocessing for optimal quality

### Professional Editing
- **Waveform Visualization** - See audio alongside transcription
- **Editable Timestamps** - Adjust timing for perfect synchronization
- **Inline Text Editing** - Correct transcription errors before export
- **Audio Player Integration** - Click timestamps to jump to exact audio position

### Export Formats
- **SRT** - SubRip subtitles (`.srt`)
- **VTT** - WebVTT subtitles (`.vtt`)
- **TXT** - Plain text with optional timestamps (`.txt`)
- **DOCX** - Microsoft Word document (`.docx`)
- **JSON** - Structured data with metadata (`.json`)

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
4. Wait for transcription to complete
5. Edit timestamps/text as needed
6. Export to your preferred format

### Batch Transcription

1. Click menu bar icon → **Batch Import...**
2. Select multiple files
3. Files are processed in queue
4. Each completed transcription opens in its own window
5. Edit and export individually

### Dual-Channel Speaker Separation

1. Prepare stereo audio with Speaker 1 on left channel, Speaker 2 on right channel
2. Open file in TranscribeIt
3. Enable **Dual-Channel Mode** in settings
4. Transcription will show speaker labels automatically

## Usage Guide

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
- **Jump to audio**: Click timestamp to seek audio to that position
- **Scrub audio**: Click waveform to jump to any position
- **Playback speed**: Use speed slider (0.5x - 2.0x)

### Custom Vocabulary

Add domain-specific terms to improve accuracy:

1. Open Settings
2. Navigate to **Vocabulary** tab
3. Add custom words/phrases
4. Choose correction rules
5. Vocabulary applies to all future transcriptions

## Advanced Features

### Audio Normalization

Enabled by default. Automatically:
- Normalizes volume levels
- Reduces background noise
- Converts to optimal format for WhisperKit

Disable in Settings if working with pre-processed audio.

### Auto-Export

Enable in Settings to automatically export transcriptions upon completion:
1. Choose default export format
2. Select destination folder
3. Enable **Auto-Export on Completion**

### Model Management

Manage downloaded Whisper models:
- View installed models and sizes
- Download additional models
- Delete unused models to free space
- Models stored in `~/Library/Caches/whisperkit_models/`

## Performance Tips

### Optimize Transcription Speed
1. Use smaller Whisper model (tiny/base) for faster processing
2. Close other GPU-intensive applications
3. Ensure Mac is plugged in (performance mode)
4. Process shorter files in batches rather than very long files

### Improve Accuracy
1. Use larger Whisper model (medium/large)
2. Ensure high-quality audio (16kHz+ sample rate, clear speech)
3. Add custom vocabulary for technical terms
4. Use dual-channel mode for multi-speaker recordings
5. Enable audio normalization for low-quality recordings

## Troubleshooting

### Transcription Quality Issues

**Problem**: Inaccurate transcriptions

**Solutions**:
- Try larger Whisper model (Settings → Model → Medium/Large)
- Add custom vocabulary for specialized terms
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
