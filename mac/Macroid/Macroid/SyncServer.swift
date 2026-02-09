import Foundation
import Network
import os.log

private let log = Logger(subsystem: "com.macroid", category: "SyncServer")

class SyncServer {
    private var listener: NWListener?
    private let port: UInt16 = Discovery.port
    private let queue = DispatchQueue(label: "com.macroid.server")
    private var lastClipboard = ""
    private var lastTimestamp: Int64 = 0
    private var onClipboardReceived: ((String) -> Void)?
    private let deviceFingerprint: String
    private let maxBodySize = 1_048_576 // 1MB

    init(fingerprint: String) {
        self.deviceFingerprint = fingerprint
    }

    func start(onClipboardReceived: @escaping (String) -> Void) {
        self.onClipboardReceived = onClipboardReceived

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    log.info("Server listening on port \(self.port)")
                case .failed(let error):
                    log.error("Server failed: \(error.localizedDescription)")
                default:
                    break
                }
            }

            listener?.start(queue: queue)
        } catch {
            log.error("Failed to start on port \(self.port): \(error.localizedDescription)")
            tryAlternatePort(onClipboardReceived: onClipboardReceived)
        }
    }

    private func tryAlternatePort(onClipboardReceived: @escaping (String) -> Void) {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port + 1)!)
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.stateUpdateHandler = { state in
                if case .ready = state {
                    log.info("Server listening on alternate port \(self.port + 1)")
                }
            }
            listener?.start(queue: queue)
        } catch {
            log.error("Failed to start on alternate port: \(error.localizedDescription)")
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data else {
                connection.cancel()
                return
            }

            if let error = error {
                log.warning("Connection receive error: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            let request = String(data: data, encoding: .utf8) ?? ""
            self.routeRequest(request, connection: connection)
        }
    }

    private func routeRequest(_ request: String, connection: NWConnection) {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"bad request\"}")
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"bad request\"}")
            return
        }

        let method = parts[0]
        let path = parts[1]

        if method == "GET" && path == "/api/ping" {
            sendResponse(connection: connection, status: 200, body: "pong", contentType: "text/plain")
        } else if method == "GET" && path == "/api/clipboard" {
            let json: [String: Any] = ["text": lastClipboard, "timestamp": lastTimestamp]
            if let data = try? JSONSerialization.data(withJSONObject: json),
               let body = String(data: data, encoding: .utf8) {
                sendResponse(connection: connection, status: 200, body: body)
            } else {
                sendResponse(connection: connection, status: 200, body: "{\"text\":\"\",\"timestamp\":0}")
            }
        } else if method == "POST" && path == "/api/clipboard" {
            handleClipboardPost(request: request, connection: connection)
        } else if method == "POST" && path.hasPrefix("/api/localsend/v2/register") {
            sendResponse(connection: connection, status: 200, body: "{\"status\":\"ok\"}")
        } else {
            sendResponse(connection: connection, status: 404, body: "{\"error\":\"not found\"}")
        }
    }

    private func handleClipboardPost(request: String, connection: NWConnection) {
        let parts = request.components(separatedBy: "\r\n\r\n")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"missing body\"}")
            return
        }

        let bodyString = parts[1]
        if bodyString.count > maxBodySize {
            log.warning("Rejected oversized request: \(bodyString.count) bytes")
            sendResponse(connection: connection, status: 413, body: "{\"error\":\"payload too large\"}")
            return
        }

        guard let bodyData = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            log.warning("Invalid JSON in clipboard POST")
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"invalid json\"}")
            return
        }

        let text = json["text"] as? String ?? ""
        let timestamp = json["timestamp"] as? Int64 ?? (json["timestamp"] as? Double).map { Int64($0) } ?? 0
        let origin = json["origin"] as? String ?? ""

        if origin == deviceFingerprint {
            log.debug("Ignoring echo from self")
            sendResponse(connection: connection, status: 200, body: "{\"status\":\"ignored\"}")
            return
        }

        if !text.isEmpty && timestamp > lastTimestamp {
            lastTimestamp = timestamp
            lastClipboard = text
            log.info("Received clipboard (\(text.count) chars) from origin=\(origin)")
            onClipboardReceived?(text)
        }

        sendResponse(connection: connection, status: 200, body: "{\"status\":\"ok\"}")
    }

    private func sendResponse(connection: NWConnection, status: Int, body: String, contentType: String = "application/json") {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 413: statusText = "Payload Too Large"
        default: statusText = "Error"
        }

        let response = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"

        let responseData = response.data(using: .utf8)!
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    func stop() {
        listener?.cancel()
        listener = nil
        log.info("Server stopped")
    }
}
