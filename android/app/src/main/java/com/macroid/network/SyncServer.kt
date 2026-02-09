package com.macroid.network

import android.util.Base64
import android.util.Log
import com.google.gson.Gson
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

class SyncServer(private val deviceFingerprint: String) {

    companion object {
        private const val TAG = "SyncServer"
        private const val MAX_BODY_SIZE = 10_485_760 // 10MB
    }

    private var server: NettyApplicationEngine? = null
    private val gson = Gson()
    private var lastClipboard = ""
    private var lastTimestamp = 0L
    var onPeerDiscovered: ((DeviceInfo) -> Unit)? = null
    var onImageReceived: ((ByteArray) -> Unit)? = null

    fun start(onClipboardReceived: (String) -> Unit) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                server = embeddedServer(Netty, port = Discovery.PORT, host = "0.0.0.0") {
                    install(ContentNegotiation) {
                        gson()
                    }
                    routing {
                        post("/api/clipboard") {
                            try {
                                val remoteHost = call.request.local.remoteHost
                                val body = call.receiveText()
                                if (body.length > MAX_BODY_SIZE) {
                                    Log.w(TAG, "Rejected oversized request: ${body.length} bytes")
                                    call.respond(HttpStatusCode.PayloadTooLarge, mapOf("error" to "payload too large"))
                                    return@post
                                }

                                val data = gson.fromJson(body, Map::class.java)
                                val timestamp = (data["timestamp"] as? Double)?.toLong() ?: 0L
                                val origin = data["origin"] as? String ?: ""
                                val type = data["type"] as? String ?: "text"

                                if (origin == deviceFingerprint) {
                                    Log.d(TAG, "Ignoring echo from self")
                                    call.respond(HttpStatusCode.OK, mapOf("status" to "ignored"))
                                    return@post
                                }

                                // Reverse discovery: register the sender as a peer
                                if (remoteHost.isNotEmpty()) {
                                    val device = DeviceInfo(
                                        alias = remoteHost,
                                        deviceType = "desktop",
                                        fingerprint = origin,
                                        address = remoteHost,
                                        port = Discovery.PORT
                                    )
                                    Log.d(TAG, "Reverse discovery: found peer at $remoteHost")
                                    onPeerDiscovered?.invoke(device)
                                }

                                if (type == "image") {
                                    val imageBase64 = data["image"] as? String
                                    if (imageBase64 != null && timestamp > lastTimestamp) {
                                        val imageData = Base64.decode(imageBase64, Base64.NO_WRAP)
                                        lastTimestamp = timestamp
                                        Log.d(TAG, "Received image (${imageData.size} bytes) from origin=$origin")
                                        CoroutineScope(Dispatchers.Main).launch {
                                            onImageReceived?.invoke(imageData)
                                        }
                                    }
                                } else {
                                    val text = data["text"] as? String ?: ""
                                    if (text.isNotEmpty() && timestamp > lastTimestamp) {
                                        lastTimestamp = timestamp
                                        lastClipboard = text
                                        Log.d(TAG, "Received clipboard (${text.length} chars) from origin=$origin")
                                        CoroutineScope(Dispatchers.Main).launch {
                                            onClipboardReceived(text)
                                        }
                                    }
                                }
                                call.respond(HttpStatusCode.OK, mapOf("status" to "ok"))
                            } catch (e: Exception) {
                                Log.e(TAG, "Error processing clipboard POST", e)
                                call.respond(
                                    HttpStatusCode.BadRequest,
                                    mapOf("error" to (e.message ?: "unknown"))
                                )
                            }
                        }

                        get("/api/clipboard") {
                            call.respond(
                                HttpStatusCode.OK,
                                mapOf(
                                    "text" to lastClipboard,
                                    "timestamp" to lastTimestamp
                                )
                            )
                        }

                        get("/api/ping") {
                            call.respondText("pong", ContentType.Text.Plain)
                        }

                        post("/api/localsend/v2/register") {
                            call.respond(HttpStatusCode.OK, mapOf("status" to "ok"))
                        }
                    }
                }
                server?.start(wait = false)
                Log.d(TAG, "Server started on port ${Discovery.PORT}")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start server on port ${Discovery.PORT}", e)
            }
        }
    }

    fun stop() {
        server?.stop(1000, 2000)
        server = null
        Log.d(TAG, "Server stopped")
    }
}
