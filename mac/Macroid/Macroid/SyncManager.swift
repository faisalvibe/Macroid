import Foundation
import AppKit
import Combine
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
        let disc = Discovery()
        self.discovery = disc
        let fp = String(disc.fingerprint)
        self.fingerprint = fp
        self.localIPAddress = disc.getLocalIPAddress() ?? "Unknown"

        let server = SyncServer(fingerprint: fp)
        server.deviceInfoProvider = { disc.getDeviceInfo() }
        self.syncServer = server

        server.onDeviceRegistered = { [weak self] device in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.connectedDevice = device
                self.syncClient = SyncClient(peer: device, fingerprint: fp)
                log.info("Device registered via HTTP: \(device.alias) at \(device.address)")
            }
        }

        server.start(onClipboardReceived: { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isUpdatingFromRemote = true
                self.clipboardText = text
                self.clipboardMonitor?.writeToClipboard(text)
                self.addToHistory(text)
                self.isUpdatingFromRemote = false
                log.debug("Applied remote clipboard update")
            }
        }, onImageReceived: { [weak self] imageData in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.clipboardMonitor?.writeImageToClipboard(imageData)
                log.debug("Applied remote image clipboard update")
            }
        })

        // Propagate actual server port to discovery announcements
        if let actualPort = server.actualPort as UInt16? {
            disc.announcePort = actualPort
        }

        discovery?.startDiscovery { [weak self] device in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.connectedDevice = device
                self.syncClient = SyncClient(peer: device, fingerprint: fp)
                log.info("Connected to \(device.alias) at \(device.address)")
            }
        }

        clipboardMonitor = ClipboardMonitor()
        clipboardMonitor?.startMonitoring(onClipboardChanged: { [weak self] newText in
            DispatchQueue.main.async {
                guard let self = self, !self.isUpdatingFromRemote else { return }
                if newText != self.clipboardText {
                    self.clipboardText = newText
                    self.syncClient?.sendClipboard(newText)
                    self.addToHistory(newText)
                    log.debug("Local clipboard change synced")
                }
            }
        }, onImageChanged: { [weak self] imageData in
            guard let self = self else { return }
            self.syncClient?.sendImage(imageData)
            log.debug("Local image clipboard change synced")
        })

        startKeepalive()
    }

    private func startKeepalive() {
        let timer = DispatchSource.makeTimerSource(queue: syncQueue)
        timer.schedule(deadline: .now() + 10, repeating: 10.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, let device = self.connectedDevice else { return }
            guard let url = URL(string: "http://\(device.address):\(device.port)/api/ping") else { return }

            var request = URLRequest(url: url)
            request.timeoutInterval = 3

            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 3
            let session = URLSession(configuration: config)

            session.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                let isReachable = error == nil && data != nil &&
                    String(data: data!, encoding: .utf8) == "pong"

                DispatchQueue.main.async {
                    if !isReachable && self.connectedDevice != nil {
                        log.warning("Keepalive failed for \(device.alias), marking disconnected")
                        self.connectedDevice = nil
                    }
                }
                session.invalidateAndCancel()
            }.resume()
        }
        timer.resume()
        keepaliveTimer = timer
    }

    func connectByIP(_ ip: String, port: Int = Int(Discovery.port)) {
        connectionStatus = "Connecting..."

        guard let url = URL(string: "http://\(ip):\(port)/api/ping") else {
            log.error("Invalid IP address: \(ip)")
            connectionStatus = "Failed: invalid IP"
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: config)

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            let isReachable = error == nil && data != nil &&
                String(data: data!, encoding: .utf8) == "pong"

            DispatchQueue.main.async {
                if isReachable {
                    let device = DeviceInfo(
                        alias: ip,
                        deviceType: "mobile",
                        fingerprint: "manual",
                        address: ip,
                        port: port
                    )
                    self.connectedDevice = device
                    self.syncClient = SyncClient(peer: device, fingerprint: self.fingerprint)
                    self.connectionStatus = "Connected to \(ip)"
                    log.info("Manually connected to \(ip):\(port)")
                } else {
                    self.connectionStatus = "Failed to connect to \(ip)"
                    log.warning("Failed to connect to \(ip):\(port)")
                }
            }
            session.invalidateAndCancel()
        }.resume()
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
        log.info("All sync components stopped")
    }
}
