import Foundation
import AppKit
import os.log

private let log = Logger(subsystem: "com.macroid", category: "ClipboardMonitor")

class ClipboardMonitor {
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int = 0
    private var lastText: String = ""
    private var lastRemoteText: String = ""
    private var lastImageData: Data?
    private var lastRemoteImageData: Data?
    private let pasteboard = NSPasteboard.general
    private let queue = DispatchQueue(label: "com.macroid.clipboard")
    private let lock = NSLock()

    func startMonitoring(onClipboardChanged: @escaping (String) -> Void, onImageChanged: ((Data) -> Void)? = nil) {
        lastChangeCount = pasteboard.changeCount
        lastText = getCurrentClipboard()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }

            let currentCount = self.pasteboard.changeCount
            if currentCount != self.lastChangeCount {
                self.lastChangeCount = currentCount

                // Check for image first
                if let imageData = self.getCurrentClipboardImage() {
                    if imageData != self.lastImageData {
                        self.lastImageData = imageData
                        self.lastText = ""

                        self.lock.lock()
                        let isEcho = (imageData == self.lastRemoteImageData)
                        self.lock.unlock()

                        if isEcho {
                            log.debug("Skipping echo of remote image")
                        } else {
                            log.debug("Local clipboard image changed (\(imageData.count) bytes)")
                            onImageChanged?(imageData)
                        }
                    }
                    return
                }

                // Check for text
                let text = self.getCurrentClipboard()
                if text != self.lastText {
                    self.lastText = text
                    self.lastImageData = nil

                    self.lock.lock()
                    let isEcho = (text == self.lastRemoteText)
                    self.lock.unlock()

                    if isEcho {
                        log.debug("Skipping echo of remote text")
                    } else {
                        log.debug("Local clipboard changed (\(text.count) chars)")
                        onClipboardChanged(text)
                    }
                }
            }
        }
        timer.resume()
        self.timer = timer
        log.info("Clipboard monitoring started")
    }

    func writeToClipboard(_ text: String) {
        lock.lock()
        lastRemoteText = text
        lastRemoteImageData = nil
        lock.unlock()
        lastText = text
        lastImageData = nil
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        log.debug("Wrote remote text to clipboard (\(text.count) chars)")
    }

    func writeImageToClipboard(_ data: Data) {
        lock.lock()
        lastRemoteImageData = data
        lastRemoteText = ""
        lock.unlock()
        lastImageData = data
        lastText = ""
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        lastChangeCount = pasteboard.changeCount
        log.debug("Wrote remote image to clipboard (\(data.count) bytes)")
    }

    private func getCurrentClipboard() -> String {
        return pasteboard.string(forType: .string) ?? ""
    }

    private func getCurrentClipboardImage() -> Data? {
        let types = pasteboard.types ?? []
        if types.contains(.png) {
            return pasteboard.data(forType: .png)
        }
        if types.contains(.tiff) {
            if let tiffData = pasteboard.data(forType: .tiff),
               let image = NSImage(data: tiffData),
               let tiffRep = image.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffRep),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                return pngData
            }
        }
        return nil
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
        log.info("Clipboard monitoring stopped")
    }
}
