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

    private var discovery: Discovery?
    private var syncServer: SyncServer?
    private var syncClient: SyncClient?
    private var clipboardMonitor: ClipboardMonitor?
    private let syncQueue = DispatchQueue(label: "com.macroid.syncmanager")
    private var keepaliveTimer: DispatchSourceTimer?
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

        syncServer = SyncServer(fingerprint: fp)
        syncServer?.start { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isUpdatingFromRemote = true
                self.clipboardText = text
                self.clipboardMonitor?.writeToClipboard(text)
                self.addToHistory(text)
                self.isUpdatingFromRemote = false
                log.debug("Applied remote clipboard update")
            }
        }

        // Propagate actual server port to discovery announcements
        if let actualPort = syncServer?.actualPort {
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
        clipboardMonitor?.startMonitoring { [weak self] newText in
            DispatchQueue.main.async {
                guard let self = self, !self.isUpdatingFromRemote else { return }
                if newText != self.clipboardText {
                    self.clipboardText = newText
                    self.syncClient?.sendClipboard(newText)
                    self.addToHistory(newText)
                    log.debug("Local clipboard change synced")
                }
            }
        }

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
