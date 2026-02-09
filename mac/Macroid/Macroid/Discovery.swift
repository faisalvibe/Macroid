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
        AppLog.add("[Discovery] Starting with fingerprint: \(String(fingerprint))")
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
            AppLog.add("[Discovery] Multicast listener started on \(Discovery.multicastGroup):\(Discovery.port)")
            log.info("Multicast listener started on \(Discovery.multicastGroup):\(Discovery.port)")

        } catch {
            AppLog.add("[Discovery] ERROR: Multicast setup failed: \(error.localizedDescription)")
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

        AppLog.add("[Discovery] Found device via multicast: \(device.alias) at \(device.address):\(device.port)")
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
        guard let body = try? JSONSerialization.data(withJSONObject: getDeviceInfo()) else { return }
        let cleanAddress = targetAddress.replacingOccurrences(of: "%25", with: "").replacingOccurrences(of: "%", with: "")

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(targetPort)) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(cleanAddress), port: nwPort, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let httpRequest = "POST /api/localsend/v2/register HTTP/1.1\r\nHost: \(cleanAddress):\(targetPort)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                var requestData = httpRequest.data(using: .utf8)!
                requestData.append(body)
                connection.send(content: requestData, completion: .contentProcessed { error in
                    if let error = error {
                        AppLog.add("[Discovery] Register send to \(cleanAddress) failed: \(error.localizedDescription)")
                        self?.sendMulticastResponse()
                    } else {
                        AppLog.add("[Discovery] Register sent to \(cleanAddress):\(targetPort)")
                    }
                    connection.cancel()
                })
            case .failed(let error):
                AppLog.add("[Discovery] Register connect to \(cleanAddress) failed: \(error.localizedDescription)")
                self?.sendMulticastResponse()
                connection.cancel()
            default:
                break
            }
        }

        connection.start(queue: queue)

        // Timeout
        queue.asyncAfter(deadline: .now() + 3) {
            connection.cancel()
        }
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
        AppLog.add("[Discovery] Starting fallback subnet scan on \(subnet).0/24")
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

    /// Raw TCP HTTP GET using NWConnection - bypasses ATS
    private func rawHTTPGet(ip: String, port: UInt16, path: String, timeout: TimeInterval = 1.0) -> Data? {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?

        let connection = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: .tcp)
        var completed = false

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let request = "GET \(path) HTTP/1.1\r\nHost: \(ip):\(port)\r\nConnection: close\r\n\r\n"
                connection.send(content: request.data(using: .utf8), completion: .contentProcessed { error in
                    if error != nil {
                        if !completed { completed = true; semaphore.signal() }
                        return
                    }
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                        if !completed {
                            completed = true
                            if let data = data, let response = String(data: data, encoding: .utf8) {
                                // Extract body after \r\n\r\n
                                if let range = response.range(of: "\r\n\r\n") {
                                    let body = String(response[range.upperBound...])
                                    resultData = body.data(using: .utf8)
                                }
                            }
                            semaphore.signal()
                        }
                        connection.cancel()
                    }
                })
            case .failed(_), .cancelled:
                if !completed { completed = true; semaphore.signal() }
            default:
                break
            }
        }

        connection.start(queue: DispatchQueue(label: "com.macroid.scan.\(ip)"))
        _ = semaphore.wait(timeout: .now() + timeout)
        if !completed { completed = true; connection.cancel() }
        return resultData
    }

    private func tryInfoEndpoint(ip: String) -> DeviceInfo? {
        guard let data = rawHTTPGet(ip: ip, port: Discovery.port, path: "/api/localsend/v2/info"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        guard let fp = json["fingerprint"] as? String, fp != String(fingerprint) else { return nil }
        let deviceType = json["deviceType"] as? String ?? "unknown"
        guard deviceType == "mobile" else { return nil }

        let device = DeviceInfo(
            alias: json["alias"] as? String ?? ip,
            deviceType: deviceType,
            fingerprint: fp,
            address: ip,
            port: json["port"] as? Int ?? Int(Discovery.port)
        )
        AppLog.add("[Discovery] Fallback info found device at \(ip): \(device.alias)")
        return device
    }

    private func tryPingEndpoint(ip: String) -> DeviceInfo? {
        guard let data = rawHTTPGet(ip: ip, port: Discovery.port, path: "/api/ping"),
              let response = String(data: data, encoding: .utf8),
              response.contains("pong") else { return nil }

        let device = DeviceInfo(
            alias: ip,
            deviceType: "mobile",
            fingerprint: "fallback",
            address: ip,
            port: Int(Discovery.port)
        )
        AppLog.add("[Discovery] Fallback ping found device at \(ip)")
        return device
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
