package com.macroid.ui

import android.content.Context
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.macroid.clipboard.ClipboardMonitor
import com.macroid.network.DeviceInfo
import com.macroid.network.Discovery
import com.macroid.network.SyncClient
import com.macroid.network.SyncServer
import com.macroid.util.AppLog
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.net.HttpURLConnection
import java.net.URL

private const val TAG = "MacroidApp"
private const val MAX_HISTORY = 20
private const val PREFS_NAME = "macroid_prefs"
private const val HISTORY_KEY = "clipboard_history"

@Composable
fun MacroidApp() {
    MacroidTheme {
        val context = LocalContext.current

        var clipboardText by remember { mutableStateOf("") }
        var connectedDevice by remember { mutableStateOf<DeviceInfo?>(null) }
        var isSearching by remember { mutableStateOf(true) }
        var connectionStatus by remember { mutableStateOf("") }
        val clipboardHistory = remember { mutableStateListOf<String>() }

        val discovery = remember { Discovery(context) }
        val localIP = remember { discovery.getLocalIPAddress() ?: "Unknown" }

        val prefs = remember { context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE) }
        remember {
            val ordered = prefs.getString("${HISTORY_KEY}_ordered", null)
            if (ordered != null && ordered.isNotEmpty()) {
                ordered.split("\u0000").filter { it.isNotEmpty() }.take(MAX_HISTORY).forEach {
                    clipboardHistory.add(it)
                }
            }
            true
        }

        val syncServer = remember { SyncServer(discovery.fingerprint, deviceInfoProvider = { discovery.getDeviceInfo() }) }
        val syncClient = remember { SyncClient(discovery.fingerprint) }
        val clipboardMonitor = remember { ClipboardMonitor(context) }

        DisposableEffect(Unit) {
            AppLog.add("[MacroidApp] Starting up...")
            AppLog.add("[MacroidApp] Local IP: $localIP, Fingerprint: ${discovery.fingerprint}")

            val onDeviceFound = { device: DeviceInfo ->
                connectedDevice = device
                isSearching = false
                syncClient.setPeer(device)
                AppLog.add("[MacroidApp] Device found: ${device.alias} at ${device.address}:${device.port}")
            }

            syncServer.onDeviceRegistered = { device ->
                if (device.deviceType != "mobile") {
                    CoroutineScope(Dispatchers.Main).launch {
                        onDeviceFound(device)
                        AppLog.add("[MacroidApp] Device registered via HTTP: ${device.alias}")
                    }
                }
            }

            syncServer.onReady = {
                discovery.announcePort = syncServer.actualPort
                AppLog.add("[MacroidApp] Server ready on port ${syncServer.actualPort}")
            }

            syncServer.start(onClipboardReceived = { incomingText ->
                if (incomingText != clipboardText) {
                    clipboardText = incomingText
                    clipboardMonitor.writeToClipboard(incomingText)
                    addToHistory(clipboardHistory, incomingText, prefs)
                    AppLog.add("[MacroidApp] Received remote clipboard (${incomingText.length} chars)")
                }
            }, onImageReceived = { imageBytes ->
                clipboardMonitor.writeImageToClipboard(imageBytes)
                AppLog.add("[MacroidApp] Received remote image (${imageBytes.size} bytes)")
            })

            discovery.startDiscovery { device ->
                onDeviceFound(device)
            }

            AppLog.add("[MacroidApp] Discovery started")

            clipboardMonitor.startMonitoring(onClipboardChanged = { newText ->
                if (newText != clipboardText) {
                    clipboardText = newText
                    syncClient.sendClipboard(newText)
                    addToHistory(clipboardHistory, newText, prefs)
                }
            }, onImageChanged = { imageBytes ->
                syncClient.sendImage(imageBytes)
            })

            val keepaliveJob = CoroutineScope(Dispatchers.IO).launch {
                delay(10_000)
                while (isActive) {
                    val device = connectedDevice
                    if (device != null) {
                        val reachable = pingDevice(device)
                        if (!reachable) {
                            AppLog.add("[MacroidApp] Keepalive failed for ${device.alias}")
                            connectedDevice = null
                            isSearching = true
                        }
                    }
                    delay(10_000)
                }
            }

            AppLog.add("[MacroidApp] Setup complete")

            onDispose {
                keepaliveJob.cancel()
                clipboardMonitor.stopMonitoring()
                discovery.stopDiscovery()
                syncServer.stop()
            }
        }

        MainScreen(
            clipboardText = clipboardText,
            connectedDevice = connectedDevice,
            isSearching = isSearching,
            clipboardHistory = clipboardHistory,
            localIP = localIP,
            connectionStatus = connectionStatus,
            onTextChanged = { newText ->
                clipboardText = newText
                clipboardMonitor.writeToClipboard(newText)
                syncClient.sendClipboard(newText)
            },
            onHistoryItemClicked = { text ->
                clipboardText = text
                clipboardMonitor.writeToClipboard(text)
                syncClient.sendClipboard(text)
            },
            onClearHistory = {
                clipboardHistory.clear()
                prefs.edit().remove("${HISTORY_KEY}_ordered").apply()
            },
            onConnectByIP = { ip ->
                connectionStatus = "Connecting..."
                val portsToTry = listOf(Discovery.PORT, Discovery.PORT + 1, Discovery.PORT + 2)
                AppLog.add("[MacroidApp] Connecting by IP to $ip, trying ports $portsToTry...")
                CoroutineScope(Dispatchers.IO).launch {
                    var connected = false
                    for (port in portsToTry) {
                        val device = DeviceInfo(
                            alias = ip,
                            deviceType = "desktop",
                            fingerprint = "manual",
                            address = ip,
                            port = port
                        )
                        val reachable = pingDevice(device)
                        if (reachable) {
                            CoroutineScope(Dispatchers.Main).launch {
                                connectedDevice = device
                                isSearching = false
                                syncClient.setPeer(device)
                                connectionStatus = "Connected to $ip:$port"
                                AppLog.add("[MacroidApp] Connected to $ip:$port")
                            }
                            connected = true
                            break
                        }
                        AppLog.add("[MacroidApp] Port $port failed, trying next...")
                    }
                    if (!connected) {
                        CoroutineScope(Dispatchers.Main).launch {
                            connectionStatus = "Failed to connect to $ip"
                            AppLog.add("[MacroidApp] ERROR: Failed to connect to $ip on all ports")
                        }
                    }
                }
            }
        )
    }
}

private fun pingDevice(device: DeviceInfo): Boolean {
    return try {
        AppLog.add("[Ping] Connecting to ${device.address}:${device.port}/api/ping...")
        val url = URL("http://${device.address}:${device.port}/api/ping")
        val connection = url.openConnection() as HttpURLConnection
        connection.connectTimeout = 3000
        connection.readTimeout = 3000
        connection.requestMethod = "GET"
        val response = connection.inputStream.bufferedReader().readText()
        connection.disconnect()
        val ok = response == "pong"
        AppLog.add("[Ping] Response from ${device.address}: ${if (ok) "pong OK" else "'$response'"}")
        ok
    } catch (e: Exception) {
        AppLog.add("[Ping] FAILED to ${device.address}: ${e.javaClass.simpleName}: ${e.message}")
        false
    }
}

private fun addToHistory(
    history: MutableList<String>,
    text: String,
    prefs: android.content.SharedPreferences
) {
    if (text.isBlank()) return
    history.remove(text)
    history.add(0, text)
    while (history.size > MAX_HISTORY) {
        history.removeAt(history.size - 1)
    }
    prefs.edit().putString("${HISTORY_KEY}_ordered", history.joinToString("\u0000")).apply()
}
