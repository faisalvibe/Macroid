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

    /// Send image notification to peer (pull-based: peer fetches from our server)
    func sendImage(_ imageData: Data, localPort: UInt16) {
        // Build fetch URL that peer can use to download the image
        let localIP = getLocalIPAddress() ?? peer.address
        let fetchURL = "http://\(localIP):\(localPort)/api/image/latest"

        let payload: [String: Any] = [
            "fetch_url": fetchURL,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "origin": deviceFingerprint
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            AppLog.add("[SyncClient] Failed to serialize image notification")
            return
        }

        AppLog.add("[SyncClient] Sending image notification (\(imageData.count) bytes available at \(fetchURL))")
        sendHTTPPost(path: "/api/clipboard/image", body: body, attempt: 1) { success in
            if success {
                AppLog.add("[SyncClient] Image notification sent successfully")
            } else {
                AppLog.add("[SyncClient] ERROR: Failed to send image notification")
            }
        }
    }

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let sa = ptr.pointee.ifa_addr.pointee
            guard sa.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(ptr.pointee.ifa_addr, socklen_t(sa.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            address = String(cString: hostname)
            break
        }
        return address
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

        // Timeout - longer for image uploads
        let timeout: Double = path.contains("image") ? 30 : 5
        queue.asyncAfter(deadline: .now() + timeout) {
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
