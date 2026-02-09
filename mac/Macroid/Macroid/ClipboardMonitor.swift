import Foundation
import AppKit
import os.log

private let log = Logger(subsystem: "com.macroid", category: "ClipboardMonitor")

class ClipboardMonitor {
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int = 0
    private var lastText: String = ""
    private var lastRemoteText: String = ""
    private var lastRemoteImageHash: Int = 0
    private let pasteboard = NSPasteboard.general
    private let queue = DispatchQueue(label: "com.macroid.clipboard")
    private let lock = NSLock()

    func startMonitoring(onClipboardChanged: @escaping (String) -> Void, onImageChanged: @escaping (Data) -> Void) {
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
                if let imageData = self.getCurrentImage() {
                    let hash = imageData.hashValue
                    self.lock.lock()
                    let isEcho = (hash == self.lastRemoteImageHash)
                    self.lock.unlock()

                    if isEcho {
                        log.debug("Skipping echo of remote image")
                    } else {
                        log.debug("Local clipboard image changed (\(imageData.count) bytes)")
                        onImageChanged(imageData)
                    }
                    return
                }

                let text = self.getCurrentClipboard()
                if text != self.lastText {
                    self.lastText = text

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
        lock.unlock()
        lastText = text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        log.debug("Wrote remote text to clipboard (\(text.count) chars)")
    }

    func writeImageToClipboard(_ imageData: Data) {
        lock.lock()
        lastRemoteImageHash = imageData.hashValue
        lock.unlock()
        pasteboard.clearContents()
        if let image = NSImage(data: imageData) {
            pasteboard.writeObjects([image])
        }
        lastChangeCount = pasteboard.changeCount
        log.debug("Wrote remote image to clipboard (\(imageData.count) bytes)")
    }

    private func getCurrentClipboard() -> String {
        return pasteboard.string(forType: .string) ?? ""
    }

    private func getCurrentImage() -> Data? {
        if pasteboard.types?.contains(.png) == true {
            return pasteboard.data(forType: .png)
        }
        if pasteboard.types?.contains(.tiff) == true,
           let tiffData = pasteboard.data(forType: .tiff),
           let bitmapRep = NSBitmapImageRep(data: tiffData) {
            return bitmapRep.representation(using: .png, properties: [:])
        }
        // Check for file URLs pointing to image files
        if pasteboard.types?.contains(.fileURL) == true,
           let urlString = pasteboard.string(forType: .fileURL),
           let url = URL(string: urlString) {
            let ext = url.pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "webp", "heic"].contains(ext) {
                if let data = try? Data(contentsOf: url) {
                    if let image = NSImage(data: data),
                       let tiffRep = image.tiffRepresentation,
                       let bitmapRep = NSBitmapImageRep(data: tiffRep) {
                        return bitmapRep.representation(using: .png, properties: [:])
                    }
                }
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
