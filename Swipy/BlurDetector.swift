//
//  BlurDetector.swift
//  CleanSwipe
//

import UIKit
import CoreImage
import Vision

class BlurDetector {
    static let shared = BlurDetector()
    private init() {}

    /// Variance threshold for the blurry photos filter category.
    /// Calibrated from real images: blurry=155–445, sharp=1419+.
    static let blurryFilterThreshold: Double = 300.0

    private let context = CIContext()
    private let thumbnailSize = CGSize(width: 200, height: 200)

    /// מחזיר true אם התמונה מטושטשת
    func isBlurry(_ image: UIImage, threshold: Double = BlurDetector.blurryFilterThreshold) -> Bool {
        sharpnessVariance(image) < threshold
    }

    /// Raw Laplacian variance — used by AestheticScoringService for sharpness scoring.
    func sharpnessVariance(_ image: UIImage) -> Double {
        edgeStats(of: image).variance
    }

    // MARK: - Private Core

    /// Grayscale CIEdges variance + mean in one pass. Resizes to thumbnailSize first.
    private func edgeStats(of image: UIImage) -> (variance: Double, mean: Double) {
        guard
            let resized = resize(image),
            var ciImage = CIImage(image: resized),
            let edgeFilter = CIFilter(name: "CIEdges")
        else { return (.infinity, .infinity) }

        // Grayscale first — color edges on blurry images inflate variance and mask true focus loss
        if let grayFilter = CIFilter(name: "CIPhotoEffectMono") {
            grayFilter.setValue(ciImage, forKey: kCIInputImageKey)
            ciImage = grayFilter.outputImage ?? ciImage
        }

        edgeFilter.setValue(ciImage, forKey: kCIInputImageKey)
        edgeFilter.setValue(1.0, forKey: "inputIntensity")

        guard
            let output = edgeFilter.outputImage,
            let cgEdge = context.createCGImage(output, from: output.extent)
        else { return (.infinity, .infinity) }

        return pixelStats(cgEdge)
    }

    private func resize(_ image: UIImage) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(thumbnailSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result
    }

    private func pixelStats(_ cgImage: CGImage) -> (variance: Double, mean: Double) {
        guard
            let data = cgImage.dataProvider?.data,
            let bytes = CFDataGetBytePtr(data)
        else { return (.infinity, .infinity) }

        let length = CFDataGetLength(data)
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let pixelCount = length / bytesPerPixel
        guard pixelCount > 0 else { return (.infinity, .infinity) }

        var sum: Double = 0
        var sumSquared: Double = 0
        for i in stride(from: 0, to: length, by: bytesPerPixel) {
            let v = Double(bytes[i])
            sum += v
            sumSquared += v * v
        }
        let mean = sum / Double(pixelCount)
        return ((sumSquared / Double(pixelCount)) - mean * mean, mean)
    }

    // MARK: - Debug Calibration

    #if DEBUG
    /// Returns raw variance, normalized variance, and the region used ("face" or "full").
    /// Normalized = variance / mean² (coefficient of variation²) — content-independent.
    /// Must be called from a non-cooperative background thread (Vision + CIEdges block).
    func advancedSharpnessInfo(_ image: UIImage) -> (raw: Double, normalized: Double, region: String) {
        let (targetImage, region): (UIImage, String)
        if let faceImage = cropToFace(image) {
            (targetImage, region) = (faceImage, "face")
        } else {
            (targetImage, region) = (image, "full")
        }
        let stats = edgeStats(of: targetImage)
        // Normalize by mean² so a busy-but-blurry background doesn't inflate the score
        let normalized = stats.mean > 1 ? stats.variance / (stats.mean * stats.mean) : stats.variance
        return (stats.variance, normalized, region)
    }

    /// Crops to the largest detected face with 20% padding. Returns nil if no face found.
    private func cropToFace(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        guard let face = request.results?.first as? VNFaceObservation else { return nil }

        let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
        // Vision: bottom-left origin → flip Y for CGImage (top-left origin)
        let box = face.boundingBox
        let faceRect = CGRect(x: box.minX * w, y: (1 - box.maxY) * h,
                              width: box.width * w, height: box.height * h)
        // 20% padding so we include forehead and chin context
        let padded = faceRect.insetBy(dx: -faceRect.width * 0.2, dy: -faceRect.height * 0.2)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard let cropped = cgImage.cropping(to: padded) else { return nil }
        return UIImage(cgImage: cropped)
    }
    #endif
}
