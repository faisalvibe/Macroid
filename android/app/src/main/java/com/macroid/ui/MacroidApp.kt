package com.macroid.ui

import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.macroid.network.DeviceInfo
import com.macroid.network.Discovery
import com.macroid.network.SyncClient
import com.macroid.network.SyncServer
import com.macroid.util.AppLog
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import com.google.gson.Gson
import java.io.ByteArrayOutputStream
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
        var lastReceivedImage by remember { mutableStateOf<ByteArray?>(null) }
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
        var isUpdatingFromRemote by remember { mutableStateOf(false) }
        val coroutineScope = rememberCoroutineScope()
        var debounceJob by remember { mutableStateOf<Job?>(null) }
        var lastSentText by remember { mutableStateOf("") }

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

            syncServer.onPeerActivity = { address, port ->
                if (connectedDevice == null) {
                    // Try to fetch the device's info for name
                    CoroutineScope(Dispatchers.IO).launch {
                        val info = fetchDeviceInfo(address, port)
                        val alias = info?.get("alias") as? String ?: address
                        val peerPort = (info?.get("port") as? Double)?.toInt() ?: port
                        CoroutineScope(Dispatchers.Main).launch {
                            val device = DeviceInfo(
                                alias = alias,
                                deviceType = "desktop",
                                fingerprint = "peer-$address",
                                address = address,
                                port = peerPort
                            )
                            connectedDevice = device
                            isSearching = false
                            syncClient.setPeer(device)
                            AppLog.add("[MacroidApp] Peer detected: $alias at $address:$peerPort")
                        }
                    }
                }
            }

            syncServer.onReady = {
                discovery.announcePort = syncServer.actualPort
                AppLog.add("[MacroidApp] Server ready on port ${syncServer.actualPort}")
            }

            syncServer.start(onClipboardReceived = { incomingText ->
                CoroutineScope(Dispatchers.Main).launch {
                    // If user is actively typing (debounce pending), ignore incoming text
                    if (debounceJob?.isActive == true) {
                        AppLog.add("[MacroidApp] Ignored incoming text (user is typing)")
                        return@launch
                    }
                    // Ignore echo of text we just sent
                    if (incomingText == lastSentText) {
                        AppLog.add("[MacroidApp] Ignored echo text")
                        return@launch
                    }
                    if (incomingText != clipboardText) {
                        isUpdatingFromRemote = true
                        clipboardText = incomingText
                        addToHistory(clipboardHistory, incomingText, prefs)
                        AppLog.add("[MacroidApp] Received text (${incomingText.length} chars)")
                        delay(500)
                        isUpdatingFromRemote = false
                    }
                }
            }, onImageReceived = { imageBytes ->
                lastReceivedImage = imageBytes
                AppLog.add("[MacroidApp] Received image (${imageBytes.size} bytes)")
            })

            discovery.startDiscovery { device ->
                onDeviceFound(device)
                // Register with the discovered device so it knows about us
                CoroutineScope(Dispatchers.IO).launch {
                    registerWithPeer(device.address, device.port, discovery)
                }
            }

            AppLog.add("[MacroidApp] Discovery started")

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
            lastReceivedImage = lastReceivedImage,
            onTextChanged = { newText ->
                if (!isUpdatingFromRemote) {
                    clipboardText = newText
                    debounceJob?.cancel()
                    debounceJob = coroutineScope.launch {
                        delay(300)
                        lastSentText = newText
                        syncClient.sendClipboard(newText)
                    }
                }
            },
            onHistoryItemClicked = { text ->
                clipboardText = text
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
                            // Fetch device name and register
                            val info = fetchDeviceInfo(ip, port)
                            val alias = info?.get("alias") as? String ?: ip
                            registerWithPeer(ip, port, discovery)
                            CoroutineScope(Dispatchers.Main).launch {
                                val namedDevice = DeviceInfo(
                                    alias = alias,
                                    deviceType = "desktop",
                                    fingerprint = "manual",
                                    address = ip,
                                    port = port
                                )
                                connectedDevice = namedDevice
                                isSearching = false
                                syncClient.setPeer(namedDevice)
                                connectionStatus = "Connected to $alias"
                                AppLog.add("[MacroidApp] Connected to $alias ($ip:$port)")
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
            },
            onSendClipboard = {
                sendClipboardContent(context, syncClient, { clipboardText = it }, { lastReceivedImage = it })
            }
        )
    }
}

private fun sendClipboardContent(
    context: Context,
    syncClient: SyncClient,
    onTextFound: (String) -> Unit,
    onImageFound: (ByteArray) -> Unit
) {
    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    if (!cm.hasPrimaryClip()) return
    val clip = cm.primaryClip ?: return
    val item = clip.getItemAt(0) ?: return

    // Check for image
    val uri = item.uri
    if (uri != null) {
        val mimeType = context.contentResolver.getType(uri)
        if (mimeType != null && mimeType.startsWith("image/")) {
            try {
                context.contentResolver.openInputStream(uri)?.use { stream ->
                    val bitmap = BitmapFactory.decodeStream(stream) ?: return
                    val baos = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, baos)
                    val imageBytes = baos.toByteArray()
                    CoroutineScope(Dispatchers.Main).launch { onImageFound(imageBytes) }
                    syncClient.sendImage(imageBytes)
                    AppLog.add("[MacroidApp] Sending clipboard image (${imageBytes.size} bytes)")
                }
            } catch (e: Exception) {
                AppLog.add("[MacroidApp] ERROR reading clipboard image: ${e.message}")
            }
            return
        }
    }

    // Check for text
    val text = item.text?.toString()
    if (!text.isNullOrEmpty()) {
        CoroutineScope(Dispatchers.Main).launch { onTextFound(text) }
        syncClient.sendClipboard(text)
        AppLog.add("[MacroidApp] Sending clipboard text (${text.length} chars)")
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

private fun fetchDeviceInfo(address: String, port: Int): Map<*, *>? {
    val portsToTry = listOf(port, Discovery.PORT, Discovery.PORT + 1, Discovery.PORT + 2).distinct()
    for (p in portsToTry) {
        try {
            val url = URL("http://$address:$p/api/localsend/v2/info")
            val connection = url.openConnection() as HttpURLConnection
            connection.connectTimeout = 2000
            connection.readTimeout = 2000
            connection.requestMethod = "GET"
            val response = connection.inputStream.bufferedReader().readText()
            connection.disconnect()
            return Gson().fromJson(response, Map::class.java)
        } catch (_: Exception) { }
    }
    return null
}

private fun registerWithPeer(address: String, port: Int, discovery: Discovery) {
    val portsToTry = listOf(port, Discovery.PORT, Discovery.PORT + 1, Discovery.PORT + 2).distinct()
    for (p in portsToTry) {
        try {
            val url = URL("http://$address:$p/api/localsend/v2/register")
            val connection = url.openConnection() as HttpURLConnection
            connection.connectTimeout = 2000
            connection.readTimeout = 2000
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/json")
            connection.doOutput = true
            val body = Gson().toJson(discovery.getDeviceInfo())
            connection.outputStream.write(body.toByteArray())
            connection.responseCode
            connection.disconnect()
            AppLog.add("[MacroidApp] Register sent to $address:$p")
            return
        } catch (_: Exception) { }
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
