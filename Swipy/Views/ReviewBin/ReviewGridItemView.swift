//
//  ReviewGridItemView.swift
//  Swipy
//
//  פריט בודד בגריד של Review Bin
//
//  Performance design:
//  - thumbnailPixelSize injected from ReviewBinView — pixel-exact match with
//    startCachingImages guarantees a PHCachingImageManager cache hit every time.
//  - loadThumbnail (.fastFormat, no network) — serves from PHKit OS cache in <1ms.
//  - Request ID stored and cancelled on onDisappear — no request storm on fast scroll.
//  - No app-level NSCache — PHCachingImageManager already manages OS-level caching;
//    double-caching wastes memory without adding speed.
//  - No withAnimation in callback — avoids layout work during scroll.
//  - Cell ratio 4:3 — matches standard camera output; most photos fill with zero letterbox.
//  - Color.clear anchor + .overlay pattern — layout bounds are fixed to the anchor,
//    so scaledToFill content can never bleed into neighbouring cells.
//  - Blurred scaledToFill underlay fills letterbox areas for portrait/square assets.
//

import SwiftUI
import Photos

struct ReviewGridItemView: View {
    let item: PhotoItem
    let thumbnailPixelSize: CGSize

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID = PHInvalidImageRequestID

    var body: some View {
        Color.clear
            .aspectRatio(4/3, contentMode: .fit)
            .overlay {
                ZStack {
                    if let image {
                        // Blurred fill — covers letterbox areas for non-4:3 assets.
                        // scaleEffect(1.1) hides the soft blur edge artifact.
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: 18)
                            .scaleEffect(1.1)

                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Color.primary.opacity(0.08)
                        ProgressView()
                    }

                    // Video duration strip
                    if item.isVideo {
                        VStack {
                            Spacer()
                            HStack {
                                Image(systemName: "play.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                Text(item.durationString)
                                    .font(.caption2)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(6)
                            .background(
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.6)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }

                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onAppear(perform: loadThumbnail)
            .onDisappear(perform: cancelIfNeeded)
    }

    // MARK: - Image Loading

    private func loadThumbnail() {
        requestID = PhotoLibraryService.shared.loadThumbnail(
            for: item.asset,
            targetSize: thumbnailPixelSize
        ) { loaded in
            guard let loaded else { return }
            self.image = loaded
        }
    }

    private func cancelIfNeeded() {
        guard requestID != PHInvalidImageRequestID else { return }
        PhotoLibraryService.shared.cancelRequest(requestID)
        requestID = PHInvalidImageRequestID
    }
}
