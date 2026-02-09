package com.macroid.ui

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
import kotlinx.coroutines.launch
import java.net.HttpURLConnection
import java.net.URL

private const val TAG = "MacroidApp"
private const val MAX_HISTORY = 20

@Composable
fun MacroidApp() {
    MacroidTheme {
        val context = LocalContext.current

        var clipboardText by remember { mutableStateOf("") }
        var clipboardImage by remember { mutableStateOf<ByteArray?>(null) }
        var connectedDevice by remember { mutableStateOf<DeviceInfo?>(null) }
        var isSearching by remember { mutableStateOf(true) }
        var connectionStatus by remember { mutableStateOf("") }
        val clipboardHistory = remember { mutableStateListOf<String>() }

        val discovery = remember { Discovery(context) }
        val syncServer = remember { SyncServer(discovery.fingerprint) }
        val syncClient = remember { SyncClient(discovery.fingerprint) }
        val clipboardMonitor = remember { ClipboardMonitor(context) }

        val localIP = remember { discovery.getLocalIPAddress() ?: "Unknown" }

        DisposableEffect(Unit) {
            val onDeviceFound = { device: DeviceInfo ->
                connectedDevice = device
                isSearching = false
                connectionStatus = ""
                syncClient.setPeer(device)
            }

            syncServer.onPeerDiscovered = { device ->
                if (connectedDevice == null) {
                    Log.d(TAG, "Reverse discovery: connected to ${device.alias}")
                    onDeviceFound(device)
                }
            }

            syncServer.onImageReceived = { imageData ->
                clipboardImage = imageData
                clipboardText = ""
                clipboardMonitor.writeImageToClipboard(imageData)
                Log.d(TAG, "Received remote image (${imageData.size} bytes)")
            }

            syncServer.start { incomingText ->
                if (incomingText != clipboardText) {
                    clipboardText = incomingText
                    clipboardImage = null
                    clipboardMonitor.writeToClipboard(incomingText)
                    addToHistory(clipboardHistory, incomingText)
                    Log.d(TAG, "Received remote clipboard update")
                }
            }

            discovery.startDiscovery(onDeviceFound)

            clipboardMonitor.startMonitoring(
                onClipboardChanged = { newText ->
                    if (newText != clipboardText) {
                        clipboardText = newText
                        clipboardImage = null
                        syncClient.sendClipboard(newText)
                        addToHistory(clipboardHistory, newText)
                        Log.d(TAG, "Detected local clipboard change, syncing")
                    }
                },
                onImageChanged = { imageData ->
                    clipboardImage = imageData
                    clipboardText = ""
                    syncClient.sendImage(imageData)
                    Log.d(TAG, "Detected local image change, syncing (${imageData.size} bytes)")
                }
            )

            onDispose {
                clipboardMonitor.stopMonitoring()
                discovery.stopDiscovery()
                syncServer.stop()
            }
        }

        MainScreen(
            clipboardText = clipboardText,
            clipboardImage = clipboardImage,
            connectedDevice = connectedDevice,
            isSearching = isSearching,
            connectionStatus = connectionStatus,
            localIP = localIP,
            clipboardHistory = clipboardHistory,
            onTextChanged = { newText ->
                clipboardText = newText
                clipboardImage = null
                clipboardMonitor.writeToClipboard(newText)
                syncClient.sendClipboard(newText)
            },
            onHistoryItemClicked = { text ->
                clipboardText = text
                clipboardImage = null
                clipboardMonitor.writeToClipboard(text)
                syncClient.sendClipboard(text)
            },
            onClearHistory = {
                clipboardHistory.clear()
            },
            onManualConnect = { ip ->
                val trimmed = ip.trim()
                if (trimmed.isNotEmpty()) {
                    connectionStatus = "Connecting..."
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val url = URL("http://$trimmed:${Discovery.PORT}/api/ping")
                            val conn = url.openConnection() as HttpURLConnection
                            conn.connectTimeout = 5000
                            conn.readTimeout = 5000
                            conn.requestMethod = "GET"
                            val code = conn.responseCode
                            conn.disconnect()

                            val device = DeviceInfo(
                                alias = trimmed,
                                deviceType = "desktop",
                                fingerprint = "manual",
                                address = trimmed,
                                port = Discovery.PORT
                            )
                            CoroutineScope(Dispatchers.Main).launch {
                                connectedDevice = device
                                isSearching = false
                                connectionStatus = ""
                                syncClient.setPeer(device)
                                Log.d(TAG, "Manually connected to $trimmed")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Manual connect to $trimmed failed", e)
                            CoroutineScope(Dispatchers.Main).launch {
                                connectionStatus = "Failed: ${e.message ?: "connection error"}"
                                // Auto-clear after 3 seconds
                                CoroutineScope(Dispatchers.Main).launch {
                                    kotlinx.coroutines.delay(3000)
                                    if (connectedDevice == null) {
                                        connectionStatus = ""
                                    }
                                }
                            }
                        }
                    }
                }
            }
        )
    }
}

private fun addToHistory(history: MutableList<String>, text: String) {
    if (text.isBlank()) return
    history.remove(text)
    history.add(0, text)
    while (history.size > MAX_HISTORY) {
        history.removeAt(history.size - 1)
    }
}
