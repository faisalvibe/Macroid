import Foundation
import AppKit
import Combine
import os.log

private let log = Logger(subsystem: "com.macroid", category: "SyncManager")
private let maxHistory = 20

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
    @Published var clipboardImage: Data?
    @Published var connectedDevice: DeviceInfo?
    @Published var clipboardHistory: [String] = []
    @Published var localIP: String = ""
    @Published var connectionStatus: String = ""

    private var discovery: Discovery?
    private var syncServer: SyncServer?
    private var syncClient: SyncClient?
    private var clipboardMonitor: ClipboardMonitor?
    private let syncQueue = DispatchQueue(label: "com.macroid.syncmanager")
    @Published private(set) var isUpdatingFromRemote = false

    init() {
        setupSync()
    }

    deinit {
        stopAll()
    }

    private func setupSync() {
        let disc = Discovery()
        self.discovery = disc
        let fp = String(disc.fingerprint)

        DispatchQueue.main.async {
            self.localIP = disc.getLocalIPAddress() ?? "Unknown"
        }

        let onDeviceFound: (DeviceInfo) -> Void = { [weak self] device in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.connectedDevice = device
                self.syncClient = SyncClient(peer: device, fingerprint: fp)
                self.connectionStatus = ""
                log.info("Connected to \(device.alias) at \(device.address)")
            }
        }

        syncServer = SyncServer(fingerprint: fp)
        syncServer?.onPeerDiscovered = { [weak self] device in
            guard let self = self else { return }
            if self.connectedDevice == nil {
                log.info("Reverse discovery: connected to \(device.alias)")
                onDeviceFound(device)
            }
        }
        syncServer?.onImageReceived = { [weak self] imageData in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isUpdatingFromRemote = true
                self.clipboardImage = imageData
                self.clipboardText = ""
                self.clipboardMonitor?.writeImageToClipboard(imageData)
                self.isUpdatingFromRemote = false
                log.debug("Applied remote image update (\(imageData.count) bytes)")
            }
        }
        syncServer?.start { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isUpdatingFromRemote = true
                self.clipboardText = text
                self.clipboardImage = nil
                self.clipboardMonitor?.writeToClipboard(text)
                self.addToHistory(text)
                self.isUpdatingFromRemote = false
                log.debug("Applied remote clipboard update")
            }
        }

        discovery?.startDiscovery(onDeviceFound: onDeviceFound)

        clipboardMonitor = ClipboardMonitor()
        clipboardMonitor?.startMonitoring(
            onClipboardChanged: { [weak self] newText in
                DispatchQueue.main.async {
                    guard let self = self, !self.isUpdatingFromRemote else { return }
                    if newText != self.clipboardText {
                        self.clipboardText = newText
                        self.clipboardImage = nil
                        self.syncClient?.sendClipboard(newText)
                        self.addToHistory(newText)
                        log.debug("Local clipboard change synced")
                    }
                }
            },
            onImageChanged: { [weak self] imageData in
                DispatchQueue.main.async {
                    guard let self = self, !self.isUpdatingFromRemote else { return }
                    self.clipboardImage = imageData
                    self.clipboardText = ""
                    self.syncClient?.sendImage(imageData)
                    log.debug("Local image change synced (\(imageData.count) bytes)")
                }
            }
        )
    }

    func onTextEdited(_ text: String) {
        guard !isUpdatingFromRemote else { return }
        clipboardImage = nil
        clipboardMonitor?.writeToClipboard(text)
        syncClient?.sendClipboard(text)
    }

    func clearHistory() {
        clipboardHistory.removeAll()
    }

    func restoreFromHistory(_ text: String) {
        clipboardText = text
        clipboardImage = nil
        clipboardMonitor?.writeToClipboard(text)
        syncClient?.sendClipboard(text)
    }

    func connectManually(ip: String) {
        let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        connectionStatus = "Connecting..."
        let fp = String(discovery?.fingerprint ?? Substring("manual"))
        let port = Int(Discovery.port)
        let url = URL(string: "http://\(trimmed):\(port)/api/ping")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                log.error("Manual connect to \(trimmed) failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.connectionStatus = "Failed: \(error.localizedDescription)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if self.connectedDevice == nil {
                            self.connectionStatus = ""
                        }
                    }
                }
                return
            }

            let device = DeviceInfo(
                alias: trimmed,
                deviceType: "mobile",
                fingerprint: "manual",
                address: trimmed,
                port: port
            )

            DispatchQueue.main.async {
                self.connectedDevice = device
                self.syncClient = SyncClient(peer: device, fingerprint: fp)
                self.connectionStatus = ""
                log.info("Manually connected to \(trimmed)")
            }
        }.resume()
    }

    private func addToHistory(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        clipboardHistory.removeAll { $0 == text }
        clipboardHistory.insert(text, at: 0)
        if clipboardHistory.count > maxHistory {
            clipboardHistory = Array(clipboardHistory.prefix(maxHistory))
        }
    }

    private func stopAll() {
        clipboardMonitor?.stopMonitoring()
        discovery?.stopDiscovery()
        syncServer?.stop()
        log.info("All sync components stopped")
    }
}
