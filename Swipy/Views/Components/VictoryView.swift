import SwiftUI

struct VictoryView: View {
    let onEmptyBin: () -> Void
    var onImportPhotos: (() -> Void)? = nil
    var reviewBinCount: Int = 0
    var currentFilter: FilterCategory = .all
    var isOfflineMode: Bool = false

    private var iconName: String {
        isOfflineMode ? "airplane.circle.fill" : "checkmark.seal.fill"
    }

    private var iconColor: Color {
        isOfflineMode ? Color(red: 0.1, green: 0.35, blue: 0.9) : .swipeGreen
    }

    private var titleText: String {
        if isOfflineMode { return String(localized: "victory.title_offline") }
        return currentFilter == .all
            ? String(localized: "victory.title")
            : "\(currentFilter.displayName) ✓"
    }

    private var subtitleText: String {
        if isOfflineMode { return String(localized: "victory.subtitle_offline") }
        return currentFilter == .all
            ? String(localized: "victory.subtitle")
            : String(format: String(localized: "victory.subtitle_filter"), currentFilter.displayName)
    }

    var body: some View {
        VStack(spacing: 25) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [iconColor.opacity(0.2), iconColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)

                Image(systemName: iconName)
                    .font(.system(size: 70))
                    .foregroundColor(iconColor)
                    .shadow(color: iconColor.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .padding(.top, 40)

            VStack(spacing: 12) {
                Text(titleText)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)

                Text(subtitleText)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal)
            }
            
             // CTA
            if reviewBinCount > 0 {
                Button(action: onEmptyBin) {
                    Text(String(format: String(localized: "victory.empty_bin"), reviewBinCount))
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Capsule().fill(Color.red.gradient))
                }
                .padding(.horizontal)
            }

            if let onImportPhotos {
                Button(action: onImportPhotos) {
                    HStack(spacing: 8) {
                        Image(systemName: "gear")
                        Text(String(localized: "victory.import_photos"))
                            .font(.headline)
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Capsule().fill(Color.blue.opacity(0.1)))
                }
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding()
        .transition(.asymmetric(
            insertion: .scale.combined(with: .opacity),
            removal: .opacity
        ))
    }
}

#Preview {
    VictoryView(onEmptyBin: {})
}
