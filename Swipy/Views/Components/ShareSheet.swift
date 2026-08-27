import SwiftUI
import UIKit
import LinkPresentation

/// Provides a rich App Store link preview (icon + title + URL) instead of a bare
/// text link. `UIActivityItemSource` + `LPLinkMetadata` is what makes Messages,
/// Mail, and social targets render a proper app card with our icon — a plain
/// `UIImage` item only ever attaches as a separate file, never a unified preview.
final class AppShareItemSource: NSObject, UIActivityItemSource {
    private let url: URL
    private let title: String
    private let icon: UIImage?

    init(url: URL, title: String, icon: UIImage?) {
        self.url = url
        self.title = title
        self.icon = icon
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        // Returning the URL as the placeholder makes the share sheet treat this
        // item as a link, so it renders the metadata card rather than raw text.
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        title
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = url
        metadata.url = url
        if let icon {
            metadata.iconProvider = NSItemProvider(object: icon)
            metadata.imageProvider = NSItemProvider(object: icon)
        }
        return metadata
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onCompleted: (() -> Void)?

    /// Official App Store listing.
    private static let appStoreURL = URL(string: "https://apps.apple.com/il/app/swipy-photo-video-cleaner/id6772767520")!

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
        let message = String(localized: "paywall.share.message")
        let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Swipy"
        // Marketing copy for text-only targets (WhatsApp, Twitter) + a rich link
        // card (app icon + name + URL) for targets that support LPLinkMetadata.
        return [
            message,
            AppShareItemSource(url: appStoreURL, title: appName, icon: UIImage(named: "AppIconImage")),
        ]
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
