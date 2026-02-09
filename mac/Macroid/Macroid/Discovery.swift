import Foundation
import Network
import os.log

private let log = Logger(subsystem: "com.macroid", category: "Discovery")

class Discovery {
    static let multicastGroup = "224.0.0.167"
    static let port: UInt16 = 53317

    private var listenConnection: NWConnection?
    private var announceTimer: DispatchSourceTimer?
    private var fallbackTimer: DispatchSourceTimer?
    private var listener: NWListener?
    private var multicastGroup: NWConnectionGroup?
    private let queue = DispatchQueue(label: "com.macroid.discovery")
    let fingerprint = UUID().uuidString.prefix(8).lowercased()
    private var deviceFound = false

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
        log.info("Starting discovery with fingerprint: \(String(self.fingerprint))")
        startMulticastListener(onDeviceFound: onDeviceFound)
        startAnnouncing()
        startFallbackTimer(onDeviceFound: onDeviceFound)
    }

    private func startFallbackTimer(onDeviceFound: @escaping (DeviceInfo) -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, !self.deviceFound else { return }
            log.info("No device found via multicast after 10s, starting subnet scan fallback")
            self.startFallbackDiscovery(onDeviceFound: onDeviceFound)
        }
        timer.resume()
        fallbackTimer = timer
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
                log.debug("Multicast group state: \(String(describing: state))")
            }

            groupConnection.start(queue: queue)
            self.multicastGroup = groupConnection
            log.info("Multicast listener started on \(Discovery.multicastGroup):\(Discovery.port)")

        } catch {
            log.error("Multicast setup failed: \(error.localizedDescription), using fallback discovery")
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

        log.info("Found device: \(device.alias) at \(device.address):\(device.port)")
        deviceFound = true
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
            if let error = error {
                log.warning("Announcement send failed: \(error.localizedDescription)")
            }
        }
    }

    private func startFallbackDiscovery(onDeviceFound: @escaping (DeviceInfo) -> Void) {
        guard let localIP = getLocalIPAddress() else {
            log.error("Could not determine local IP for fallback discovery")
            return
        }
        let subnet = localIP.components(separatedBy: ".").prefix(3).joined(separator: ".")
        log.info("Starting fallback subnet scan on \(subnet).0/24")

        let scanQueue = DispatchQueue(label: "com.macroid.scan", attributes: .concurrent)
        let group = DispatchGroup()

        for i in 1...254 {
            let ip = "\(subnet).\(i)"
            if ip == localIP { continue }

            group.enter()
            scanQueue.async {
                defer { group.leave() }

                let url = URL(string: "http://\(ip):\(Discovery.port)/api/ping")!
                var request = URLRequest(url: url)
                request.timeoutInterval = 0.5

                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 0.5
                config.timeoutIntervalForResource = 1.0
                let session = URLSession(configuration: config)

                let semaphore = DispatchSemaphore(value: 0)
                let task = session.dataTask(with: request) { data, response, error in
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
                    log.info("Fallback found device at \(ip)")
                    onDeviceFound(device)
                }
                task.resume()
                _ = semaphore.wait(timeout: .now() + 1.0)
                session.invalidateAndCancel()
            }
        }

        group.notify(queue: queue) {
            log.info("Fallback subnet scan completed")
        }
    }

    func getLocalIPAddress() -> String? {
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
        fallbackTimer?.cancel()
        fallbackTimer = nil
        multicastGroup?.cancel()
        multicastGroup = nil
        log.info("Discovery stopped")
    }
}
