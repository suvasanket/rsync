//
//  NetworkMonitor.swift
//  rsync
//
//  Lightweight, kernel-driven network reachability monitor using Apple's Network framework.
//

import Foundation
import Network

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published private(set) var isConnected: Bool = true
    @Published private(set) var isChecking: Bool = true
    private(set) var hasConnectedOnce: Bool = false
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.rsync.networkmonitor", qos: .utility)
    
    var onConnectivityChange: ((_ isConnected: Bool, _ isFirstConnection: Bool) -> Void)?
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = (path.status == .satisfied)
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let previous = self.isConnected
                let firstCheck = self.isChecking
                
                self.isChecking = false
                self.isConnected = online
                
                let isFirstOnline = online && !self.hasConnectedOnce
                if online {
                    self.hasConnectedOnce = true
                }
                
                if firstCheck || previous != online {
                    print("NetworkMonitor: Status changed to \(online ? "ONLINE" : "OFFLINE") (first online: \(isFirstOnline))")
                    self.onConnectivityChange?(online, isFirstOnline)
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}
