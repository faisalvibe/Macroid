import Foundation
import AppKit
import os.log

private let log = Logger(subsystem: "com.macroid", category: "ClipboardMonitor")

class ClipboardMonitor {
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int = 0
    private var lastText: String = ""
    private var lastRemoteText: String = ""
    private let pasteboard = NSPasteboard.general
    private let queue = DispatchQueue(label: "com.macroid.clipboard")
    private let lock = NSLock()

    func startMonitoring(onClipboardChanged: @escaping (String) -> Void) {
        lastChangeCount = pasteboard.changeCount
        lastText = getCurrentClipboard()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }

            let currentCount = self.pasteboard.changeCount
            if currentCount != self.lastChangeCount {
                self.lastChangeCount = currentCount

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

    private func getCurrentClipboard() -> String {
        return pasteboard.string(forType: .string) ?? ""
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
        log.info("Clipboard monitoring stopped")
    }
}
