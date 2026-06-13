//
//  AestheticScoringService.swift
//  Swipy
//
//  Builds a UserAestheticPersona from the user's Favorites and scores
//  every card 1–10 based on its match to that persona.
//  Scoring uses VNGenerateImageFeaturePrintRequest (perceptual centroid)
//  instead of VNClassifyImageRequest (coarse semantic categories).
//

import UIKit
import Photos
import Vision
import CoreImage

// MARK: - Persona Model

struct UserAestheticPersona: Codable {
    /// Element-wise mean of VNFeaturePrint float vectors across all favorites.
    var featurePrintCentroid: [Float] = []
    /// Average Laplacian variance of favorites (sharpness baseline).
    var avgSharpnessVariance: Double = 100.0
    /// Average color temperature of favorites: 0 = cool, 1 = warm.
    var avgColorTemperature: Double = 0.5
    /// Fraction of favorites that are Live Photos.
    var livePhotoRate: Double = 0.0
    /// Fraction of favorites that are HDR.
    var hdrRate: Double = 0.0
    var sampleCount: Int = 0
    var isReady: Bool = false

    var debugDescription: String {
        let tempLabel = avgColorTemperature > 0.6 ? "warm" : avgColorTemperature < 0.4 ? "cool" : "neutral"
        let centroidInfo: String
        if featurePrintCentroid.isEmpty {
            centroidInfo = "not available"
        } else {
            let norm = sqrt(featurePrintCentroid.map { Double($0) * Double($0) }.reduce(0, +))
            centroidInfo = "\(featurePrintCentroid.count) dims, L2 norm: \(String(format: "%.2f", norm))"
        }
        return """
        [AestheticScoring] ── User Aesthetic Persona ──────────────────
          Samples:          \(sampleCount) favorites
          Sharpness (avg):  \(String(format: "%.1f", avgSharpnessVariance)) (Laplacian variance)
          Color temperature:\(String(format: " %.2f", avgColorTemperature)) (\(tempLabel))
          Live Photos:      \(String(format: "%.0f%%", livePhotoRate * 100))
          HDR:              \(String(format: "%.0f%%", hdrRate * 100))
          Feature print:    \(centroidInfo)
        [AestheticScoring] ─────────────────────────────────────────────
        """
    }
}

// MARK: - Scoring Service

final class AestheticScoringService {
    static let shared = AestheticScoringService()

    private var persona: UserAestheticPersona?
    private var isAnalyzing = false
    /// Stores computed Int scores (1–10). Thread-safe via NSCache internals.
    let scoreCache = NSCache<NSString, NSNumber>()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let personaKey = "userAestheticPersona_v2"

    var isPersonaReady: Bool { persona?.isReady == true }

    private init() {
        scoreCache.countLimit = 60
        if let data = UserDefaults.standard.data(forKey: personaKey),
           let saved = try? JSONDecoder().decode(UserAestheticPersona.self, from: data) {
            persona = saved
        }
    }

    /// Synchronous cache read — safe to call from any thread.
    func cachedScore(for id: String) -> Int? {
        guard let n = scoreCache.object(forKey: id as NSString) else { return nil }
        let v = n.intValue
        return v > 0 ? v : nil
    }

    // MARK: - Persona Building

    /// Scans up to 200 Favorites in the background and builds the persona.
    /// No-op if already built or currently running.
    func analyzeFavorites() async {
        if persona?.isReady == true {
            print("[AestheticScoring] ✓ Persona already loaded from cache (\(persona!.sampleCount) favorites). Skipping re-analysis.")
            print(persona!.debugDescription)
            return
        }
        guard !isAnalyzing else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        print("[AestheticScoring] ▶︎ Starting user style analysis…")
        let startTime = Date()

        // Dispatch blocking PHImageManager + Vision work to a GCD thread.
        // Do NOT run this on the Swift cooperative thread pool — sequential
        // isSynchronous image requests would stall the entire async system.
        guard let p = await withCheckedContinuation({ (continuation: CheckedContinuation<UserAestheticPersona?, Never>) in
            DispatchQueue.global(qos: .utility).async { [self] in
                continuation.resume(returning: self.buildPersonaBlocking())
            }
        }) else {
            print("[AestheticScoring] ✗ Analysis aborted — see logs above for reason.")
            return
        }

        persona = p
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: personaKey)
        }

        let elapsed = String(format: "%.1f", Date().timeIntervalSince(startTime))
        print("[AestheticScoring] ✓ Style analysis complete in \(elapsed)s — \(p.sampleCount) favorites scanned.")
        print(p.debugDescription)
    }

    private func buildPersonaBlocking() -> UserAestheticPersona? {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(
            format: "favorite == YES AND mediaType == %d",
            PHAssetMediaType.image.rawValue
        )
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = 200

        let result = PHAsset.fetchAssets(with: opts)
        let total = result.count
        print("[AestheticScoring] Found \(total) favorited images in library.")
        guard total >= 3 else {
            print("[AestheticScoring] ✗ Too few favorites (\(total)) — need at least 3.")
            return nil
        }
        let sampleN = min(total, 200)

        let thumbSize = CGSize(width: 299, height: 299)
        let reqOpts = PHImageRequestOptions()
        reqOpts.isSynchronous = true
        reqOpts.deliveryMode = .fastFormat
        reqOpts.resizeMode = .fast
        reqOpts.isNetworkAccessAllowed = true

        var sharpnessValues: [Double] = []
        var colorTempValues: [Double] = []
        var fpAccum: [Float] = []       // element-wise sum of feature print vectors
        var fpCount = 0
        var liveCount = 0
        var hdrCount = 0
        var loadedCount = 0

        for i in 0..<sampleN {
            let asset = result.object(at: i)
            if asset.mediaSubtypes.contains(.photoLive) { liveCount += 1 }
            if asset.mediaSubtypes.contains(.photoHDR)  { hdrCount += 1 }

            var thumb: UIImage?
            PHImageManager.default().requestImage(
                for: asset, targetSize: thumbSize,
                contentMode: .aspectFit, options: reqOpts
            ) { img, _ in thumb = img }
            guard let img = thumb else { continue }
            loadedCount += 1

            let v = BlurDetector.shared.sharpnessVariance(img)
            if v.isFinite && v >= 0 { sharpnessValues.append(v) }

            colorTempValues.append(colorTemperature(of: img))

            // Feature print accumulation
            if let fp = extractFeaturePrintVector(img) {
                if fpAccum.isEmpty {
                    fpAccum = fp
                } else if fp.count == fpAccum.count {
                    for j in 0..<fp.count { fpAccum[j] += fp[j] }
                }
                fpCount += 1
            }
        }

        print("[AestheticScoring] Loaded \(loadedCount)/\(sampleN) thumbnails successfully.")
        guard !sharpnessValues.isEmpty else {
            print("[AestheticScoring] ✗ All thumbnails failed to load (iCloud-only photos with no local cache?).")
            return nil
        }

        var p = UserAestheticPersona()
        p.avgSharpnessVariance = sharpnessValues.reduce(0, +) / Double(sharpnessValues.count)
        p.avgColorTemperature  = colorTempValues.isEmpty
            ? 0.5
            : colorTempValues.reduce(0, +) / Double(colorTempValues.count)
        p.livePhotoRate    = Double(liveCount) / Double(sampleN)
        p.hdrRate          = Double(hdrCount)  / Double(sampleN)
        p.sampleCount      = sampleN

        if fpCount > 0 && !fpAccum.isEmpty {
            let n = Float(fpCount)
            p.featurePrintCentroid = fpAccum.map { $0 / n }
            print("[AestheticScoring] Feature print centroid built from \(fpCount) images (\(fpAccum.count) dims).")
        } else {
            print("[AestheticScoring] ⚠︎ Feature print extraction failed for all images — centroid unavailable.")
        }

        p.isReady = true
        return p
    }

    // MARK: - Scoring

    /// Returns a 1–10 score. Returns 0 if persona isn't ready yet (badge hidden).
    /// Synchronous — call from a background thread via DispatchQueue.global.
    func score(for asset: PHAsset, image: UIImage) -> Int {
        let key = asset.localIdentifier as NSString
        if let cached = scoreCache.object(forKey: key) {
            print("[AestheticScoring] score() NSCache hit → \(cached.intValue) for \(asset.localIdentifier.prefix(8))")
            return cached.intValue
        }
        guard let p = persona, p.isReady else {
            print("[AestheticScoring] score() persona nil/not ready — returning 0")
            return 0
        }
        print("[AestheticScoring] score() computing for \(asset.localIdentifier.prefix(8))…")
        let result = computeScore(asset: asset, image: image, persona: p)
        print("[AestheticScoring] score() done → \(result) for \(asset.localIdentifier.prefix(8))")
        scoreCache.setObject(NSNumber(value: result), forKey: key)
        return result
    }

    // MARK: - Private Computation

    private func computeScore(asset: PHAsset, image: UIImage, persona p: UserAestheticPersona) -> Int {
        // Downscale to 299×299 for all CPU-heavy operations.
        let thumb = resized(image, to: CGSize(width: 299, height: 299))

        var weightedSum = 0.0
        var totalWeight = 0.0

        // Sharpness: 25%
        let variance = BlurDetector.shared.sharpnessVariance(thumb)
        if variance.isFinite {
            let s = min(1.0, variance / max(p.avgSharpnessVariance, 1.0))
            weightedSum += s * 0.25; totalWeight += 0.25
        }

        // Color temperature match: 15%
        let tempS = max(0.0, 1.0 - abs(colorTemperature(of: thumb) - p.avgColorTemperature) * 2.5)
        weightedSum += tempS * 0.15; totalWeight += 0.15

        // Media-type alignment: 10%
        var typeS = 0.5
        if asset.mediaSubtypes.contains(.photoLive) && p.livePhotoRate > 0.25 { typeS += 0.3 }
        if asset.mediaSubtypes.contains(.photoHDR)  && p.hdrRate > 0.25       { typeS += 0.2 }
        weightedSum += min(1.0, typeS) * 0.10; totalWeight += 0.10

        // Feature print similarity: 50%
        if !p.featurePrintCentroid.isEmpty,
           let cardFP = extractFeaturePrintVector(thumb),
           cardFP.count == p.featurePrintCentroid.count {
            let sim = featurePrintSimilarity(cardFP, p.featurePrintCentroid)
            weightedSum += sim * 0.50; totalWeight += 0.50
        }

        guard totalWeight > 0 else { return 5 }
        var raw = weightedSum / totalWeight

        // Blur gate — two tiers so blurry images can't ride a high feature-print score.
        //
        // Tier 1 (hard): variance < 600 → sharpnessFactor ramps 0→1 over that range.
        //   Calibrated from real images: blurry=290–580, sharp=622+.
        //   var=290 → gate≈0.51, var=440 → gate≈0.75, var=580 → gate≈0.97.
        // Tier 2 (soft): variance ≥ 600 → relative to persona baseline.
        // Fallback: BlurDetector returned ∞ (CIEdges pipeline failed) → 0.6× penalty.
        let hardBlurThreshold = 600.0
        let sharpnessFactor: Double
        if variance.isFinite && variance >= 0 {
            if variance < hardBlurThreshold {
                sharpnessFactor = variance / hardBlurThreshold
            } else {
                sharpnessFactor = min(1.0, variance / max(p.avgSharpnessVariance, hardBlurThreshold))
            }
            raw *= (0.05 + 0.95 * sharpnessFactor)
        } else {
            sharpnessFactor = -1  // sentinel: BlurDetector failed
            raw *= 0.6
        }

        let finalScore = max(1, min(10, Int(raw * 9) + 1))
        let blurBucket = !variance.isFinite ? "∞(fail)" : variance < 50 ? "VERY-BLURRY" : variance < hardBlurThreshold ? "BLURRY" : variance < 300 ? "borderline" : "sharp"
        print("[BlurCalib] \(blurBucket) | var=\(variance.isFinite ? String(format:"%.1f",variance) : "∞") | threshold=\(hardBlurThreshold) | gate=\(String(format:"%.3f", sharpnessFactor < 0 ? 0.6 : (0.05 + 0.95 * max(0, sharpnessFactor)))) | score=\(finalScore)")
        print("[AestheticScoring] score detail: var=\(variance.isFinite ? String(format:"%.0f",variance) : "∞") avg=\(String(format:"%.0f",p.avgSharpnessVariance)) sf=\(sharpnessFactor < 0 ? "n/a" : String(format:"%.2f",sharpnessFactor)) raw→\(String(format:"%.3f",raw)) score=\(finalScore)")
        return finalScore
    }

    /// Extracts a raw float vector from a VNGenerateImageFeaturePrintRequest.
    /// Must be called on a non-cooperative background thread (blocking Vision call).
    private func extractFeaturePrintVector(_ image: UIImage) -> [Float]? {
        guard let cg = image.cgImage else { return nil }
        let req = VNGenerateImageFeaturePrintRequest()
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
        guard let obs = req.results?.first as? VNFeaturePrintObservation,
              obs.elementType == .float,
              obs.elementCount > 0 else { return nil }
        return obs.data.withUnsafeBytes { buf in Array(buf.bindMemory(to: Float.self)) }
    }

    /// L2 distance between two feature print vectors, normalized to [0, 1].
    /// Distance range for VNFeaturePrint: ~0 (identical) to ~10+ (very different).
    private func featurePrintSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        var sumSq: Float = 0
        for i in 0..<a.count { let d = a[i] - b[i]; sumSq += d * d }
        let distance = Double(sumSq.squareRoot())
        return max(0.0, 1.0 - distance / 8.0)
    }

    private func resized(_ image: UIImage, to size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let result = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return result
    }

    private func colorTemperature(of image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0.5 }
        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage") else { return 0.5 }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: ci.extent), forKey: "inputExtent")
        guard let out = filter.outputImage else { return 0.5 }

        var px = [UInt8](repeating: 0, count: 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
                data: &px, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let avg = ciContext.createCGImage(out, from: CGRect(x: 0, y: 0, width: 1, height: 1))
        else { return 0.5 }
        ctx.draw(avg, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let r = Double(px[0]), g = Double(px[1]), b = Double(px[2])
        let total = r + g + b
        return total > 0 ? (r + g * 0.5) / total : 0.5
    }
}
