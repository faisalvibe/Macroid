package com.macroid.network

import android.util.Log
import com.google.gson.Gson
import com.macroid.util.AppLog
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.call
import io.ktor.server.application.install
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.netty.NettyApplicationEngine
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.gson.gson
import io.ktor.server.request.receiveText
import io.ktor.server.response.respond
import io.ktor.server.response.respondText
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.routing
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class SyncServer(
    private val deviceFingerprint: String,
    private val deviceInfoProvider: (() -> Map<String, Any>)? = null
) {

    companion object {
        private const val TAG = "SyncServer"
        private const val MAX_BODY_SIZE = 1_048_576 // 1MB
        private const val MAX_IMAGE_SIZE = 10_485_760 // 10MB
    }

    private var server: NettyApplicationEngine? = null
    private val gson = Gson()
    private var lastClipboard = ""
    private var lastTimestamp = 0L
    var onDeviceRegistered: ((DeviceInfo) -> Unit)? = null
    var onReady: (() -> Unit)? = null
    var actualPort: Int = Discovery.PORT
        private set

    private var onClipboardReceivedCallback: ((String) -> Unit)? = null
    private var onImageReceivedCallback: ((ByteArray) -> Unit)? = null

    fun start(onClipboardReceived: (String) -> Unit, onImageReceived: (ByteArray) -> Unit = {}) {
        this.onClipboardReceivedCallback = onClipboardReceived
        this.onImageReceivedCallback = onImageReceived
        CoroutineScope(Dispatchers.IO).launch {
            startOnPort(Discovery.PORT)
        }
    }

    private fun startOnPort(port: Int) {
        try {
            server = embeddedServer(Netty, port = port, host = "0.0.0.0") {
                install(ContentNegotiation) {
                    gson()
                }
                routing {
                    post("/api/clipboard") {
                        try {
                            val body = call.receiveText()
                            if (body.length > MAX_BODY_SIZE) {
                                Log.w(TAG, "Rejected oversized request: ${body.length} bytes")
                                call.respond(HttpStatusCode.PayloadTooLarge, mapOf("error" to "payload too large"))
                                return@post
                            }

                            val data = gson.fromJson(body, Map::class.java)
                            val text = data["text"] as? String ?: ""
                            val timestamp = (data["timestamp"] as? Double)?.toLong() ?: 0L
                            val origin = data["origin"] as? String ?: ""

                            if (origin == deviceFingerprint) {
                                call.respond(HttpStatusCode.OK, mapOf("status" to "ignored"))
                                return@post
                            }

                            if (text.isNotEmpty() && timestamp > lastTimestamp) {
                                lastTimestamp = timestamp
                                lastClipboard = text
                                Log.d(TAG, "Received clipboard (${text.length} chars) from origin=$origin")
                                AppLog.add("[SyncServer] Received clipboard (${text.length} chars) from origin=$origin")
                                CoroutineScope(Dispatchers.Main).launch {
                                    onClipboardReceivedCallback?.invoke(text)
                                }
                            }
                            call.respond(HttpStatusCode.OK, mapOf("status" to "ok"))
                        } catch (e: Exception) {
                            Log.e(TAG, "Error processing clipboard POST", e)
                            call.respond(HttpStatusCode.BadRequest, mapOf("error" to (e.message ?: "unknown")))
                        }
                    }

                    get("/api/clipboard") {
                        call.respond(HttpStatusCode.OK, mapOf("text" to lastClipboard, "timestamp" to lastTimestamp))
                    }

                    get("/api/ping") {
                        call.respondText("pong", ContentType.Text.Plain)
                    }

                    post("/api/clipboard/image") {
                        try {
                            val body = call.receiveText()
                            val data = gson.fromJson(body, Map::class.java)
                            val origin = data["origin"] as? String ?: ""

                            if (origin == deviceFingerprint) {
                                call.respond(HttpStatusCode.OK, mapOf("status" to "ignored"))
                                return@post
                            }

                            val base64Image = data["image"] as? String ?: ""
                            val imageBytes = android.util.Base64.decode(base64Image, android.util.Base64.DEFAULT)

                            if (imageBytes.size > MAX_IMAGE_SIZE) {
                                call.respond(HttpStatusCode.PayloadTooLarge, mapOf("error" to "image too large"))
                                return@post
                            }

                            Log.d(TAG, "Received image (${imageBytes.size} bytes) from origin=$origin")
                            AppLog.add("[SyncServer] Received image (${imageBytes.size} bytes) from origin=$origin")
                            CoroutineScope(Dispatchers.Main).launch {
                                onImageReceivedCallback?.invoke(imageBytes)
                            }
                            call.respond(HttpStatusCode.OK, mapOf("status" to "ok"))
                        } catch (e: Exception) {
                            Log.e(TAG, "Error processing image POST", e)
                            call.respond(HttpStatusCode.BadRequest, mapOf("error" to (e.message ?: "unknown")))
                        }
                    }

                    // LocalSend v2 info endpoint
                    get("/api/localsend/v2/info") {
                        val info = deviceInfoProvider?.invoke() ?: mapOf(
                            "alias" to (android.os.Build.MODEL ?: "Android"),
                            "version" to "2.1",
                            "deviceModel" to (android.os.Build.MODEL ?: "Unknown"),
                            "deviceType" to "mobile",
                            "fingerprint" to deviceFingerprint,
                            "download" to false
                        )
                        call.respond(HttpStatusCode.OK, info)
                    }

                    // LocalSend v2 register endpoint
                    post("/api/localsend/v2/register") {
                        try {
                            val body = call.receiveText()
                            val data = gson.fromJson(body, Map::class.java)
                            val fp = data["fingerprint"] as? String ?: ""
                            val alias = data["alias"] as? String ?: "Unknown"
                            val deviceType = data["deviceType"] as? String ?: "unknown"
                            val remotePort = (data["port"] as? Double)?.toInt() ?: Discovery.PORT

                            if (fp.isNotEmpty() && fp != deviceFingerprint) {
                                val remoteAddress = call.request.local.remoteAddress
                                val device = DeviceInfo(
                                    alias = alias,
                                    deviceType = deviceType,
                                    fingerprint = fp,
                                    address = remoteAddress,
                                    port = remotePort
                                )
                                Log.d(TAG, "Device registered via HTTP: ${device.alias} at ${device.address}")
                                AppLog.add("[SyncServer] Device registered via HTTP: ${device.alias} at ${device.address}:${device.port}")
                                onDeviceRegistered?.invoke(device)
                            }

                            val myInfo = deviceInfoProvider?.invoke() ?: mapOf(
                                "alias" to (android.os.Build.MODEL ?: "Android"),
                                "version" to "2.1",
                                "deviceType" to "mobile",
                                "fingerprint" to deviceFingerprint
                            )
                            call.respond(HttpStatusCode.OK, myInfo)
                        } catch (e: Exception) {
                            Log.e(TAG, "Error processing register", e)
                            call.respond(HttpStatusCode.OK, mapOf("status" to "ok"))
                        }
                    }
                }
            }
            server?.start(wait = false)
            actualPort = port
            Log.d(TAG, "Server started on port $port")
            AppLog.add("[SyncServer] Server started on port $port")
            onReady?.invoke()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start server on port $port", e)
            AppLog.add("[SyncServer] ERROR on port $port: ${e.javaClass.simpleName}: ${e.message}")
            // Try alternate ports
            if (port == Discovery.PORT) {
                AppLog.add("[SyncServer] Trying alternate port ${Discovery.PORT + 1}...")
                startOnPort(Discovery.PORT + 1)
            } else if (port == Discovery.PORT + 1) {
                AppLog.add("[SyncServer] Trying alternate port ${Discovery.PORT + 2}...")
                startOnPort(Discovery.PORT + 2)
            } else {
                AppLog.add("[SyncServer] ERROR: All ports failed, server not running")
            }
        }
    }

    fun stop() {
        server?.stop(1000, 2000)
        server = null
        Log.d(TAG, "Server stopped")
    }
}
