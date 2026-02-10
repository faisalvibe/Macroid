import Foundation
import os.log

private let logger = Logger(subsystem: "com.macroid", category: "AppLog")

class AppLog: ObservableObject {
    static let shared = AppLog()
    @Published var entries: [String] = []
    private let maxEntries = 200
    private let queue = DispatchQueue(label: "com.macroid.applog")

    static func add(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = "[\(timestamp)] \(message)"
        logger.info("\(entry)")

        DispatchQueue.main.async {
            shared.entries.append(entry)
            if shared.entries.count > shared.maxEntries {
                shared.entries.removeFirst(shared.entries.count - shared.maxEntries)
            }
        }
    }

    func allText() -> String {
        entries.joined(separator: "\n")
    }

    func clear() {
        entries.removeAll()
    }
}
