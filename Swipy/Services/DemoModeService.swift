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

    /// The 3 sneak-peek items shown *first* on a Shuffle tap, ahead of Demo1's 6 images
    /// below — a personal pelican/tree/beach set, distinct from either demo1 or demo2's
    /// own session content.
    private static let shuffleSneakPeekAssets: [DemoAsset] = [
        .video(resource: "ShuffleBeach", ext: "mov"),
        .image(name: "ShufflePelican"),
        .image(name: "ShuffleTree"),
    ]

    /// Shuffle-only demo bucket — the 3 sneak-peek items above, followed by Demo1's 6
    /// already-bundled images. Own dedicated cache key (not demo1's own) since the
    /// bucket's content no longer matches demo1's asset list 1:1.
    private static let demoShuffleAssets: [DemoAsset] = shuffleSneakPeekAssets + DemoSession.demo1.assets
    private static let demoShuffleIdentifiersKey = "demoAssetIdentifierCache_shuffle"

    /// True once a shake has successfully loaded the active session's demo items at
    /// least once this run. Gates the shuffle-demo sneak-peek (`PhotoStackViewModel
    /// .pinDemoShuffleAssets`) and its fake "August 2023" landing label — pressing
    /// Shuffle before ever shaking behaves 100% normally (real random date, no pinned
    /// items), so the trick only kicks in mid-recording, after demo2 is already staged.
    private(set) static var shakeDemoLoaded = false

    /// Resolves the active session's demo PHAssets, in session.assets' order, importing
    /// only whatever isn't already cached. Every later call (each shake) just re-fetches
    /// the same assets by their stored localIdentifier — nothing is re-imported.
    static func loadDemoAssets(completion: @escaping ([PHAsset]) -> Void) {
        let session = activeSession
        loadAssets(session.assets, cacheKey: session.identifiersKey) { assets in
            if !assets.isEmpty { shakeDemoLoaded = true }
            completion(assets)
        }
    }

    /// Same idempotent import/cache mechanism as `loadDemoAssets`, but for the fixed
    /// shuffle-only bucket (Demo1's images) regardless of which session is active.
    static func loadDemoShuffleAssets(completion: @escaping ([PHAsset]) -> Void) {
        loadAssets(demoShuffleAssets, cacheKey: demoShuffleIdentifiersKey, completion: completion)
    }

    /// Fire-and-forget: imports (if needed) the shuffle demo images and decodes them
    /// straight into PhotoLibraryService's card NSCache ahead of time, so pinning them
    /// on a Shuffle tap later is a synchronous cache hit — zero visible loading. Safe to
    /// call more than once (e.g. every shake); `requestCardImage` results just get re-cached.
    /// `onResolved` hands back the resolved assets so the caller can react (e.g. excluding
    /// them from the main linear stack — see `PhotoStackViewModel.excludeFromMainStack`)
    /// without making a second, independent `loadDemoShuffleAssets` call — two concurrent
    /// calls on a cold cache would race and could double-import the same 6 assets.
    static func prewarmDemoShuffleAssets(onResolved: (([PHAsset]) -> Void)? = nil) {
        loadDemoShuffleAssets { assets in
            print("[Demo] prewarming \(assets.count) shuffle asset(s)")
            for asset in assets where asset.mediaType == .image {
                PhotoLibraryService.shared.requestCardImage(for: asset) { image, isDegraded in
                    guard let image, !isDegraded else { return }
                    PhotoLibraryService.shared.cacheImage(image, for: asset.localIdentifier)
                }
            }
            onResolved?(assets)
        }
    }

    /// Deletes every demo asset ever imported into the real Photos library — across both
    /// sessions (demo1, demo2; the shuffle bucket reuses demo1's key, so it's covered too)
    /// — and clears their identifier caches so a later run re-imports fresh copies instead
    /// of pointing at now-deleted identifiers. Call once at the end of a recording session
    /// to leave the real Photos library exactly as it was before demo mode touched it.
    static func deleteAllDemoAssets(completion: @escaping (Bool) -> Void) {
        let sessions: [DemoSession] = [.demo1, .demo2]
        // demoShuffleIdentifiersKey is its own dedicated cache key (no longer aliases
        // demo1's), so it must be swept separately or the sneak-peek trio would leak
        // out of cleanup entirely.
        let cacheKeys = sessions.map { $0.identifiersKey } + [demoShuffleIdentifiersKey]
        let allIDs = Set(cacheKeys.flatMap { key in
            ((UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]).values
        })
        guard !allIDs.isEmpty else {
            print("[Demo] deleteAllDemoAssets — nothing to delete")
            completion(true)
            return
        }
        let toDelete = PHAsset.fetchAssets(withLocalIdentifiers: Array(allIDs), options: nil)
        print("[Demo] deleting \(toDelete.count) demo asset(s) from Photos")
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(toDelete)
        }, completionHandler: { success, error in
            if success {
                for key in cacheKeys { UserDefaults.standard.removeObject(forKey: key) }
                shakeDemoLoaded = false
                print("[Demo] deleteAllDemoAssets succeeded")
            } else {
                print("[Demo] ⚠️ deleteAllDemoAssets failed: \(error?.localizedDescription ?? "unknown error")")
            }
            DispatchQueue.main.async { completion(success) }
        })
    }

    private static func loadAssets(_ assets: [DemoAsset], cacheKey: String, completion: @escaping ([PHAsset]) -> Void) {
        let authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let cache = (UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: String]) ?? [:]
        print("[Demo] authStatus=\(authStatus.rawValue) cachedCount=\(cache.count)/\(assets.count) key=\(cacheKey)")
        if let ordered = orderedAssets(for: assets, cache: cache) {
            print("[Demo] serving \(ordered.count) cached asset(s)")
            completion(ordered)
            return
        }
        importAndLoad(assets: assets, cacheKey: cacheKey, cache: cache, completion: completion)
    }

    /// Resolves every item in `assets` to a PHAsset via the cache, preserving `assets`'
    /// order. Returns nil if anything is missing from the cache (needs importing) or a
    /// cached localIdentifier no longer resolves to a real PHAsset.
    private static func orderedAssets(for assets: [DemoAsset], cache: [String: String]) -> [PHAsset]? {
        let ids = assets.map { cache[$0.cacheKey] }
        guard ids.allSatisfy({ $0 != nil }) else { return nil }
        let nonNilIDs = ids.compactMap { $0 }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: nonNilIDs, options: nil)
        var byID: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        let resolved = nonNilIDs.compactMap { byID[$0] }
        return resolved.count == nonNilIDs.count ? resolved : nil
    }

    private static func importAndLoad(assets: [DemoAsset], cacheKey: String, cache: [String: String], completion: @escaping ([PHAsset]) -> Void) {
        // A cache entry alone isn't enough — the localIdentifier it points to may no
        // longer resolve (e.g. the demo asset was deleted from Photos directly), so treat
        // that the same as never having been imported and re-create it.
        var resolvedIDs: Set<String> = []
        let cachedIDs = Array(Set(cache.values))
        if !cachedIDs.isEmpty {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: cachedIDs, options: nil)
            result.enumerateObjects { asset, _, _ in resolvedIDs.insert(asset.localIdentifier) }
        }
        let missing = assets.filter { asset in
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
            UserDefaults.standard.set(updatedCache, forKey: cacheKey)
            let ordered = orderedAssets(for: assets, cache: updatedCache) ?? []
            print("[Demo] resolved \(ordered.count)/\(assets.count) final asset(s)")
            DispatchQueue.main.async { completion(ordered) }
        })
    }
}
