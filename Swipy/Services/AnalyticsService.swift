//
//  AnalyticsService.swift
//  Swipy
//
//  Native-only, on-device product telemetry. No network, no third-party SDK.
//  Two layers per event:
//   1. A local aggregate counter (PersistenceService) — inspectable via
//      AnalyticsDebugView during development/TestFlight.
//   2. An os_signpost — MetricKit automatically rolls these up into
//      MXSignpostMetric, surfaced in Xcode Organizer → Metrics for
//      opted-in users once the app is live. No subscriber code needed.
//

import Foundation
import os

final class AnalyticsService {
    static let shared = AnalyticsService()

    enum Event: String {
        case swipeKeep, swipeDelete, swipeSnooze, undoTriggered
        case shuffleActivated, smartFilterOpened
        case reviewBinEmptied, paywallShown, subscriptionPurchased
    }

    private let signpostLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "Swipy", category: "ProductUsage")

    /// - Parameter detail: optional breakdown suffix (e.g. a FilterCategory or PremiumTier
    ///   rawValue) appended to the persisted counter key. The signpost name is always a
    ///   static literal (os_signpost requires it) so MetricKit aggregates a stable,
    ///   low-cardinality taxonomy regardless of `detail`.
    func log(_ event: Event, detail: String? = nil) {
        let key = detail.map { "\(event.rawValue).\($0)" } ?? event.rawValue
        PersistenceService.shared.incrementEventCount(key)

        switch event {
        case .swipeKeep:             os_signpost(.event, log: signpostLog, name: "swipeKeep")
        case .swipeDelete:           os_signpost(.event, log: signpostLog, name: "swipeDelete")
        case .swipeSnooze:           os_signpost(.event, log: signpostLog, name: "swipeSnooze")
        case .undoTriggered:         os_signpost(.event, log: signpostLog, name: "undoTriggered")
        case .shuffleActivated:      os_signpost(.event, log: signpostLog, name: "shuffleActivated")
        case .smartFilterOpened:     os_signpost(.event, log: signpostLog, name: "smartFilterOpened")
        case .reviewBinEmptied:      os_signpost(.event, log: signpostLog, name: "reviewBinEmptied")
        case .paywallShown:          os_signpost(.event, log: signpostLog, name: "paywallShown")
        case .subscriptionPurchased: os_signpost(.event, log: signpostLog, name: "subscriptionPurchased")
        }
    }

    private init() {}
}
