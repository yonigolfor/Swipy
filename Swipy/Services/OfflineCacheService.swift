//
//  OfflineCacheService.swift
//  Swipy
//
//  Disk cache for offline pre-fetched photos.
//  Max 500 MB. Evicts oldest entries when cap is exceeded.
//  All file I/O is confined to ioQueue — never touches main thread.
//

import UIKit

final class OfflineCacheService {
    static let shared = OfflineCacheService()

    private let maxCacheSizeBytes: Int = 500 * 1024 * 1024  // 500 MB
    private let ioQueue = DispatchQueue(label: "com.swipy.offlinecache", qos: .utility)

    private var cacheDirectory: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflinePhotoCache", isDirectory: true)
    }

    private init() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            try? FileManager.default.createDirectory(at: cacheDirectory,
                                                     withIntermediateDirectories: true)
        }
    }

    // MARK: - Public API

    func store(image: UIImage, for assetID: String) {
        ioQueue.async { [weak self] in
            guard let self,
                  let data = image.jpegData(compressionQuality: 0.85) else { return }
            try? data.write(to: fileURL(for: assetID), options: .atomic)
            enforceMaxSize()
        }
    }

    /// Synchronous read — fast for local Caches files. Safe to call from any thread.
    func retrieve(for assetID: String) -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL(for: assetID)) else { return nil }
        return UIImage(data: data)
    }

    func evict(for assetID: String) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            try? FileManager.default.removeItem(at: fileURL(for: assetID))
        }
    }

    func evictAll() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            try? FileManager.default.removeItem(at: cacheDirectory)
            try? FileManager.default.createDirectory(at: cacheDirectory,
                                                     withIntermediateDirectories: true)
        }
    }

    // MARK: - Private

    private func fileURL(for assetID: String) -> URL {
        let safe = assetID.replacingOccurrences(of: "/", with: "_")
        return cacheDirectory.appendingPathComponent("\(safe).jpg")
    }

    /// Deletes oldest files until total size is within maxCacheSizeBytes.
    private func enforceMaxSize() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .creationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: Array(keys)
        ) else { return }

        var totalSize = 0
        var entries: [(url: URL, date: Date, size: Int)] = []

        for url in urls {
            guard let res = try? url.resourceValues(forKeys: keys) else { continue }
            let size = res.fileSize ?? 0
            let date = res.creationDate ?? .distantPast
            totalSize += size
            entries.append((url, date, size))
        }

        guard totalSize > maxCacheSizeBytes else { return }
        entries.sort { $0.date < $1.date }

        for entry in entries {
            try? FileManager.default.removeItem(at: entry.url)
            totalSize -= entry.size
            if totalSize <= maxCacheSizeBytes { break }
        }
    }
}
