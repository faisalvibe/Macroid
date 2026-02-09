import Foundation
import os.log

private let log = Logger(subsystem: "com.macroid", category: "SyncClient")

class SyncClient {
    private var peer: DeviceInfo
    private let session: URLSession
    private let deviceFingerprint: String
    private let maxRetries = 3

    init(peer: DeviceInfo, fingerprint: String) {
        self.peer = peer
        self.deviceFingerprint = fingerprint
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        self.session = URLSession(configuration: config)
    }

    func sendClipboard(_ text: String) {
        guard let url = URL(string: "http://\(peer.address):\(peer.port)/api/clipboard") else {
            log.error("Invalid peer URL: \(self.peer.address):\(self.peer.port)")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "text": text,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "origin": deviceFingerprint
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = body

        sendWithRetry(request: request, text: text, attempt: 1)
    }

    func sendImage(_ imageData: Data) {
        guard let url = URL(string: "http://\(peer.address):\(peer.port)/api/clipboard/image") else {
            log.error("Invalid peer URL for image: \(self.peer.address):\(self.peer.port)")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "image": imageData.base64EncodedString(),
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "origin": deviceFingerprint
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        request.httpBody = body

        session.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }
            if let error = error {
                log.error("Image send failed: \(error.localizedDescription)")
            } else {
                log.debug("Sent image (\(imageData.count) bytes) to \(self.peer.alias)")
            }
        }.resume()
    }

    private func sendWithRetry(request: URLRequest, text: String, attempt: Int) {
        session.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }

            if let error = error {
                if attempt < self.maxRetries {
                    let backoff = Double(1 << (attempt - 1)) * 0.5
                    log.warning("Send failed (attempt \(attempt)/\(self.maxRetries)), retrying in \(backoff)s: \(error.localizedDescription)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + backoff) {
                        self.sendWithRetry(request: request, text: text, attempt: attempt + 1)
                    }
                } else {
                    log.error("Send failed after \(self.maxRetries) attempts: \(error.localizedDescription)")
                }
                return
            }

            log.debug("Sent clipboard (\(text.count) chars) to \(self.peer.alias)")
        }.resume()
    }
}
