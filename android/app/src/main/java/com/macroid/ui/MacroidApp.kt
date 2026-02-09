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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.NetworkInterface
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
        val clipboardHistory = remember { mutableStateListOf<String>() }
        val localIP = remember { getLocalIPAddress() }

        // Load persisted history on first composition
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

        val discovery = remember { Discovery(context) }
        val syncServer = remember { SyncServer(discovery.fingerprint) }
        val syncClient = remember { SyncClient(discovery.fingerprint) }
        val clipboardMonitor = remember { ClipboardMonitor(context) }

        DisposableEffect(Unit) {
            syncServer.start(onClipboardReceived = { incomingText ->
                if (incomingText != clipboardText) {
                    clipboardText = incomingText
                    clipboardMonitor.writeToClipboard(incomingText)
                    addToHistory(clipboardHistory, incomingText, prefs)
                    Log.d(TAG, "Received remote clipboard update")
                }
            }, onImageReceived = { imageBytes ->
                clipboardMonitor.writeImageToClipboard(imageBytes)
                Log.d(TAG, "Received remote image clipboard update")
            })

            discovery.startDiscovery { device ->
                connectedDevice = device
                isSearching = false
                syncClient.setPeer(device)
            }

            clipboardMonitor.startMonitoring(onClipboardChanged = { newText ->
                if (newText != clipboardText) {
                    clipboardText = newText
                    syncClient.sendClipboard(newText)
                    addToHistory(clipboardHistory, newText, prefs)
                    Log.d(TAG, "Detected local clipboard change, syncing")
                }
            }, onImageChanged = { imageBytes ->
                syncClient.sendImage(imageBytes)
                Log.d(TAG, "Detected local image clipboard change, syncing")
            })

            val keepaliveJob = CoroutineScope(Dispatchers.IO).launch {
                delay(10_000)
                while (isActive) {
                    val device = connectedDevice
                    if (device != null) {
                        val reachable = pingDevice(device)
                        if (!reachable) {
                            Log.w(TAG, "Keepalive failed for ${device.alias}, marking disconnected")
                            connectedDevice = null
                            isSearching = true
                        }
                    }
                    delay(10_000)
                }
            }

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
                CoroutineScope(Dispatchers.IO).launch {
                    val reachable = pingDevice(DeviceInfo(
                        alias = ip,
                        deviceType = "desktop",
                        fingerprint = "manual",
                        address = ip,
                        port = Discovery.PORT
                    ))
                    if (reachable) {
                        val device = DeviceInfo(
                            alias = ip,
                            deviceType = "desktop",
                            fingerprint = "manual",
                            address = ip,
                            port = Discovery.PORT
                        )
                        connectedDevice = device
                        isSearching = false
                        syncClient.setPeer(device)
                        Log.d(TAG, "Manually connected to $ip")
                    } else {
                        Log.w(TAG, "Failed to connect to $ip")
                    }
                }
            }
        )
    }
}

private fun pingDevice(device: DeviceInfo): Boolean {
    return try {
        val url = URL("http://${device.address}:${device.port}/api/ping")
        val connection = url.openConnection() as HttpURLConnection
        connection.connectTimeout = 3000
        connection.readTimeout = 3000
        connection.requestMethod = "GET"
        val response = connection.inputStream.bufferedReader().readText()
        connection.disconnect()
        response == "pong"
    } catch (e: Exception) {
        false
    }
}

private fun getLocalIPAddress(): String {
    return try {
        NetworkInterface.getNetworkInterfaces()?.toList()
            ?.flatMap { it.inetAddresses.toList() }
            ?.firstOrNull { it is Inet4Address && !it.isLoopbackAddress }
            ?.hostAddress ?: "Unknown"
    } catch (e: Exception) {
        "Unknown"
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
