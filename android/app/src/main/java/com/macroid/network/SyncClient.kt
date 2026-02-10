package com.macroid.network

import android.util.Log
import com.google.gson.Gson
import com.macroid.util.AppLog
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class SyncClient(private val deviceFingerprint: String) {

    companion object {
        private const val TAG = "SyncClient"
        private const val MAX_RETRIES = 3
        private const val INITIAL_BACKOFF_MS = 500L
    }

    private val client = HttpClient(OkHttp) {
        engine {
            config {
                connectTimeout(10, java.util.concurrent.TimeUnit.SECONDS)
                readTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
                writeTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
            }
        }
    }

    private val gson = Gson()
    private var peer: DeviceInfo? = null
    @Volatile
    var lastSentText: String = ""
        private set

    fun setPeer(device: DeviceInfo) {
        peer = device
        Log.d(TAG, "Peer set: ${device.alias} at ${device.address}:${device.port}")
        AppLog.add("[SyncClient] Peer set: ${device.alias} at ${device.address}:${device.port}")
    }

    fun sendImage(imageBytes: ByteArray) {
        val device = peer ?: return

        CoroutineScope(Dispatchers.IO).launch {
            val base64 = android.util.Base64.encodeToString(imageBytes, android.util.Base64.NO_WRAP)
            val payload = gson.toJson(
                mapOf(
                    "image" to base64,
                    "timestamp" to System.currentTimeMillis(),
                    "origin" to deviceFingerprint
                )
            )

            AppLog.add("[SyncClient] Sending image (${imageBytes.size} bytes, payload ${payload.length} chars) to ${device.alias}")

            var attempt = 0
            var backoff = INITIAL_BACKOFF_MS
            while (attempt < MAX_RETRIES) {
                try {
                    client.post("http://${device.address}:${device.port}/api/clipboard/image") {
                        contentType(ContentType.Application.Json)
                        setBody(payload)
                    }
                    Log.d(TAG, "Sent image (${imageBytes.size} bytes) to ${device.alias}")
                    AppLog.add("[SyncClient] Sent image successfully to ${device.alias}")
                    return@launch
                } catch (e: Exception) {
                    attempt++
                    if (attempt < MAX_RETRIES) {
                        Log.w(TAG, "Image send failed (attempt $attempt/$MAX_RETRIES), retrying in ${backoff}ms", e)
                        AppLog.add("[SyncClient] Image send failed (attempt $attempt/$MAX_RETRIES): ${e.javaClass.simpleName}: ${e.message}")
                        delay(backoff)
                        backoff *= 2
                    } else {
                        Log.e(TAG, "Image send failed after $MAX_RETRIES attempts", e)
                        AppLog.add("[SyncClient] ERROR: Image send failed after $MAX_RETRIES attempts: ${e.javaClass.simpleName}: ${e.message}")
                    }
                }
            }
        }
    }

    fun sendClipboard(text: String) {
        val device = peer ?: return
        lastSentText = text

        CoroutineScope(Dispatchers.IO).launch {
            val payload = gson.toJson(
                mapOf(
                    "text" to text,
                    "timestamp" to System.currentTimeMillis(),
                    "origin" to deviceFingerprint
                )
            )

            var attempt = 0
            var backoff = INITIAL_BACKOFF_MS

            while (attempt < MAX_RETRIES) {
                try {
                    client.post("http://${device.address}:${device.port}/api/clipboard") {
                        contentType(ContentType.Application.Json)
                        setBody(payload)
                    }
                    Log.d(TAG, "Sent clipboard (${text.length} chars) to ${device.alias}")
                    AppLog.add("[SyncClient] Sent clipboard (${text.length} chars) to ${device.alias}")
                    return@launch
                } catch (e: Exception) {
                    attempt++
                    if (attempt < MAX_RETRIES) {
                        Log.w(TAG, "Send failed (attempt $attempt/$MAX_RETRIES), retrying in ${backoff}ms", e)
                        AppLog.add("[SyncClient] Send failed (attempt $attempt/$MAX_RETRIES): ${e.javaClass.simpleName}: ${e.message}")
                        delay(backoff)
                        backoff *= 2
                    } else {
                        Log.e(TAG, "Send failed after $MAX_RETRIES attempts", e)
                        AppLog.add("[SyncClient] ERROR: Send failed after $MAX_RETRIES attempts: ${e.javaClass.simpleName}: ${e.message}")
                    }
                }
            }
        }
    }
}
