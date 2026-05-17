//
//  NetworkMonitorService.swift
//  Swipy
//

import Network
import Combine

@MainActor
final class NetworkMonitorService: ObservableObject {
    static let shared = NetworkMonitorService()

    @Published private(set) var isOnline: Bool = true
    /// True when the active path is cellular (metered).
    @Published private(set) var isExpensive: Bool = false
    /// True when Low Data Mode is enabled.
    @Published private(set) var isConstrained: Bool = false

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.swipy.networkmonitor", qos: .utility)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isOnline = path.status == .satisfied
                self.isExpensive = path.isExpensive
                self.isConstrained = path.isConstrained
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit { monitor.cancel() }
}
