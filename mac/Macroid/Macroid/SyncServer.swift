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
    private var onImageReceived: ((Data) -> Void)?
    private let deviceFingerprint: String
    private let maxBodySize = 1_048_576 // 1MB
    private let maxImageSize = 10_485_760 // 10MB
    private(set) var actualPort: UInt16
    var deviceInfoProvider: (() -> [String: Any])?
    var onDeviceRegistered: ((DeviceInfo) -> Void)?
    var onPeerActivity: ((String) -> Void)?

    init(fingerprint: String) {
        self.deviceFingerprint = fingerprint
        self.actualPort = Discovery.port
    }

    var onReady: (() -> Void)?

    func start(onClipboardReceived: @escaping (String) -> Void, onImageReceived: @escaping (Data) -> Void = { _ in }) {
        self.onClipboardReceived = onClipboardReceived
        self.onImageReceived = onImageReceived
        startOnPort(port)
    }

    private func startOnPort(_ targetPort: UInt16) {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true

            guard let nwPort = NWEndpoint.Port(rawValue: targetPort) else {
                log.error("Invalid port number: \(targetPort)")
                return
            }
            listener = try NWListener(using: params, on: nwPort)

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.actualPort = targetPort
                    AppLog.add("[SyncServer] Listening on port \(targetPort)")
                    log.info("Server listening on port \(targetPort)")
                    self.onReady?()
                case .failed(let error):
                    AppLog.add("[SyncServer] ERROR on port \(targetPort): \(error.localizedDescription)")
                    log.error("Server failed on port \(targetPort): \(error.localizedDescription)")
                    self.listener?.cancel()
                    self.listener = nil
                    // Try alternate ports if the primary port failed
                    if targetPort == self.port {
                        AppLog.add("[SyncServer] Trying alternate port \(self.port + 1)...")
                        self.startOnPort(self.port + 1)
                    } else if targetPort == self.port + 1 {
                        AppLog.add("[SyncServer] Trying alternate port \(self.port + 2)...")
                        self.startOnPort(self.port + 2)
                    } else {
                        AppLog.add("[SyncServer] ERROR: All ports failed, server not running")
                    }
                default:
                    break
                }
            }

            listener?.start(queue: queue)
        } catch {
            AppLog.add("[SyncServer] ERROR creating listener on port \(targetPort): \(error.localizedDescription)")
            log.error("Failed to create listener on port \(targetPort): \(error.localizedDescription)")
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
        } else if method == "POST" && path == "/api/clipboard/image" {
            handleImagePost(request: request, connection: connection)
        } else if method == "GET" && path == "/api/localsend/v2/info" {
            handleInfoGet(connection: connection)
        } else if method == "POST" && path.hasPrefix("/api/localsend/v2/register") {
            handleRegisterPost(request: request, connection: connection)
        } else {
            sendResponse(connection: connection, status: 404, body: "{\"error\":\"not found\"}")
        }
    }

    private func handleInfoGet(connection: NWConnection) {
        let info = deviceInfoProvider?() ?? [
            "alias": Host.current().localizedName ?? "Mac",
            "version": "2.1",
            "deviceType": "desktop",
            "fingerprint": deviceFingerprint,
            "download": false
        ]
        if let data = try? JSONSerialization.data(withJSONObject: info),
           let body = String(data: data, encoding: .utf8) {
            sendResponse(connection: connection, status: 200, body: body)
        } else {
            sendResponse(connection: connection, status: 200, body: "{\"status\":\"ok\"}")
        }
    }

    private func handleRegisterPost(request: String, connection: NWConnection) {
        let parts = request.components(separatedBy: "\r\n\r\n")
        var responseInfo = deviceInfoProvider?() ?? [
            "alias": Host.current().localizedName ?? "Mac",
            "version": "2.1",
            "deviceType": "desktop",
            "fingerprint": deviceFingerprint
        ]

        if parts.count >= 2 {
            let bodyString = parts[1]
            if let bodyData = bodyString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                let fp = json["fingerprint"] as? String ?? ""
                let alias = json["alias"] as? String ?? "Unknown"
                let deviceType = json["deviceType"] as? String ?? "unknown"
                let port = json["port"] as? Int ?? Int(Discovery.port)

                if !fp.isEmpty && fp != deviceFingerprint {
                    // Extract remote IP from connection
                    var remoteAddress = "unknown"
                    if case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint {
                        remoteAddress = "\(host)"
                    }

                    let device = DeviceInfo(
                        alias: alias,
                        deviceType: deviceType,
                        fingerprint: fp,
                        address: remoteAddress,
                        port: port
                    )
                    log.info("Device registered via HTTP: \(device.alias) at \(device.address)")
                    onDeviceRegistered?(device)
                }
            }
        }

        if let data = try? JSONSerialization.data(withJSONObject: responseInfo),
           let body = String(data: data, encoding: .utf8) {
            sendResponse(connection: connection, status: 200, body: body)
        } else {
            sendResponse(connection: connection, status: 200, body: "{\"status\":\"ok\"}")
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
            // Notify about peer activity for auto-connection
            if let endpoint = connection.currentPath?.remoteEndpoint,
               case .hostPort(let host, _) = endpoint {
                let remoteAddress = "\(host)"
                AppLog.add("[SyncServer] Received clipboard (\(text.count) chars) from \(remoteAddress)")
                onPeerActivity?(remoteAddress)
            }
            log.info("Received clipboard (\(text.count) chars) from origin=\(origin)")
            onClipboardReceived?(text)
        }

        sendResponse(connection: connection, status: 200, body: "{\"status\":\"ok\"}")
    }

    private func handleImagePost(request: String, connection: NWConnection) {
        let parts = request.components(separatedBy: "\r\n\r\n")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"missing body\"}")
            return
        }

        let bodyString = parts[1]
        guard let bodyData = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"invalid json\"}")
            return
        }

        let origin = json["origin"] as? String ?? ""
        if origin == deviceFingerprint {
            sendResponse(connection: connection, status: 200, body: "{\"status\":\"ignored\"}")
            return
        }

        guard let base64String = json["image"] as? String,
              let imageData = Data(base64Encoded: base64String) else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"invalid image data\"}")
            return
        }

        if imageData.count > maxImageSize {
            sendResponse(connection: connection, status: 413, body: "{\"error\":\"image too large\"}")
            return
        }

        log.info("Received image (\(imageData.count) bytes) from origin=\(origin)")
        onImageReceived?(imageData)
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

        guard let responseData = response.data(using: .utf8) else {
            log.error("Failed to encode HTTP response")
            connection.cancel()
            return
        }
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
