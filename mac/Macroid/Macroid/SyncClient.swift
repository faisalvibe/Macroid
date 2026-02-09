import Foundation

class SyncClient {
    private var peer: DeviceInfo
    private let session: URLSession

    init(peer: DeviceInfo) {
        self.peer = peer
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        self.session = URLSession(configuration: config)
    }

    func sendClipboard(_ text: String) {
        let url = URL(string: "http://\(peer.address):\(peer.port)/api/clipboard")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "text": text,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = body

        session.dataTask(with: request) { _, _, error in
            // Sent (or failed silently)
        }.resume()
    }
}
