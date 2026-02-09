package com.macroid.network

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

class SyncServer {

    private var server: NettyApplicationEngine? = null
    private val gson = Gson()
    private var lastClipboard = ""
    private var lastTimestamp = 0L

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
                                val body = call.receiveText()
                                val data = gson.fromJson(body, Map::class.java)
                                val text = data["text"] as? String ?: ""
                                val timestamp = (data["timestamp"] as? Double)?.toLong() ?: 0L

                                if (text.isNotEmpty() && timestamp > lastTimestamp) {
                                    lastTimestamp = timestamp
                                    lastClipboard = text
                                    CoroutineScope(Dispatchers.Main).launch {
                                        onClipboardReceived(text)
                                    }
                                }
                                call.respond(HttpStatusCode.OK, mapOf("status" to "ok"))
                            } catch (e: Exception) {
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
            } catch (_: Exception) {
                // Port might be in use
            }
        }
    }

    fun stop() {
        server?.stop(1000, 2000)
        server = null
    }
}
