import Foundation
import AppKit

class ClipboardMonitor {
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int = 0
    private var lastText: String = ""
    private var ignoreNextChange = false
    private let pasteboard = NSPasteboard.general
    private let queue = DispatchQueue(label: "com.macroid.clipboard")

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

                if self.ignoreNextChange {
                    self.ignoreNextChange = false
                    return
                }

                let text = self.getCurrentClipboard()
                if text != self.lastText {
                    self.lastText = text
                    onClipboardChanged(text)
                }
            }
        }
        timer.resume()
        self.timer = timer
    }

    func writeToClipboard(_ text: String) {
        ignoreNextChange = true
        lastText = text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    private func getCurrentClipboard() -> String {
        return pasteboard.string(forType: .string) ?? ""
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
    }
}
