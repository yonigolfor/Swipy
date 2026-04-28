//
//  PHAsset+Extensions.swift
//  CleanSwipe
//
//  Extensions עבור PHAsset (Photos Framework)
//

import Photos
import UIKit

extension PHAsset {
    /// גודל הקובץ ב-bytes
    var fileSize: Int64 {
        guard let resource = PHAssetResource.assetResources(for: self).first else {
            return 0
        }
        
        if let unsignedInt64 = resource.value(forKey: "fileSize") as? CLong {
            return Int64(unsignedInt64)
        }
        
        return 0
    }
    
    /// גודל קריא (MB/GB)
    var fileSizeString: String {
        let bytes = Double(fileSize)
        let megabytes = bytes / 1_048_576 // 1024 * 1024
        
        if megabytes < 1024 {
            return String(format: "%.1f MB", megabytes)
        } else {
            let gigabytes = megabytes / 1024
            return String(format: "%.2f GB", gigabytes)
        }
    }
    
    /// האם זה screenshot
    var isScreenshot: Bool {
        return (mediaSubtypes.contains(.photoScreenshot))
    }
    
    /// האם זה screen recording
    var isScreenRecording: Bool {
        if mediaType == .video {
            // Screen recordings usually have specific dimensions
            return pixelWidth == 1170 || pixelWidth == 1284 || pixelWidth == 2532
        }
        return false
    }
    
    /// טעינת תמונה (async)
    func loadImage(targetSize: CGSize = PHImageManagerMaximumSize,
                   completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        
        PHImageManager.default().requestImage(
            for: self,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }
    
    /// טעינת תמונה סינכרונית (לשימוש ב-async context)
    func loadImageAsync(targetSize: CGSize = PHImageManagerMaximumSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            loadImage(targetSize: targetSize) { image in
                continuation.resume(returning: image)
            }
        }
    }
}
