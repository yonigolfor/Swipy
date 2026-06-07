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

    /// Returns a snapshot of all sanitized asset IDs currently on disk.
    /// Reads the cache directory exactly once — O(n) on disk, then O(1) per lookup.
    /// Callers own the returned Set for the duration of their scan; the Service
    /// holds no reference to it, so it is freed as soon as the caller releases it.
    /// Uses .skipsHiddenFiles to ignore .DS_Store and similar system entries.
    ///
    /// The sanitized form matches fileURL(for:) exactly:
    ///   assetID.replacingOccurrences(of: "/", with: "_") → filename (no extension)
    /// Callers must apply the same transformation before calling contains(_:).
    func cachedAssetIDSet() -> Set<String> {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }
        return Set(urls.map { $0.deletingPathExtension().lastPathComponent })
    }

    /// Async variant — runs the file read on ioQueue so the caller's actor
    /// (typically @MainActor) is never blocked by disk I/O.
    func retrieveAsync(for assetID: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            ioQueue.async { [self] in
                continuation.resume(returning: retrieve(for: assetID))
            }
        }
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
