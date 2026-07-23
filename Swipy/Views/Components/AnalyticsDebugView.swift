//
//  AnalyticsDebugView.swift
//  Swipy
//
//  DEBUG/TestFlight-only inspector for AnalyticsService's local event counters.
//  Long-press the "Device" section header in SmartFiltersView to open.
//

#if DEBUG
import SwiftUI

struct AnalyticsDebugView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var counts: [(key: String, value: Int)] = []

    var body: some View {
        NavigationView {
            List {
                if counts.isEmpty {
                    Text("No events logged yet")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(counts, id: \.key) { entry in
                        HStack {
                            Text(entry.key)
                            Spacer()
                            Text("\(entry.value)")
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Analytics (Debug)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Reset") {
                        PersistenceService.shared.resetAnalyticsEventCounts()
                        refresh()
                    }
                }
            }
            .onAppear(perform: refresh)
        }
    }

    private func refresh() {
        counts = PersistenceService.shared.analyticsEventCounts
            .sorted { $0.value > $1.value }
    }
}
#endif
