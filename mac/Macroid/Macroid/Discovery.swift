import Foundation
import Network
import os.log

private let log = Logger(subsystem: "com.macroid", category: "Discovery")

class Discovery {
    static let multicastGroup = "224.0.0.167"
    static let port: UInt16 = 53317

    private var listenConnection: NWConnection?
    private var announceTimer: DispatchSourceTimer?
    private var listener: NWListener?
    private var multicastGroup: NWConnectionGroup?
    private let queue = DispatchQueue(label: "com.macroid.discovery")
    let fingerprint = UUID().uuidString.prefix(8).lowercased()
    var announcePort: UInt16 = Discovery.port

    private var deviceAlias: String {
        Host.current().localizedName ?? "Mac"
    }

    func getDeviceInfo() -> [String: Any] {
        return [
            "alias": deviceAlias,
            "version": "2.1",
            "deviceModel": getMacModel(),
            "deviceType": "desktop",
            "fingerprint": String(fingerprint),
            "port": Int(announcePort),
            "protocol": "http",
            "download": false
        ]
    }

    private func getAnnouncement(announce: Bool = true) -> [String: Any] {
        var info = getDeviceInfo()
        info["announce"] = announce
        return info
    }

    func startDiscovery(onDeviceFound: @escaping (DeviceInfo) -> Void) {
        log.info("Starting discovery with fingerprint: \(String(self.fingerprint))")
        startMulticastListener(onDeviceFound: onDeviceFound)
        startAnnouncing()

        // Start fallback subnet scan after a delay
        queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.startFallbackDiscovery(onDeviceFound: onDeviceFound)
        }
    }

    private func startMulticastListener(onDeviceFound: @escaping (DeviceInfo) -> Void) {
        do {
            guard let nwPort = NWEndpoint.Port(rawValue: Discovery.port) else {
                log.error("Invalid discovery port: \(Discovery.port)")
                startFallbackDiscovery(onDeviceFound: onDeviceFound)
                return
            }
            let group = try NWMulticastGroup(for: [
                .hostPort(
                    host: NWEndpoint.Host(Discovery.multicastGroup),
                    port: nwPort
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
        let isAnnounce = json["announce"] as? Bool ?? true

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

        log.info("Found device via multicast: \(device.alias) at \(device.address):\(device.port)")
        onDeviceFound(device)

        // If this is an announcement, respond via HTTP register
        if isAnnounce {
            queue.async { [weak self] in
                self?.respondViaRegister(targetAddress: address, targetPort: port)
            }
        }
    }

    private func respondViaRegister(targetAddress: String, targetPort: Int) {
        let cleanAddress = targetAddress.replacingOccurrences(of: "%", with: "%25")
        guard let url = URL(string: "http://\(cleanAddress):\(targetPort)/api/localsend/v2/register") else {
            log.warning("Invalid address for register: \(targetAddress)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3

        guard let body = try? JSONSerialization.data(withJSONObject: getDeviceInfo()) else { return }
        request.httpBody = body

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: config)

        session.dataTask(with: request) { _, response, error in
            if let error = error {
                log.warning("Register response failed to \(targetAddress): \(error.localizedDescription)")
                // Fallback: send multicast with announce=false
                self.sendMulticastResponse()
            } else {
                log.debug("Register response sent to \(targetAddress)")
            }
            session.invalidateAndCancel()
        }.resume()
    }

    private func sendMulticastResponse() {
        guard let data = try? JSONSerialization.data(withJSONObject: getAnnouncement(announce: false)) else { return }
        multicastGroup?.send(content: data) { error in
            if let error = error {
                log.warning("Multicast response failed: \(error.localizedDescription)")
            }
        }
    }

    private func startAnnouncing() {
        // LocalSend-style burst: 0ms, 100ms, 500ms, 2000ms
        let burstDelays: [Double] = [0, 0.1, 0.5, 2.0]
        for delay in burstDelays {
            queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.sendAnnouncement()
            }
        }

        // Then periodic every 5 seconds
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5.0, repeating: 5.0)
        timer.setEventHandler { [weak self] in
            self?.sendAnnouncement()
        }
        timer.resume()
        announceTimer = timer
    }

    private func sendAnnouncement() {
        guard let data = try? JSONSerialization.data(withJSONObject: getAnnouncement(announce: true)) else { return }

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

                // Try /api/localsend/v2/info first
                if let device = self.tryInfoEndpoint(ip: ip) {
                    onDeviceFound(device)
                    return
                }

                // Fallback to /api/ping
                if let device = self.tryPingEndpoint(ip: ip) {
                    onDeviceFound(device)
                }
            }
        }

        group.notify(queue: queue) {
            log.info("Fallback subnet scan completed")
        }
    }

    private func tryInfoEndpoint(ip: String) -> DeviceInfo? {
        guard let url = URL(string: "http://\(ip):\(Discovery.port)/api/localsend/v2/info") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0.5
        config.timeoutIntervalForResource = 1.0
        let session = URLSession(configuration: config)

        let semaphore = DispatchSemaphore(value: 0)
        var result: DeviceInfo?

        session.dataTask(with: request) { [weak self] data, _, error in
            defer { semaphore.signal() }
            guard let self = self, error == nil, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            guard let fp = json["fingerprint"] as? String, fp != String(self.fingerprint) else { return }
            let deviceType = json["deviceType"] as? String ?? "unknown"
            guard deviceType == "mobile" else { return }

            result = DeviceInfo(
                alias: json["alias"] as? String ?? ip,
                deviceType: deviceType,
                fingerprint: fp,
                address: ip,
                port: json["port"] as? Int ?? Int(Discovery.port)
            )
            log.info("Info endpoint found device at \(ip)")
        }.resume()

        _ = semaphore.wait(timeout: .now() + 1.0)
        session.invalidateAndCancel()
        return result
    }

    private func tryPingEndpoint(ip: String) -> DeviceInfo? {
        guard let url = URL(string: "http://\(ip):\(Discovery.port)/api/ping") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0.5
        config.timeoutIntervalForResource = 1.0
        let session = URLSession(configuration: config)

        let semaphore = DispatchSemaphore(value: 0)
        var result: DeviceInfo?

        session.dataTask(with: request) { data, _, error in
            defer { semaphore.signal() }
            guard error == nil, let data = data,
                  String(data: data, encoding: .utf8) == "pong" else { return }

            result = DeviceInfo(
                alias: ip,
                deviceType: "mobile",
                fingerprint: "fallback",
                address: ip,
                port: Int(Discovery.port)
            )
            log.info("Ping fallback found device at \(ip)")
        }.resume()

        _ = semaphore.wait(timeout: .now() + 1.0)
        session.invalidateAndCancel()
        return result
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
        multicastGroup?.cancel()
        multicastGroup = nil
        log.info("Discovery stopped")
    }
}
