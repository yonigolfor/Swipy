//
//  BlurDetector.swift
//  CleanSwipe
//

import UIKit
import CoreImage

class BlurDetector {
    static let shared = BlurDetector()
    private init() {}

    private let context = CIContext()
    private let thumbnailSize = CGSize(width: 200, height: 200)

    /// מחזיר true אם התמונה מטושטשת
    func isBlurry(_ image: UIImage, threshold: Double = 50.0) -> Bool {
        variance(of: image) < threshold
    }

    private func variance(of image: UIImage) -> Double {
        guard
            let resized = resize(image),
            let ciImage = CIImage(image: resized),
            let filter = CIFilter(name: "CILaplacian")
        else { return Double.infinity }

        filter.setValue(ciImage, forKey: kCIInputImageKey)

        guard
            let output = filter.outputImage,
            let cgImage = context.createCGImage(output, from: output.extent)
        else { return Double.infinity }

        return calculateVariance(cgImage)
    }

    private func resize(_ image: UIImage) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result
    }

    private func calculateVariance(_ cgImage: CGImage) -> Double {
        guard
            let data = cgImage.dataProvider?.data,
            let bytes = CFDataGetBytePtr(data)
        else { return Double.infinity }

        let length = CFDataGetLength(data)
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let pixelCount = length / bytesPerPixel

        guard pixelCount > 0 else { return Double.infinity }

        var sum: Double = 0
        var sumSquared: Double = 0

        for i in stride(from: 0, to: length, by: bytesPerPixel) {
            let value = Double(bytes[i])
            sum += value
            sumSquared += value * value
        }

        let mean = sum / Double(pixelCount)
        return (sumSquared / Double(pixelCount)) - (mean * mean)
    }
}
