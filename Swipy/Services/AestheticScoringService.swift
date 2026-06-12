//
//  AestheticScoringService.swift
//  Swipy
//
//  Builds a UserAestheticPersona from the user's Favorites and scores
//  every card 1–10 based on its match to that persona.
//

import UIKit
import Photos
import Vision
import CoreImage

// MARK: - Persona Model

struct UserAestheticPersona: Codable {
    /// Average VNClassifyImageRequest confidence per category, across all favorites.
    var topCategories: [String: Double] = [:]
    /// Average Laplacian variance of favorites (sharpness baseline).
    var avgSharpnessVariance: Double = 100.0
    /// Average color temperature of favorites: 0 = cool, 1 = warm.
    var avgColorTemperature: Double = 0.5
    /// Fraction of favorites that contain people/portrait scenes.
    var facePresenceRate: Double = 0.0
    /// Fraction of favorites that are Live Photos.
    var livePhotoRate: Double = 0.0
    /// Fraction of favorites that are HDR.
    var hdrRate: Double = 0.0
    var sampleCount: Int = 0
    var isReady: Bool = false

    var debugDescription: String {
        let tempLabel  = avgColorTemperature > 0.6 ? "warm" : avgColorTemperature < 0.4 ? "cool" : "neutral"
        let topCatList = topCategories
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { "    \($0.key): \(String(format: "%.2f", $0.value))" }
            .joined(separator: "\n")
        return """
        [AestheticScoring] ── User Aesthetic Persona ──────────────────
          Samples:          \(sampleCount) favorites
          Sharpness (avg):  \(String(format: "%.1f", avgSharpnessVariance)) (Laplacian variance)
          Color temperature:\(String(format: " %.2f", avgColorTemperature)) (\(tempLabel))
          Faces/portraits:  \(String(format: "%.0f%%", facePresenceRate * 100))
          Live Photos:      \(String(format: "%.0f%%", livePhotoRate * 100))
          HDR:              \(String(format: "%.0f%%", hdrRate * 100))
          Top scene categories (avg confidence):
        \(topCatList)
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
    private let personaKey = "userAestheticPersona_v1"

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
        reqOpts.isNetworkAccessAllowed = true  // allow iCloud thumbnails

        var sharpnessValues: [Double] = []
        var colorTempValues: [Double] = []
        var categoryAccum: [String: (sum: Double, count: Int)] = [:]
        var faceCount = 0
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

            let imgCats = classifySync(img)
            for (id, conf) in imgCats {
                let cur = categoryAccum[id] ?? (0.0, 0)
                categoryAccum[id] = (cur.sum + conf, cur.count + 1)
            }

            if imgCats.keys.contains(where: {
                $0.contains("people") || $0.contains("portrait") || $0.contains("selfie")
            }) { faceCount += 1 }
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
        p.facePresenceRate = Double(faceCount) / Double(sampleN)
        p.livePhotoRate    = Double(liveCount) / Double(sampleN)
        p.hdrRate          = Double(hdrCount)  / Double(sampleN)
        p.sampleCount      = sampleN

        let avgCats: [(String, Double)] = categoryAccum
            .mapValues { $0.sum / Double($0.count) }
            .filter { $0.value > 0.05 }
            .sorted { $0.value > $1.value }
            .prefix(20)
            .map { ($0.key, $0.value) }
        p.topCategories = Dictionary(uniqueKeysWithValues: avgCats)
        p.isReady = true
        return p
    }

    // MARK: - Scoring

    /// Returns a 1–10 score. Returns 0 if persona isn't ready yet (badge hidden).
    /// Synchronous — call from a background thread (Task.detached).
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
        // Downscale to 299×299 for all CPU-heavy operations — same size used in persona building.
        // Without this, Vision + CIEdges on a 1080p card image takes 10+ seconds.
        let thumb = resized(image, to: CGSize(width: 299, height: 299))

        var weightedSum = 0.0
        var totalWeight = 0.0

        // Sharpness: 30%
        let variance = BlurDetector.shared.sharpnessVariance(thumb)
        if variance.isFinite {
            let s = min(1.0, variance / max(p.avgSharpnessVariance, 1.0))
            weightedSum += s * 0.30; totalWeight += 0.30
        }

        // Color temperature match: 20%
        let tempS = max(0.0, 1.0 - abs(colorTemperature(of: thumb) - p.avgColorTemperature) * 2.5)
        weightedSum += tempS * 0.20; totalWeight += 0.20

        // Media-type alignment: 10%
        var typeS = 0.5
        if asset.mediaSubtypes.contains(.photoLive) && p.livePhotoRate > 0.25 { typeS += 0.3 }
        if asset.mediaSubtypes.contains(.photoHDR)  && p.hdrRate > 0.25       { typeS += 0.2 }
        weightedSum += min(1.0, typeS) * 0.10; totalWeight += 0.10

        // Scene match: 40%
        let cats = classifySync(thumb)
        if !cats.isEmpty && !p.topCategories.isEmpty {
            var overlap = 0.0
            for (id, conf) in cats {
                if let pConf = p.topCategories[id] { overlap += min(conf, pConf) }
            }
            let norm = max(p.topCategories.values.reduce(0, +) * 0.2, 0.001)
            weightedSum += min(1.0, overlap / norm) * 0.40; totalWeight += 0.40
        }

        guard totalWeight > 0 else { return 5 }
        let raw = weightedSum / totalWeight
        return max(1, min(10, Int(raw * 9) + 1))
    }

    private func classifySync(_ image: UIImage) -> [String: Double] {
        guard let cg = image.cgImage else { return [:] }
        let req = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
        return Dictionary(uniqueKeysWithValues:
            (req.results ?? [])
                .filter { $0.confidence > 0.05 }
                .prefix(15)
                .map { ($0.identifier, Double($0.confidence)) }
        )
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
