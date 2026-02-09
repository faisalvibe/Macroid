import Foundation
import AppKit
import Combine

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

    private var discovery: Discovery?
    private var syncServer: SyncServer?
    private var syncClient: SyncClient?
    private var clipboardMonitor: ClipboardMonitor?
    private var isUpdatingFromRemote = false

    init() {
        setupSync()
    }

    deinit {
        stopAll()
    }

    private func setupSync() {
        syncServer = SyncServer()
        syncServer?.start { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isUpdatingFromRemote = true
                self.clipboardText = text
                self.clipboardMonitor?.writeToClipboard(text)
                self.isUpdatingFromRemote = false
            }
        }

        discovery = Discovery()
        discovery?.startDiscovery { [weak self] device in
            DispatchQueue.main.async {
                self?.connectedDevice = device
                self?.syncClient = SyncClient(peer: device)
            }
        }

        clipboardMonitor = ClipboardMonitor()
        clipboardMonitor?.startMonitoring { [weak self] newText in
            DispatchQueue.main.async {
                guard let self = self, !self.isUpdatingFromRemote else { return }
                if newText != self.clipboardText {
                    self.clipboardText = newText
                    self.syncClient?.sendClipboard(newText)
                }
            }
        }
    }

    func onTextEdited(_ text: String) {
        guard !isUpdatingFromRemote else { return }
        clipboardMonitor?.writeToClipboard(text)
        syncClient?.sendClipboard(text)
    }

    private func stopAll() {
        clipboardMonitor?.stopMonitoring()
        discovery?.stopDiscovery()
        syncServer?.stop()
    }
}
