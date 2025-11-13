# TranscribeIt Tests

Этот каталог содержит unit-тесты и integration тесты для проекта TranscribeIt.

## Структура

```
Tests/
├── TranscribeItCoreTests.swift       # Базовые smoke-тесты
├── Utils/                            # Тесты утилит
│   ├── Timeline/                     # Тесты TimelineMapper
│   ├── VAD/                          # Тесты VAD алгоритмов
│   └── Audio/                        # Тесты AudioNormalizer, AudioCache
├── Services/                         # Тесты сервисов
│   ├── WhisperServiceTests.swift
│   ├── FileTranscriptionServiceTests.swift
│   └── BatchTranscriptionServiceTests.swift
├── UI/                               # Тесты UI компонентов
│   └── ViewModels/                   # Тесты ViewModel
├── Integration/                      # Integration тесты
│   └── TranscriptionIntegrationTests.swift
└── Mocks/                            # Mock-реализации для тестирования
    ├── MockVocabularyManager.swift
    ├── MockUserSettings.swift
    └── MockModelManager.swift
```

## Запуск тестов

### Все тесты
```bash
swift test
```

### Конкретный тест
```bash
swift test --filter TranscribeItCoreTests
```

### С verbose выводом
```bash
swift test --verbose
```

## Конфигурация

Test Target настроен в `Package.swift`:
- **Имя:** TranscribeItCoreTests
- **Зависимости:** TranscribeItCore, WhisperKit
- **Путь:** Tests/

## Требования

- macOS 14.0+
- Swift 5.9+
- Xcode 15.0+

## Test Coverage

Цель проекта - достичь >60% покрытия core логики unit-тестами:

- ✅ Базовая инфраструктура тестов
- ⬜ TimelineMapper (приоритет: P1)
- ⬜ VAD алгоритмы (приоритет: P1)
- ⬜ AudioNormalizer (приоритет: P2)
- ⬜ ViewModel (приоритет: P2)
- ⬜ Integration тесты (приоритет: P3)

## Примечания

- Все тесты должны быть независимыми и воспроизводимыми
- Для зависимостей использовать mock-реализации из `Tests/Mocks/`
- Избегать реальной загрузки WhisperKit моделей в unit-тестах
- Integration тесты могут использовать реальные файлы из `test_audio/` (не в git)

## CI/CD

В будущем планируется добавить GitHub Actions для автоматического запуска тестов при каждом push.
