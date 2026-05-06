import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onCompleted: (() -> Void)?

    private static let blocklist: Set<UIActivity.ActivityType> = [
        .copyToPasteboard,
        .saveToCameraRoll,
        .print,
        .assignToContact,
        .addToReadingList,
        .airDrop,
        .openInIBooks,
        .markupAsPDF,
    ]

    static func makeShareItems() -> [Any] {
        var items: [Any] = [
            String(localized: "paywall.share.message"),
            URL(string: "https://apps.apple.com/app/id6745854678")!,
        ]
        if let icon = UIImage(named: "AppIcon") {
            items.append(icon)
        }
        return items
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.excludedActivityTypes = Array(Self.blocklist)
        vc.completionWithItemsHandler = { activityType, completed, _, _ in
            guard completed, let type = activityType, !Self.blocklist.contains(type) else { return }
            onCompleted?()
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
