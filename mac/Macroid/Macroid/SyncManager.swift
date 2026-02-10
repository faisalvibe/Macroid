import Foundation
import AppKit
import Combine
import Network
import os.log

private let log = Logger(subsystem: "com.macroid", category: "SyncManager")
private let maxHistory = 20
private let historyKey = "com.macroid.clipboardHistory"

struct DeviceInfo: Identifiable {
    let id = UUID()
    let alias: String
    let deviceType: String
    let fingerprint: String
    let address: String
    let port: Int
}

class SyncManager: ObservableObject {
    @Published var clipboardText: String = ""
    @Published var connectedDevice: DeviceInfo?
    @Published var clipboardHistory: [String] = []
    @Published var localIPAddress: String = ""
    @Published var connectionStatus: String = ""
    @Published var lastReceivedImage: Data?

    private var discovery: Discovery?
    private var syncServer: SyncServer?
    private var syncClient: SyncClient?
    private var clipboardMonitor: ClipboardMonitor?
    private let syncQueue = DispatchQueue(label: "com.macroid.syncmanager")
    private var keepaliveTimer: DispatchSourceTimer?
    private var fingerprint: String = ""
    @Published private(set) var isUpdatingFromRemote = false

    init() {
        clipboardHistory = UserDefaults.standard.stringArray(forKey: historyKey) ?? []
        setupSync()
    }

    deinit {
        stopAll()
    }

    private func setupSync() {
        AppLog.add("[SyncManager] Setting up...")

        let disc = Discovery()
        self.discovery = disc
        let fp = String(disc.fingerprint)
        self.fingerprint = fp
        self.localIPAddress = disc.getLocalIPAddress() ?? "Unknown"

        AppLog.add("[SyncManager] Local IP: \(localIPAddress), Fingerprint: \(fp)")

        let server = SyncServer(fingerprint: fp)
        server.deviceInfoProvider = { disc.getDeviceInfo() }
        self.syncServer = server

        server.onDeviceRegistered = { [weak self] device in
            guard let self = self else { return }
            AppLog.add("[SyncManager] Device registered via HTTP: \(device.alias) at \(device.address):\(device.port)")
            DispatchQueue.main.async {
                self.connectedDevice = device
                self.syncClient = SyncClient(peer: device, fingerprint: fp)
            }
        }

        server.onPeerActivity = { [weak self] remoteAddress in
            guard let self = self, self.connectedDevice == nil else { return }
            self.syncQueue.async {
                let portsToTry: [UInt16] = [Discovery.port, Discovery.port + 1, Discovery.port + 2]
                for port in portsToTry {
                    if let data = disc.rawHTTPGet(ip: remoteAddress, port: port, path: "/api/localsend/v2/info"),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let alias = json["alias"] as? String ?? remoteAddress
                        let peerPort = json["port"] as? Int ?? Int(port)
                        let device = DeviceInfo(alias: alias, deviceType: "mobile", fingerprint: json["fingerprint"] as? String ?? "peer", address: remoteAddress, port: peerPort)
                        DispatchQueue.main.async {
                            self.connectedDevice = device
                            self.syncClient = SyncClient(peer: device, fingerprint: fp)
                            AppLog.add("[SyncManager] Peer detected: \(alias) at \(remoteAddress):\(peerPort)")
                        }
                        return
                    }
                }
                // Fallback
                let device = DeviceInfo(alias: remoteAddress, deviceType: "mobile", fingerprint: "peer", address: remoteAddress, port: Int(Discovery.port))
                DispatchQueue.main.async {
                    self.connectedDevice = device
                    self.syncClient = SyncClient(peer: device, fingerprint: fp)
                    AppLog.add("[SyncManager] Peer detected (no info): \(remoteAddress)")
                }
            }
        }

        server.onReady = { [weak self] in
            guard let self = self, let disc = self.discovery, let server = self.syncServer else { return }
            let actualPort = server.actualPort
            disc.announcePort = actualPort
            AppLog.add("[SyncManager] Server ready on port \(actualPort)")
        }

        server.start(onClipboardReceived: { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isUpdatingFromRemote = true
                self.clipboardText = text
                self.clipboardMonitor?.writeToClipboard(text)
                self.addToHistory(text)
                self.isUpdatingFromRemote = false
                AppLog.add("[SyncManager] Received remote clipboard (\(text.count) chars)")
            }
        }, onImageReceived: { [weak self] imageData in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.lastReceivedImage = imageData
                self.clipboardMonitor?.writeImageToClipboard(imageData)
                AppLog.add("[SyncManager] Received remote image (\(imageData.count) bytes)")
            }
        })

        discovery?.startDiscovery { [weak self] device in
            AppLog.add("[SyncManager] Discovery found device: \(device.alias) at \(device.address):\(device.port)")
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.connectedDevice = device
                self.syncClient = SyncClient(peer: device, fingerprint: fp)
            }
            // Register with the discovered device so it knows about us
            self?.registerWithPeer(ip: device.address, port: UInt16(device.port))
        }

        clipboardMonitor = ClipboardMonitor()
        clipboardMonitor?.startMonitoring(onClipboardChanged: { [weak self] newText in
            DispatchQueue.main.async {
                guard let self = self, !self.isUpdatingFromRemote else { return }
                if newText != self.clipboardText {
                    self.clipboardText = newText
                    self.syncClient?.sendClipboard(newText)
                    self.addToHistory(newText)
                }
            }
        }, onImageChanged: { [weak self] imageData in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.lastReceivedImage = imageData
            }
            self.syncClient?.sendImage(imageData)
        })

        startKeepalive()
        AppLog.add("[SyncManager] Setup complete")
    }

    private func startKeepalive() {
        let timer = DispatchSource.makeTimerSource(queue: syncQueue)
        timer.schedule(deadline: .now() + 10, repeating: 10.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, let device = self.connectedDevice else { return }
            self.rawPing(host: device.address, port: UInt16(device.port)) { reachable in
                DispatchQueue.main.async {
                    if !reachable && self.connectedDevice != nil {
                        AppLog.add("[SyncManager] Keepalive failed for \(device.alias), disconnecting")
                        self.connectedDevice = nil
                    }
                }
            }
        }
        timer.resume()
        keepaliveTimer = timer
    }

    func connectByIP(_ ip: String, port: Int = Int(Discovery.port)) {
        connectionStatus = "Connecting..."
        AppLog.add("[SyncManager] Connecting by IP to \(ip), trying ports \(port), \(port+1), \(port+2)...")

        // Try the standard port, then alternates (in case of port conflict)
        let portsToTry: [UInt16] = [UInt16(port), UInt16(port + 1), UInt16(port + 2)]
        tryNextPort(ip: ip, ports: portsToTry, index: 0)
    }

    private func tryNextPort(ip: String, ports: [UInt16], index: Int) {
        guard index < ports.count else {
            DispatchQueue.main.async {
                self.connectionStatus = "Failed to connect to \(ip)"
                AppLog.add("[SyncManager] ERROR: Failed to connect to \(ip) on all ports")
            }
            return
        }

        let port = ports[index]
        rawPing(host: ip, port: port) { [weak self] reachable in
            guard let self = self else { return }
            if reachable {
                DispatchQueue.main.async {
                    let device = DeviceInfo(
                        alias: ip,
                        deviceType: "mobile",
                        fingerprint: "manual",
                        address: ip,
                        port: Int(port)
                    )
                    self.connectedDevice = device
                    self.syncClient = SyncClient(peer: device, fingerprint: self.fingerprint)
                    self.connectionStatus = "Connected to \(ip):\(port)"
                    AppLog.add("[SyncManager] Connected to \(ip):\(port)")
                    // Register with the peer so it knows we're connected
                    self.registerWithPeer(ip: ip, port: port)
                }
            } else {
                AppLog.add("[SyncManager] Port \(port) failed, trying next...")
                self.tryNextPort(ip: ip, ports: ports, index: index + 1)
            }
        }
    }

    /// Register with the peer so it knows we're connected
    private func registerWithPeer(ip: String, port: UInt16) {
        guard let disc = discovery,
              let body = try? JSONSerialization.data(withJSONObject: disc.getDeviceInfo()),
              let nwPort = NWEndpoint.Port(rawValue: port) else { return }

        let connection = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: .tcp)
        var completed = false

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let httpRequest = "POST /api/localsend/v2/register HTTP/1.1\r\nHost: \(ip):\(port)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                var requestData = httpRequest.data(using: .utf8)!
                requestData.append(body)
                connection.send(content: requestData, completion: .contentProcessed { _ in
                    if !completed {
                        completed = true
                        AppLog.add("[SyncManager] Register sent to \(ip):\(port)")
                    }
                    connection.cancel()
                })
            case .failed(_):
                if !completed { completed = true }
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: syncQueue)
        syncQueue.asyncAfter(deadline: .now() + 3) {
            if !completed { completed = true; connection.cancel() }
        }
    }

    /// Raw TCP ping using NWConnection - bypasses URLSession/ATS entirely
    private func rawPing(host: String, port: UInt16, completion: @escaping (Bool) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            AppLog.add("[Ping] Invalid port: \(port)")
            completion(false)
            return
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        var completed = false

        connection.stateUpdateHandler = { state in
            guard !completed else { return }
            switch state {
            case .ready:
                AppLog.add("[Ping] TCP connected to \(host):\(port), sending GET /api/ping")
                let request = "GET /api/ping HTTP/1.1\r\nHost: \(host):\(port)\r\nConnection: close\r\n\r\n"
                connection.send(content: request.data(using: .utf8), completion: .contentProcessed { error in
                    if let error = error {
                        AppLog.add("[Ping] Send error: \(error.localizedDescription)")
                        if !completed {
                            completed = true
                            connection.cancel()
                            completion(false)
                        }
                        return
                    }
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                        guard !completed else { return }
                        completed = true
                        connection.cancel()

                        if let data = data, let response = String(data: data, encoding: .utf8) {
                            let hasPong = response.contains("pong")
                            AppLog.add("[Ping] Response from \(host): \(hasPong ? "pong OK" : String(response.prefix(200)))")
                            completion(hasPong)
                        } else {
                            AppLog.add("[Ping] No data from \(host): \(error?.localizedDescription ?? "unknown")")
                            completion(false)
                        }
                    }
                })
            case .waiting(let error):
                AppLog.add("[Ping] Waiting for \(host):\(port): \(error.localizedDescription)")
            case .failed(let error):
                AppLog.add("[Ping] TCP connection to \(host):\(port) FAILED: \(error.localizedDescription)")
                if !completed {
                    completed = true
                    connection.cancel()
                    completion(false)
                }
            default:
                break
            }
        }

        connection.start(queue: syncQueue)

        syncQueue.asyncAfter(deadline: .now() + 3) {
            if !completed {
                completed = true
                AppLog.add("[Ping] TIMEOUT connecting to \(host):\(port)")
                connection.cancel()
                completion(false)
            }
        }
    }

    func onTextEdited(_ text: String) {
        guard !isUpdatingFromRemote else { return }
        clipboardMonitor?.writeToClipboard(text)
        syncClient?.sendClipboard(text)
    }

    func clearHistory() {
        clipboardHistory.removeAll()
        saveHistory()
    }

    func restoreFromHistory(_ text: String) {
        clipboardText = text
        clipboardMonitor?.writeToClipboard(text)
        syncClient?.sendClipboard(text)
    }

    private func addToHistory(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        clipboardHistory.removeAll { $0 == text }
        clipboardHistory.insert(text, at: 0)
        if clipboardHistory.count > maxHistory {
            clipboardHistory = Array(clipboardHistory.prefix(maxHistory))
        }
        saveHistory()
    }

    private func saveHistory() {
        UserDefaults.standard.set(clipboardHistory, forKey: historyKey)
    }

    private func stopAll() {
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
        clipboardMonitor?.stopMonitoring()
        discovery?.stopDiscovery()
        syncServer?.stop()
        AppLog.add("[SyncManager] Stopped all components")
    }
}
