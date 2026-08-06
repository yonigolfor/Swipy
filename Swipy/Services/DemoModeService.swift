//
//  DemoModeService.swift
//  Swipy
//
//  DEMO BRANCH ONLY — not meant to reach main. Imports the bundled
//  Assets.xcassets/Demo/<session> images into Photos once per session, so they become real
//  PHAssets and flow through the existing card pipeline (PhotoItem/PhotoLibraryService/
//  CardStackView) completely unchanged. Delete this file (and its two call sites in
//  SwipeStackView.swift and PhotoStackViewModel.swift) before merging back to main.
//

import Photos
import UIKit

enum DemoModeService {
    /// A named set of 6 bundled demo images (Assets.xcassets/Demo/<case>/).
    enum DemoSession: String {
        case demo1
        case demo2

        var imageNames: [String] {
            switch self {
            case .demo1: return ["DemoPhoto1", "DemoPhoto2", "DemoPhoto3", "DemoPhoto4", "DemoPhoto5", "DemoPhoto6"]
            case .demo2: return ["Demo2Photo1", "Demo2Photo2", "Demo2Photo3", "Demo2Photo4", "Demo2Photo5", "Demo2Photo6"]
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
    /// call only. Every later call (each shake) just re-fetches the same 6 assets by their
    /// stored localIdentifier — nothing is re-imported or duplicated.
    static func loadDemoAssets(completion: @escaping ([PHAsset]) -> Void) {
        let session = activeSession
        if let saved = UserDefaults.standard.stringArray(forKey: session.identifiersKey),
           let ordered = fetchOrdered(saved), ordered.count == session.imageNames.count {
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
            for name in session.imageNames {
                guard let image = UIImage(named: name) else { continue }
                if let placeholder = PHAssetChangeRequest.creationRequestForAsset(from: image).placeholderForCreatedAsset {
                    placeholders.append(placeholder)
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
