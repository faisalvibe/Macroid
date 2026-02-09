package com.macroid.network

import com.google.gson.Gson
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class SyncClient {

    private val client = HttpClient(OkHttp) {
        engine {
            config {
                connectTimeout(5, java.util.concurrent.TimeUnit.SECONDS)
                readTimeout(5, java.util.concurrent.TimeUnit.SECONDS)
            }
        }
    }

    private val gson = Gson()
    private var peer: DeviceInfo? = null

    fun setPeer(device: DeviceInfo) {
        peer = device
    }

    fun sendClipboard(text: String) {
        val device = peer ?: return

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val payload = gson.toJson(
                    mapOf(
                        "text" to text,
                        "timestamp" to System.currentTimeMillis()
                    )
                )

                client.post("http://${device.address}:${device.port}/api/clipboard") {
                    contentType(ContentType.Application.Json)
                    setBody(payload)
                }
            } catch (_: Exception) {
                // Peer unreachable
            }
        }
    }
}
