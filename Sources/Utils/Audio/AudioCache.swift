//
//  AudioCache.swift
//  TranscribeIt
//
//  Кэш для аудио данных для предотвращения множественной загрузки одного файла.
//
//  Проблема: аудио файл загружается 3 раза:
//  - FileTranscriptionService.loadAudio() для mono транскрипции
//  - FileTranscriptionService.loadAudioStereo() для stereo разделения каналов
//  - AudioPlayerManager.loadAudio() для воспроизведения
//
//  Решение: AudioCache кэширует загруженные аудио данные для повторного использования.
//

import Foundation
import AVFoundation

/// Actor для thread-safe кэширования аудио данных
///
/// Предотвращает избыточную загрузку одних и тех же аудио файлов.
/// Кэш автоматически очищается по возрасту и при переполнении.
///
/// ## Пример использования
/// ```swift
/// let cache = AudioCache()
/// let audio = try await cache.loadAudio(from: fileURL)
/// let samples = audio.monoSamples
/// let (left, right) = audio.stereoChannels ?? ([], [])
/// ```
public actor AudioCache {

    // MARK: - Cached Audio Structure

    /// Кэшированные аудио данные с метаданными
    public struct CachedAudio {
        /// Mono аудио samples (16kHz Float32)
        public let monoSamples: [Float]

        /// Stereo каналы: (left, right) или nil для mono файлов
        public let stereoChannels: (left: [Float], right: [Float])?

        /// Sample rate (всегда 16000 Hz после конвертации)
        public let sampleRate: Double

        /// Длительность аудио в секундах
        public let duration: TimeInterval

        /// Время загрузки в кэш
        public let loadedAt: Date

        /// Размер в байтах (для контроля памяти)
        public let sizeInBytes: Int

        /// Является ли файл стерео
        public let isStereo: Bool

        public init(
            monoSamples: [Float],
            stereoChannels: (left: [Float], right: [Float])?,
            sampleRate: Double = 16000,
            loadedAt: Date = Date(),
            isStereo: Bool = false
        ) {
            self.monoSamples = monoSamples
            self.stereoChannels = stereoChannels
            self.sampleRate = sampleRate
            self.duration = TimeInterval(monoSamples.count) / sampleRate
            self.loadedAt = loadedAt
            self.isStereo = isStereo

            // Вычисляем размер в памяти
            var size = monoSamples.count * MemoryLayout<Float>.size
            if let stereo = stereoChannels {
                size += (stereo.left.count + stereo.right.count) * MemoryLayout<Float>.size
            }
            self.sizeInBytes = size
        }
    }

    // MARK: - Cache Configuration

    /// Максимальный возраст кэша в секундах (5 минут)
    private let maxCacheAge: TimeInterval

    /// Максимальное количество файлов в кэше
    private let maxCacheSize: Int

    /// Максимальный размер кэша в байтах (500 MB)
    private let maxMemorySize: Int

    // MARK: - Private State

    /// Словарь кэшированных аудио по URL
    private var cache: [URL: CachedAudio] = [:]

    /// Очередь доступа для отслеживания LRU (Least Recently Used)
    private var accessOrder: [URL] = []

    // MARK: - Statistics

    /// Статистика кэша для мониторинга
    public struct CacheStatistics {
        public let hits: Int
        public let misses: Int
        public let evictions: Int
        public let currentSize: Int
        public let currentMemoryUsage: Int

        public var hitRate: Double {
            let total = hits + misses
            return total > 0 ? Double(hits) / Double(total) : 0
        }
    }

    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    private var cacheEvictions: Int = 0

    // MARK: - Initialization

    /// Инициализирует AudioCache с настройками
    /// - Parameters:
    ///   - maxCacheAge: Максимальный возраст кэша в секундах (по умолчанию 300 - 5 минут)
    ///   - maxCacheSize: Максимальное количество файлов (по умолчанию 3)
    ///   - maxMemorySize: Максимальный размер в байтах (по умолчанию 500 MB)
    public init(
        maxCacheAge: TimeInterval = 300,
        maxCacheSize: Int = 3,
        maxMemorySize: Int = 500 * 1024 * 1024
    ) {
        self.maxCacheAge = maxCacheAge
        self.maxCacheSize = maxCacheSize
        self.maxMemorySize = maxMemorySize
    }

    // MARK: - Public API

    /// Загружает аудио из кэша или с диска
    /// - Parameter url: URL аудио файла
    /// - Returns: Кэшированные аудио данные
    /// - Throws: Ошибки загрузки аудио
    public func loadAudio(from url: URL) async throws -> CachedAudio {
        // Проверяем кэш
        if let cached = cache[url] {
            // Проверяем возраст
            if Date().timeIntervalSince(cached.loadedAt) < maxCacheAge {
                // Cache hit
                cacheHits += 1
                updateAccessOrder(for: url)
                return cached
            } else {
                // Истек срок кэша
                cache.removeValue(forKey: url)
                accessOrder.removeAll { $0 == url }
            }
        }

        // Cache miss - загружаем с диска
        cacheMisses += 1
        let audio = try await loadFromDisk(url)

        // Добавляем в кэш
        cache[url] = audio
        accessOrder.append(url)

        // Очищаем старый кэш при необходимости
        await evictIfNeeded()

        return audio
    }

    /// Проверяет, есть ли файл в кэше
    /// - Parameter url: URL файла
    /// - Returns: true если файл в кэше и не устарел
    public func isCached(_ url: URL) -> Bool {
        guard let cached = cache[url] else {
            return false
        }
        return Date().timeIntervalSince(cached.loadedAt) < maxCacheAge
    }

    /// Очищает весь кэш
    public func clearCache() {
        cache.removeAll()
        accessOrder.removeAll()
        cacheEvictions += cache.count
    }

    /// Удаляет конкретный файл из кэша
    /// - Parameter url: URL файла для удаления
    public func evict(_ url: URL) {
        if cache.removeValue(forKey: url) != nil {
            accessOrder.removeAll { $0 == url }
            cacheEvictions += 1
        }
    }

    /// Возвращает статистику использования кэша
    /// - Returns: Структура со статистикой
    public func getStatistics() -> CacheStatistics {
        let memoryUsage = cache.values.reduce(0) { $0 + $1.sizeInBytes }
        return CacheStatistics(
            hits: cacheHits,
            misses: cacheMisses,
            evictions: cacheEvictions,
            currentSize: cache.count,
            currentMemoryUsage: memoryUsage
        )
    }

    /// Сбрасывает статистику кэша
    public func resetStatistics() {
        cacheHits = 0
        cacheMisses = 0
        cacheEvictions = 0
    }

    // MARK: - Private Methods

    /// Загружает аудио с диска и конвертирует в оба формата (mono + stereo)
    private func loadFromDisk(_ url: URL) async throws -> CachedAudio {
        let asset = AVAsset(url: url)

        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "AudioCache", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No audio track found in file: \(url.lastPathComponent)"
            ])
        }

        // Определяем количество каналов
        let formatDescriptions = try await audioTrack.load(.formatDescriptions)
        let channelCount: Int
        if let formatDescription = formatDescriptions.first {
            let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
            channelCount = Int(audioStreamBasicDescription?.pointee.mChannelsPerFrame ?? 1)
        } else {
            channelCount = 1
        }

        let isStereo = channelCount >= 2

        // Загружаем stereo данные для максимальной гибкости
        let stereoSamples = try await loadStereoFromDisk(url: url, asset: asset, track: audioTrack)

        // Извлекаем mono (микс обоих каналов или первый канал)
        let monoSamples = extractMono(from: stereoSamples)

        // Извлекаем stereo каналы если файл стерео
        let stereoChannels: (left: [Float], right: [Float])? = isStereo ?
            (extractChannel(from: stereoSamples, channel: 0), extractChannel(from: stereoSamples, channel: 1)) : nil

        return CachedAudio(
            monoSamples: monoSamples,
            stereoChannels: stereoChannels,
            isStereo: isStereo
        )
    }

    /// Загружает stereo аудио с диска
    private func loadStereoFromDisk(url: URL, asset: AVAsset, track: AVAssetTrack) async throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)

        // Настройки: 16kHz, stereo, Float32
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)

        guard reader.startReading() else {
            throw NSError(domain: "AudioCache", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to start reading audio file"
            ])
        }

        var audioSamples: [Float] = []

        while let sampleBuffer = output.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = Data(count: length)

                _ = data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
                }

                let floatArray = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> [Float] in
                    let floatPtr = ptr.bindMemory(to: Float.self)
                    return Array(floatPtr)
                }

                audioSamples.append(contentsOf: floatArray)
            }
        }

        reader.cancelReading()
        return audioSamples
    }

    /// Извлекает mono (микс обоих каналов)
    private func extractMono(from interleavedSamples: [Float]) -> [Float] {
        var monoSamples: [Float] = []
        monoSamples.reserveCapacity(interleavedSamples.count / 2)

        for i in stride(from: 0, to: interleavedSamples.count, by: 2) {
            if i + 1 < interleavedSamples.count {
                // Микс левого и правого канала
                let mixed = (interleavedSamples[i] + interleavedSamples[i + 1]) / 2.0
                monoSamples.append(mixed)
            } else {
                // Последний sample (если нечетное количество)
                monoSamples.append(interleavedSamples[i])
            }
        }

        return monoSamples
    }

    /// Извлекает один канал из interleaved stereo
    private func extractChannel(from interleavedSamples: [Float], channel: Int) -> [Float] {
        var channelSamples: [Float] = []
        channelSamples.reserveCapacity(interleavedSamples.count / 2)

        for i in stride(from: channel, to: interleavedSamples.count, by: 2) {
            channelSamples.append(interleavedSamples[i])
        }

        return channelSamples
    }

    /// Обновляет очередь доступа для LRU
    private func updateAccessOrder(for url: URL) {
        accessOrder.removeAll { $0 == url }
        accessOrder.append(url)
    }

    /// Удаляет старые записи если превышены лимиты
    private func evictIfNeeded() async {
        // Проверяем количество файлов
        while cache.count > maxCacheSize {
            evictOldest()
        }

        // Проверяем размер памяти
        var totalSize = cache.values.reduce(0) { $0 + $1.sizeInBytes }
        while totalSize > maxMemorySize && !cache.isEmpty {
            evictOldest()
            totalSize = cache.values.reduce(0) { $0 + $1.sizeInBytes }
        }
    }

    /// Удаляет самую старую запись (LRU)
    private func evictOldest() {
        guard let oldestURL = accessOrder.first else {
            return
        }

        cache.removeValue(forKey: oldestURL)
        accessOrder.removeFirst()
        cacheEvictions += 1
    }
}
