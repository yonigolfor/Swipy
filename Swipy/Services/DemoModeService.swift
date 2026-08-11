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
                let photoAssets = (1...15).map { DemoAsset.image(name: "Demo2Photo\($0)") }
                return photoAssets + [.video(resource: "Demo2Video1", ext: "mov")]
            }
        }

        /// Each session gets its own UserDefaults key so both can be imported into Photos
        /// independently and idempotently — switching activeSession never re-imports or
        /// loses track of the other session's already-imported assets.
        var identifiersKey: String { "demoAssetLocalIdentifiers_\(rawValue)" }
    }

    /// Toggle this to switch which preset the shake gesture restages. Change and rebuild
    /// to switch demo video scenarios.
    static var activeSession: DemoSession = .demo2

    /// Resolves the active session's demo PHAssets, importing them into Photos on first
    /// call only. Every later call (each shake) just re-fetches the same assets by their
    /// stored localIdentifier — nothing is re-imported or duplicated.
    static func loadDemoAssets(completion: @escaping ([PHAsset]) -> Void) {
        let session = activeSession
        if let saved = UserDefaults.standard.stringArray(forKey: session.identifiersKey),
           let ordered = fetchOrdered(saved), ordered.count == session.assets.count {
            completion(ordered)
            return
        }
        importAndLoad(session: session, completion: completion)
    }

    private static func fetchOrdered(_ ids: [String]) -> [PHAsset]? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var byID: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        return ids.compactMap { byID[$0] }
    }

    private static func importAndLoad(session: DemoSession, completion: @escaping ([PHAsset]) -> Void) {
        var placeholders: [PHObjectPlaceholder] = []
        PHPhotoLibrary.shared().performChanges({
            for asset in session.assets {
                switch asset {
                case .image(let name):
                    guard let image = UIImage(named: name) else { continue }
                    if let placeholder = PHAssetChangeRequest.creationRequestForAsset(from: image).placeholderForCreatedAsset {
                        placeholders.append(placeholder)
                    }
                case .video(let resource, let ext):
                    guard let url = Bundle.main.url(forResource: resource, withExtension: ext),
                          let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) else { continue }
                    if let placeholder = request.placeholderForCreatedAsset {
                        placeholders.append(placeholder)
                    }
                }
            }
        }, completionHandler: { success, _ in
            guard success else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let ids = placeholders.map { $0.localIdentifier }
            UserDefaults.standard.set(ids, forKey: session.identifiersKey)
            let ordered = fetchOrdered(ids) ?? []
            DispatchQueue.main.async { completion(ordered) }
        })
    }
}
