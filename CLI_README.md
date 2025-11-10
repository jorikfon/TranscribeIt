# TranscribeIt CLI Mode

TranscribeIt поддерживает пакетную транскрибацию из командной строки с выводом результатов в JSON или GUI.

## Использование

### Базовый запуск (JSON вывод)

```bash
# Транскрибация одного файла
build/TranscribeIt.app/Contents/MacOS/TranscribeIt --batch audio.mp3 --json

# Транскрибация нескольких файлов
build/TranscribeIt.app/Contents/MacOS/TranscribeIt --batch file1.mp3 file2.mp3 file3.mp3 --json
```

### Вывод результатов в GUI

```bash
build/TranscribeIt.app/Contents/MacOS/TranscribeIt --batch audio.mp3 --gui
```

### Указание модели Whisper

```bash
# Использовать модель "small"
build/TranscribeIt.app/Contents/MacOS/TranscribeIt --batch audio.mp3 --model small --json

# Доступные модели: tiny, base, small, medium, large-v2, large-v3
```

### Включение VAD (разделение по спикерам)

```bash
# С VAD для стерео записей телефонных разговоров
build/TranscribeIt.app/Contents/MacOS/TranscribeIt --batch call.mp3 --vad --json

# Без VAD (простой текст)
build/TranscribeIt.app/Contents/MacOS/TranscribeIt --batch call.mp3 --no-vad --json
```

### Пакетная обработка всех файлов в директории

```bash
# Транскрибация всех MP3 файлов
build/TranscribeIt.app/Contents/MacOS/TranscribeIt --batch ~/Downloads/audio/*.mp3 --json > results.json
```

## Формат JSON вывода

```json
[
  {
    "file": "audio.mp3",
    "status": "success",
    "transcription": {
      "mode": "vad",
      "dialogue": [
        {
          "speaker": "Speaker 1",
          "timestamp": "00:12",
          "text": "Здравствуйте"
        },
        {
          "speaker": "Speaker 2",
          "timestamp": "00:15",
          "text": "Добрый день"
        }
      ],
      "text": null
    },
    "error": null,
    "metadata": {
      "model": "small",
      "vadEnabled": true,
      "duration": 45.2,
      "audioFileSize": 1234567
    }
  }
]
```

## Опции

| Опция | Описание |
|-------|----------|
| `--batch <files...>` | Пакетная транскрибация (обязательно) |
| `--json` | Вывод результатов в JSON (по умолчанию) |
| `--gui` | Показать результаты в GUI окне |
| `--model <name>` | Whisper модель: tiny, base, small, medium, large-v2, large-v3 |
| `--vad` | Включить VAD (разделение по спикерам для стерео) |
| `--no-vad` | Отключить VAD (простой текст) |

## Примеры использования

### Пример 1: Транскрибация телефонного разговора

```bash
build/TranscribeIt.app/Contents/MacOS/TranscribeIt \
  --batch /Users/nb/Downloads/monitor/2025/10/17/14/transfer_*.mp3 \
  --model small \
  --vad \
  --json > transcriptions.json
```

### Пример 2: Быстрая транскрибация с маленькой моделью

```bash
build/TranscribeIt.app/Contents/MacOS/TranscribeIt \
  --batch recording.mp3 \
  --model tiny \
  --json
```

### Пример 3: Обработка с выводом в GUI

```bash
build/TranscribeIt.app/Contents/MacOS/TranscribeIt \
  --batch interview.mp3 \
  --model medium \
  --gui
```

## Логи

Логи приложения можно просмотреть через macOS Console:

```bash
# Real-time stream
log stream --predicate 'subsystem == "com.transcribeit.app"'

# Только ошибки
log stream --predicate 'subsystem == "com.transcribeit.app" AND eventType >= logEventType.error'

# Категория batch
log stream --predicate 'subsystem == "com.transcribeit.app" AND category == "batch"'
```

## Обработка ошибок

Если транскрибация файла не удалась, результат содержит информацию об ошибке:

```json
{
  "file": "corrupted.mp3",
  "status": "error",
  "transcription": null,
  "error": "Failed to load audio file",
  "metadata": {
    "model": "small",
    "vadEnabled": false,
    "duration": 0.5,
    "audioFileSize": 0
  }
}
```

## Производительность

- **tiny**: ~40 MB, очень быстро, базовая точность
- **base**: ~75 MB, очень быстро, нормальная точность
- **small**: ~250 MB, быстро, хорошая точность (рекомендуется)
- **medium**: ~770 MB, средне, отличная точность
- **large-v2/v3**: ~3 GB, медленно, максимальная точность

## Создание алиаса для удобства

```bash
# Добавьте в ~/.zshrc или ~/.bashrc:
alias transcribe='~/path/to/TranscribeIt.app/Contents/MacOS/TranscribeIt --batch'

# Использование:
transcribe audio.mp3 --json
transcribe *.mp3 --model small --vad --json > results.json
```
