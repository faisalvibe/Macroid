import Foundation
import Network
import os.log

private let log = Logger(subsystem: "com.macroid", category: "SyncClient")

class SyncClient {
    private var peer: DeviceInfo
    private let deviceFingerprint: String
    private let maxRetries = 3
    private let queue = DispatchQueue(label: "com.macroid.syncclient")

    init(peer: DeviceInfo, fingerprint: String) {
        self.peer = peer
        self.deviceFingerprint = fingerprint
        AppLog.add("[SyncClient] Initialized for peer: \(peer.alias) at \(peer.address):\(peer.port)")
    }

    func sendClipboard(_ text: String) {
        let payload: [String: Any] = [
            "text": text,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "origin": deviceFingerprint
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            AppLog.add("[SyncClient] Failed to serialize clipboard payload")
            return
        }

        AppLog.add("[SyncClient] Sending clipboard (\(text.count) chars) to \(peer.alias)")
        sendHTTPPost(path: "/api/clipboard", body: body, attempt: 1) { success in
            if success {
                AppLog.add("[SyncClient] Clipboard sent successfully")
            } else {
                AppLog.add("[SyncClient] ERROR: Failed to send clipboard after retries")
            }
        }
    }

    func sendImage(_ imageData: Data) {
        let payload: [String: Any] = [
            "image": imageData.base64EncodedString(),
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "origin": deviceFingerprint
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            AppLog.add("[SyncClient] Failed to serialize image payload")
            return
        }

        AppLog.add("[SyncClient] Sending image (\(imageData.count) bytes) to \(peer.alias)")
        sendHTTPPost(path: "/api/clipboard/image", body: body, attempt: 1) { success in
            if success {
                AppLog.add("[SyncClient] Image sent successfully")
            } else {
                AppLog.add("[SyncClient] ERROR: Failed to send image")
            }
        }
    }

    private func sendHTTPPost(path: String, body: Data, attempt: Int, completion: @escaping (Bool) -> Void) {
        guard let port = NWEndpoint.Port(rawValue: UInt16(peer.port)) else {
            AppLog.add("[SyncClient] Invalid port: \(peer.port)")
            completion(false)
            return
        }

        let host = NWEndpoint.Host(peer.address)
        let connection = NWConnection(host: host, port: port, using: .tcp)
        var completed = false

        let httpRequest = "POST \(path) HTTP/1.1\r\nHost: \(peer.address):\(peer.port)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var requestData = httpRequest.data(using: .utf8)!
        requestData.append(body)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self, !completed else { return }
            switch state {
            case .ready:
                AppLog.add("[SyncClient] TCP connected to \(self.peer.address):\(self.peer.port) for \(path)")
                connection.send(content: requestData, completion: .contentProcessed { error in
                    if let error = error {
                        AppLog.add("[SyncClient] Send error: \(error.localizedDescription)")
                        completed = true
                        connection.cancel()
                        self.retryIfNeeded(path: path, body: body, attempt: attempt, completion: completion)
                        return
                    }
                    // Read response
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                        completed = true
                        connection.cancel()
                        if let data = data, let response = String(data: data, encoding: .utf8) {
                            let statusLine = response.components(separatedBy: "\r\n").first ?? ""
                            AppLog.add("[SyncClient] Response: \(statusLine)")
                            completion(statusLine.contains("200"))
                        } else {
                            AppLog.add("[SyncClient] No response data: \(error?.localizedDescription ?? "unknown")")
                            self.retryIfNeeded(path: path, body: body, attempt: attempt, completion: completion)
                        }
                    }
                })
            case .failed(let error):
                AppLog.add("[SyncClient] TCP connection failed: \(error.localizedDescription)")
                completed = true
                connection.cancel()
                self.retryIfNeeded(path: path, body: body, attempt: attempt, completion: completion)
            case .cancelled:
                if !completed {
                    completed = true
                    completion(false)
                }
            default:
                break
            }
        }

        connection.start(queue: queue)

        // Timeout
        queue.asyncAfter(deadline: .now() + 5) {
            if !completed {
                completed = true
                AppLog.add("[SyncClient] Timeout sending to \(path)")
                connection.cancel()
                self.retryIfNeeded(path: path, body: body, attempt: attempt, completion: completion)
            }
        }
    }

    private func retryIfNeeded(path: String, body: Data, attempt: Int, completion: @escaping (Bool) -> Void) {
        if attempt < maxRetries {
            let backoff = Double(1 << (attempt - 1)) * 0.5
            AppLog.add("[SyncClient] Retrying \(path) in \(backoff)s (attempt \(attempt)/\(maxRetries))")
            queue.asyncAfter(deadline: .now() + backoff) {
                self.sendHTTPPost(path: path, body: body, attempt: attempt + 1, completion: completion)
            }
        } else {
            AppLog.add("[SyncClient] ERROR: All \(maxRetries) retries exhausted for \(path)")
            completion(false)
        }
    }
}
