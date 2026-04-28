//
//  ReviewGridItemView.swift
//  CleanSwipe
//
//  פריט בודד בגריד של Review Bin
//

import SwiftUI
import Photos

struct ReviewGridItemView: View {
    let item: PhotoItem
    
    @State private var image: UIImage?
    
    var body: some View {
        ZStack {
            // Thumbnail
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 110, height: 110)
                    .clipped()
            } else {
                Color.gray.opacity(0.3)
                    .frame(width: 110, height: 110)
                
                ProgressView()
            }
            
            // Video indicator
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
            
            // File size
            VStack {
                HStack {
                    Spacer()
                    
                    Text(item.fileSizeString)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.6))
                        )
                        .padding(6)
                }
                
                Spacer()
            }
        }
        .frame(width: 110, height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        let targetSize = CGSize(width: 220, height: 220) // 2x for retina
        
        PhotoLibraryService.shared.loadImage(for: item.asset, targetSize: targetSize) { loadedImage in
            withAnimation {
                self.image = loadedImage
            }
        }
    }
}

#Preview {
    Text("Review Grid Item Preview")
}
