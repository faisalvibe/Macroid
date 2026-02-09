import Foundation
import Network

class Discovery {
    static let multicastGroup = "224.0.0.167"
    static let port: UInt16 = 53317

    private var listenConnection: NWConnection?
    private var announceTimer: DispatchSourceTimer?
    private var listener: NWListener?
    private var multicastGroup: NWConnectionGroup?
    private let queue = DispatchQueue(label: "com.macroid.discovery")
    private let fingerprint = UUID().uuidString.prefix(8).lowercased()

    private var announcement: [String: Any] {
        return [
            "alias": Host.current().localizedName ?? "Mac",
            "version": "2.1",
            "deviceModel": getMacModel(),
            "deviceType": "desktop",
            "fingerprint": String(fingerprint),
            "port": Int(Discovery.port),
            "protocol": "http",
            "download": false,
            "announce": true
        ]
    }

    func startDiscovery(onDeviceFound: @escaping (DeviceInfo) -> Void) {
        startMulticastListener(onDeviceFound: onDeviceFound)
        startAnnouncing()
    }

    private func startMulticastListener(onDeviceFound: @escaping (DeviceInfo) -> Void) {
        do {
            let group = try NWMulticastGroup(for: [
                .hostPort(
                    host: NWEndpoint.Host(Discovery.multicastGroup),
                    port: NWEndpoint.Port(rawValue: Discovery.port)!
                )
            ])

            let groupConnection = NWConnectionGroup(with: group, using: .udp)

            groupConnection.setReceiveHandler(maximumMessageSize: 4096, rejectOversizedMessages: true) { [weak self] message, content, isComplete in
                guard let self = self, let data = content else { return }

                self.handleReceivedData(data, from: message, onDeviceFound: onDeviceFound)
            }

            groupConnection.stateUpdateHandler = { state in
                // Connection group state changed
            }

            groupConnection.start(queue: queue)
            self.multicastGroup = groupConnection

        } catch {
            // Multicast setup failed, fall back to manual discovery
            startFallbackDiscovery(onDeviceFound: onDeviceFound)
        }
    }

    private func handleReceivedData(_ data: Data, from message: NWConnectionGroup.Message, onDeviceFound: @escaping (DeviceInfo) -> Void) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        guard let msgFingerprint = json["fingerprint"] as? String,
              msgFingerprint != String(fingerprint) else { return }

        let deviceType = json["deviceType"] as? String ?? "unknown"
        guard deviceType == "mobile" else { return }

        let alias = json["alias"] as? String ?? "Unknown"
        let port = json["port"] as? Int ?? Int(Discovery.port)

        var address = "unknown"
        if case .hostPort(let host, _) = message.remoteEndpoint {
            address = "\(host)"
        }

        let device = DeviceInfo(
            alias: alias,
            deviceType: deviceType,
            fingerprint: msgFingerprint,
            address: address,
            port: port
        )

        onDeviceFound(device)
    }

    private func startAnnouncing() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 3.0)
        timer.setEventHandler { [weak self] in
            self?.sendAnnouncement()
        }
        timer.resume()
        announceTimer = timer
    }

    private func sendAnnouncement() {
        guard let data = try? JSONSerialization.data(withJSONObject: announcement) else { return }

        multicastGroup?.send(content: data) { error in
            // Announcement sent (or failed)
        }
    }

    private func startFallbackDiscovery(onDeviceFound: @escaping (DeviceInfo) -> Void) {
        // Scan local subnet for Macroid devices
        guard let localIP = getLocalIPAddress() else { return }
        let subnet = localIP.components(separatedBy: ".").prefix(3).joined(separator: ".")

        queue.async {
            for i in 1...254 {
                let ip = "\(subnet).\(i)"
                if ip == localIP { continue }

                let url = URL(string: "http://\(ip):\(Discovery.port)/api/ping")!
                var request = URLRequest(url: url)
                request.timeoutInterval = 0.5

                let semaphore = DispatchSemaphore(value: 0)
                let task = URLSession.shared.dataTask(with: request) { data, response, error in
                    defer { semaphore.signal() }
                    guard error == nil, let data = data,
                          String(data: data, encoding: .utf8) == "pong" else { return }

                    let device = DeviceInfo(
                        alias: ip,
                        deviceType: "mobile",
                        fingerprint: "fallback",
                        address: ip,
                        port: Int(Discovery.port)
                    )
                    onDeviceFound(device)
                }
                task.resume()
                semaphore.wait()
            }
        }
    }

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }

    private func getMacModel() -> String {
        var size: size_t = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }

    func stopDiscovery() {
        announceTimer?.cancel()
        announceTimer = nil
        multicastGroup?.cancel()
        multicastGroup = nil
    }
}
