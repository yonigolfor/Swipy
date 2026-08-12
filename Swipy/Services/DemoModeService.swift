//
//  DemoModeService.swift
//  Swipy
//
//  DEMO BRANCH ONLY — not meant to reach main. Imports the bundled
//  Assets.xcassets/Demo/<session> images (and Resources/*.mov videos) into Photos once per
//  session, so they become real PHAssets and flow through the existing card pipeline
//  (PhotoItem/PhotoLibraryService/CardStackView) completely unchanged. Delete this file
//  (and its two call sites in SwipeStackView.swift and PhotoStackViewModel.swift) before
//  merging back to main.
//

import Photos
import UIKit

enum DemoModeService {
    /// A single demo item — either an Assets.xcassets imageset name, or a video bundled as
    /// a plain resource file (PBXFileSystemSynchronizedRootGroup picks up Swipy/Resources/*
    /// automatically, same as everything else under Swipy/).
    enum DemoAsset {
        case image(name: String)
        case video(resource: String, ext: String)

        /// Stable identity used as the identifier cache key — independent of display
        /// order, so reordering session.assets (or adding new items later) never forces a
        /// re-import of items that are already in Photos.
        var cacheKey: String {
            switch self {
            case .image(let name): return name
            case .video(let resource, _): return resource
            }
        }
    }

    /// A named set of bundled demo items (Assets.xcassets/Demo/<case>/).
    enum DemoSession: String {
        case demo1
        case demo2

        var assets: [DemoAsset] {
            switch self {
            case .demo1:
                return ["DemoPhoto1", "DemoPhoto2", "DemoPhoto3", "DemoPhoto4", "DemoPhoto5", "DemoPhoto6"]
                    .map { .image(name: $0) }
            case .demo2:
                let photos = (1...15).map { DemoAsset.image(name: "Demo2Photo\($0)") }
                // Video lands right after Demo2Photo4 (the red maple tree).
                var ordered = Array(photos.prefix(4))
                ordered.append(.video(resource: "Demo2Video1", ext: "mov"))
                ordered.append(contentsOf: photos.suffix(from: 4))
                return ordered
            }
        }

        /// Each session gets its own UserDefaults key so both can be imported into Photos
        /// independently and idempotently — switching activeSession never re-imports or
        /// loses track of the other session's already-imported assets.
        var identifiersKey: String { "demoAssetIdentifierCache_\(rawValue)" }
    }

    /// Toggle this to switch which preset the shake gesture restages. Change and rebuild
    /// to switch demo video scenarios.
    static var activeSession: DemoSession = .demo2

    /// Resolves the active session's demo PHAssets, in session.assets' order, importing
    /// only whatever isn't already cached. Every later call (each shake) just re-fetches
    /// the same assets by their stored localIdentifier — nothing is re-imported.
    static func loadDemoAssets(completion: @escaping ([PHAsset]) -> Void) {
        let session = activeSession
        let authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let cache = (UserDefaults.standard.dictionary(forKey: session.identifiersKey) as? [String: String]) ?? [:]
        print("[Demo] authStatus=\(authStatus.rawValue) cachedCount=\(cache.count)/\(session.assets.count)")
        if let ordered = orderedAssets(for: session, cache: cache) {
            print("[Demo] serving \(ordered.count) cached asset(s)")
            completion(ordered)
            return
        }
        importAndLoad(session: session, cache: cache, completion: completion)
    }

    /// Resolves every item in session.assets to a PHAsset via the cache, preserving
    /// session.assets' order. Returns nil if anything is missing from the cache (needs
    /// importing) or a cached localIdentifier no longer resolves to a real PHAsset.
    private static func orderedAssets(for session: DemoSession, cache: [String: String]) -> [PHAsset]? {
        let ids = session.assets.map { cache[$0.cacheKey] }
        guard ids.allSatisfy({ $0 != nil }) else { return nil }
        let nonNilIDs = ids.compactMap { $0 }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: nonNilIDs, options: nil)
        var byID: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        let assets = nonNilIDs.compactMap { byID[$0] }
        return assets.count == nonNilIDs.count ? assets : nil
    }

    private static func importAndLoad(session: DemoSession, cache: [String: String], completion: @escaping ([PHAsset]) -> Void) {
        // A cache entry alone isn't enough — the localIdentifier it points to may no
        // longer resolve (e.g. the demo asset was deleted from Photos directly), so treat
        // that the same as never having been imported and re-create it.
        var resolvedIDs: Set<String> = []
        let cachedIDs = Array(Set(cache.values))
        if !cachedIDs.isEmpty {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: cachedIDs, options: nil)
            result.enumerateObjects { asset, _, _ in resolvedIDs.insert(asset.localIdentifier) }
        }
        let missing = session.assets.filter { asset in
            guard let id = cache[asset.cacheKey] else { return true }
            return !resolvedIDs.contains(id)
        }
        print("[Demo] importing \(missing.count) missing asset(s): \(missing.map { $0.cacheKey })")
        var placeholders: [String: PHObjectPlaceholder] = [:]
        PHPhotoLibrary.shared().performChanges({
            for asset in missing {
                switch asset {
                case .image(let name):
                    guard let image = UIImage(named: name) else {
                        print("[Demo] ⚠️ UIImage(named: \(name)) returned nil — check it's in Assets.xcassets")
                        continue
                    }
                    if let placeholder = PHAssetChangeRequest.creationRequestForAsset(from: image).placeholderForCreatedAsset {
                        placeholders[asset.cacheKey] = placeholder
                    }
                case .video(let resource, let ext):
                    guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
                        print("[Demo] ⚠️ Bundle.main.url(forResource: \(resource), withExtension: \(ext)) returned nil — not bundled")
                        continue
                    }
                    guard let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) else {
                        print("[Demo] ⚠️ creationRequestForAssetFromVideo failed for \(url)")
                        continue
                    }
                    if let placeholder = request.placeholderForCreatedAsset {
                        placeholders[asset.cacheKey] = placeholder
                    }
                }
            }
        }, completionHandler: { success, error in
            guard success else {
                print("[Demo] ⚠️ performChanges failed: \(error?.localizedDescription ?? "unknown error")")
                DispatchQueue.main.async { completion([]) }
                return
            }
            print("[Demo] performChanges succeeded, created \(placeholders.count)/\(missing.count) placeholder(s)")
            var updatedCache = cache
            for (key, placeholder) in placeholders {
                updatedCache[key] = placeholder.localIdentifier
            }
            UserDefaults.standard.set(updatedCache, forKey: session.identifiersKey)
            let ordered = orderedAssets(for: session, cache: updatedCache) ?? []
            print("[Demo] resolved \(ordered.count)/\(session.assets.count) final asset(s)")
            DispatchQueue.main.async { completion(ordered) }
        })
    }
}
