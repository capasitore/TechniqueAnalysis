//
//  CacheManager.swift
//  TechniqueAnalysis_Example
//
//  Created by Trevor on 05.02.19.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import Foundation
import TechniqueAnalysis

class CacheManager {

    // MARK: - Properties

    /// Shared Singleton Instance
    static let shared = CacheManager()

    private(set) var cache: [CompressedTimeseries]
    private var processingQueue = [(url: URL, meta: Meta)]()
    private let processor: VideoProcessor?

    private static let cachedTimeseriesExtension = "ts"

    private static let cacheDirectory: String? = {
        return try? FileManager.default.url(for: .documentDirectory,
                                            in: .allDomainsMask,
                                            appropriateFor: nil,
                                            create: true).appendingPathComponent("timeseries_cache",
                                                                                 isDirectory: true).relativePath
    }()

    // MARK: - Initialization

    private init() {
        if let directory = CacheManager.cacheDirectory {
            try? FileManager.default.createDirectory(at: URL(fileURLWithPath: directory, isDirectory: true),
                                                     withIntermediateDirectories: true,
                                                     attributes: nil)
        }

        self.cache = CacheManager.retrieveCache()

        do {
            self.processor = try VideoProcessor(sampleLength: 5, insetPercent: 0.1, fps: 25, modelType: .cpm)
        } catch {
            print("Error while initializing VideoProcessor in CacheManager: \(error)")
            self.processor = nil
        }
    }

    // MARK: - Exposed Functions

    func cache(_ compressedTimeseries: CompressedTimeseries) -> Bool {
        let encoder = JSONEncoder()
        guard let directory = CacheManager.cacheDirectory,
            let data = try? encoder.encode(compressedTimeseries) else {
                return false
        }

        let filename = FileNamer.dataFileName(from: compressedTimeseries.meta,
                                              ext: CacheManager.cachedTimeseriesExtension)
        let filePath = URL(fileURLWithPath: directory,
                          isDirectory: true).appendingPathComponent(filename, isDirectory: false).relativePath

        _ = try? FileManager.default.removeItem(atPath: filePath)

        FileManager.default.createFile(atPath: filePath,
                                       contents: data,
                                       attributes: [:])
        cache.append(compressedTimeseries)
        return true
    }

    func processUncachedLabeledVideos(onItemProcessed: @escaping ((Int, Int) -> Void),
                                      onFinish: @escaping (() -> Void),
                                      onError: @escaping ((String) -> Void)) {
        guard processingQueue.isEmpty else {
            onError("CacheManager is already processing videos, please wait!")
            return
        }

        let labeledVideos = VideoManager.shared.labeledVideos
        let toProcess = labeledVideos.filter { !cache(contains: $0.meta) }

        if toProcess.isEmpty {
            onFinish()
            return
        }

        self.processingQueue = toProcess
        processNext(originalSize: toProcess.count, onItemProcessed: onItemProcessed, onFinish: onFinish)
    }

    // MARK: - Private Functions

    private func cache(contains meta: Meta) -> Bool {
        return cache.contains(where: { cachedSeries -> Bool in
            cachedSeries.meta.exerciseName == meta.exerciseName &&
                cachedSeries.meta.exerciseDetail == meta.exerciseDetail &&
                cachedSeries.meta.angle == meta.angle &&
                cachedSeries.meta.isLabeled == meta.isLabeled
        })
    }

    private func processNext(originalSize: Int,
                             onItemProcessed: @escaping ((Int, Int) -> Void),
                             onFinish: @escaping (() -> Void)) {
        guard let next = processingQueue.popLast(),
            let processor = processor else {
                onFinish()
                return
        }

        processor.makeCompressedTimeseries(videoURL: next.url,
                                           meta: next.meta,
                                           onFinish: { results in
                                            for compressedSeries in results {
                                                _ = self.cache(compressedSeries)
                                            }

                                            if self.processingQueue.isEmpty {
                                                onFinish()
                                            } else {
                                                onItemProcessed(originalSize - self.processingQueue.count, originalSize)
                                                self.processNext(originalSize: originalSize,
                                                                 onItemProcessed: onItemProcessed,
                                                                 onFinish: onFinish)
                                            }
        },
                                           onFailure: { _ in })
    }

    private static func retrieveCache() -> [CompressedTimeseries] {
        guard let directory = cacheDirectory,
            let cachedFilenames = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
                return []
        }

        var decodedSeries = [CompressedTimeseries]()
        let decoder = JSONDecoder()

        for filename in cachedFilenames {
            let fileURL = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(filename)

            guard FileNamer.fileExtension(filename) == cachedTimeseriesExtension,
                let data = try? Data(contentsOf: fileURL),
                let decoded = try? decoder.decode(CompressedTimeseries.self, from: data) else {
                    continue
            }

            decodedSeries.append(decoded)
        }

        return decodedSeries
    }

}