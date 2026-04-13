import Foundation
import Network

@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.postrundrip.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasConnected = self?.isConnected ?? false
                let nowConnected = path.status == .satisfied
                self?.isConnected = nowConnected

                // Drain offline queue when connectivity is restored
                if !wasConnected && nowConnected {
                    OfflineQueueManager.shared.drainQueue()
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
