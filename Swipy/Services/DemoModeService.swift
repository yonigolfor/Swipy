//
//  DemoModeService.swift
//  Swipy
//
//  DEMO BRANCH ONLY — not meant to reach main. Imports the bundled
//  Assets.xcassets/Demo images into Photos once, so they become real PHAssets and flow
//  through the existing card pipeline (PhotoItem/PhotoLibraryService/CardStackView)
//  completely unchanged. Delete this file (and its two call sites in SwipeStackView.swift
//  and PhotoStackViewModel.swift) before merging back to main.
//

import Photos
import UIKit

enum DemoModeService {
    static let imageNames = ["DemoPhoto1", "DemoPhoto2", "DemoPhoto3", "DemoPhoto4", "DemoPhoto5", "DemoPhoto6"]
    private static let identifiersKey = "demoAssetLocalIdentifiers"

    /// Resolves the demo PHAssets, importing them into Photos on first call only.
    /// Every later call (each shake) just re-fetches the same 6 assets by their
    /// stored localIdentifier — nothing is re-imported or duplicated.
    static func loadDemoAssets(completion: @escaping ([PHAsset]) -> Void) {
        if let saved = UserDefaults.standard.stringArray(forKey: identifiersKey),
           let ordered = fetchOrdered(saved), ordered.count == imageNames.count {
            completion(ordered)
            return
        }
        importAndLoad(completion: completion)
    }

    private static func fetchOrdered(_ ids: [String]) -> [PHAsset]? {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var byID: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }
        return ids.compactMap { byID[$0] }
    }

    private static func importAndLoad(completion: @escaping ([PHAsset]) -> Void) {
        var placeholders: [PHObjectPlaceholder] = []
        PHPhotoLibrary.shared().performChanges({
            for name in imageNames {
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
            UserDefaults.standard.set(ids, forKey: identifiersKey)
            let ordered = fetchOrdered(ids) ?? []
            DispatchQueue.main.async { completion(ordered) }
        })
    }
}
