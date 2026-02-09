import Foundation
import Network

class SyncServer {
    private var listener: NWListener?
    private let port: UInt16 = Discovery.port
    private let queue = DispatchQueue(label: "com.macroid.server")
    private var lastClipboard = ""
    private var lastTimestamp: Int64 = 0
    private var onClipboardReceived: ((String) -> Void)?

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
                // Listener state changed
            }

            listener?.start(queue: queue)
        } catch {
            // Port might be in use, try next port
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
            listener?.start(queue: queue)
        } catch {
            // Failed to start server
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self, let data = data else {
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
            let response = "{\"text\":\"\(escapeJSON(lastClipboard))\",\"timestamp\":\(lastTimestamp)}"
            sendResponse(connection: connection, status: 200, body: response)
        } else if method == "POST" && path == "/api/clipboard" {
            handleClipboardPost(request: request, connection: connection)
        } else if method == "POST" && path.hasPrefix("/api/localsend/v2/register") {
            sendResponse(connection: connection, status: 200, body: "{\"status\":\"ok\"}")
        } else {
            sendResponse(connection: connection, status: 404, body: "{\"error\":\"not found\"}")
        }
    }

    private func handleClipboardPost(request: String, connection: NWConnection) {
        // Extract body from HTTP request
        let parts = request.components(separatedBy: "\r\n\r\n")
        guard parts.count >= 2, let bodyData = parts[1].data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            sendResponse(connection: connection, status: 400, body: "{\"error\":\"invalid json\"}")
            return
        }

        let text = json["text"] as? String ?? ""
        let timestamp = json["timestamp"] as? Int64 ?? 0

        if !text.isEmpty && timestamp > lastTimestamp {
            lastTimestamp = timestamp
            lastClipboard = text
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
        default: statusText = "Error"
        }

        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        let responseData = response.data(using: .utf8)!
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func escapeJSON(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}
