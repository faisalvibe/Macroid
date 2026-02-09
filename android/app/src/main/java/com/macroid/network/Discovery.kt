package com.macroid.network

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log
import com.google.gson.Gson
import com.macroid.util.AppLog
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.net.DatagramPacket
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.Inet4Address
import java.net.MulticastSocket
import java.net.NetworkInterface
import java.net.URL
import java.util.UUID

class Discovery(private val context: Context) {

    companion object {
        private const val TAG = "Discovery"
        const val MULTICAST_GROUP = "224.0.0.167"
        const val PORT = 53317
    }

    private val scope = CoroutineScope(Dispatchers.IO)
    private var listenJob: Job? = null
    private var announceJob: Job? = null
    private var fallbackScanJob: Job? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private val gson = Gson()
    val fingerprint: String = UUID.randomUUID().toString().take(8)

    private val deviceAlias: String = android.os.Build.MODEL ?: "Android"

    fun getDeviceInfo(): Map<String, Any> = mapOf(
        "alias" to deviceAlias,
        "version" to "2.1",
        "deviceModel" to (android.os.Build.MODEL ?: "Unknown"),
        "deviceType" to "mobile",
        "fingerprint" to fingerprint,
        "port" to PORT,
        "protocol" to "http",
        "download" to false
    )

    private fun getAnnouncement(announce: Boolean = true): Map<String, Any> =
        getDeviceInfo() + ("announce" to announce)

    fun startDiscovery(onDeviceFound: (DeviceInfo) -> Unit) {
        val wifiManager = context.applicationContext
            .getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifiManager.createMulticastLock("macroid_multicast")
        multicastLock?.setReferenceCounted(true)
        multicastLock?.acquire()
        Log.d(TAG, "Multicast lock acquired, starting discovery")
        AppLog.add("[Discovery] Multicast lock acquired, starting discovery")
        AppLog.add("[Discovery] Local fingerprint: $fingerprint, alias: $deviceAlias")

        listenJob = scope.launch {
            listenForDevices(onDeviceFound)
        }

        announceJob = scope.launch {
            announcePresence()
        }

        // Start fallback subnet scan after a delay
        fallbackScanJob = scope.launch {
            delay(2000)
            fallbackSubnetScan(onDeviceFound)
        }
    }

    private suspend fun listenForDevices(onDeviceFound: (DeviceInfo) -> Unit) {
        try {
            val socket = MulticastSocket(PORT)
            socket.reuseAddress = true
            socket.soTimeout = 5000

            val group = InetAddress.getByName(MULTICAST_GROUP)
            val networkInterface = getWifiNetworkInterface()
            if (networkInterface != null) {
                socket.networkInterface = networkInterface
                Log.d(TAG, "Using network interface: ${networkInterface.displayName}")
                AppLog.add("[Discovery] Using network interface: ${networkInterface.displayName}")
            }
            socket.joinGroup(java.net.InetSocketAddress(group, PORT), networkInterface)
            Log.d(TAG, "Joined multicast group $MULTICAST_GROUP:$PORT")
            AppLog.add("[Discovery] Joined multicast group $MULTICAST_GROUP:$PORT")

            val buffer = ByteArray(4096)

            while (listenJob?.isActive == true) {
                try {
                    val packet = DatagramPacket(buffer, buffer.size)
                    socket.receive(packet)

                    val data = String(packet.data, 0, packet.length)
                    val msg = gson.fromJson(data, Map::class.java)

                    val msgFingerprint = msg["fingerprint"] as? String ?: continue
                    if (msgFingerprint == fingerprint) continue

                    val deviceType = msg["deviceType"] as? String ?: "unknown"
                    if (deviceType == "mobile") continue

                    val alias = msg["alias"] as? String ?: "Unknown"
                    val port = (msg["port"] as? Double)?.toInt() ?: PORT
                    val isAnnounce = msg["announce"] as? Boolean ?: true
                    val address = packet.address.hostAddress ?: "unknown"

                    val device = DeviceInfo(
                        alias = alias,
                        deviceType = deviceType,
                        fingerprint = msgFingerprint,
                        address = address,
                        port = port
                    )
                    Log.d(TAG, "Found device via multicast: ${device.alias} at ${device.address}:${device.port}")
                    AppLog.add("[Discovery] Found device via multicast: ${device.alias} at ${device.address}:${device.port}")
                    onDeviceFound(device)

                    // If this is an announcement, respond via HTTP register
                    if (isAnnounce) {
                        scope.launch { respondViaRegister(address, port) }
                    }
                } catch (_: java.net.SocketTimeoutException) {
                    // Normal timeout, keep listening
                } catch (e: Exception) {
                    Log.w(TAG, "Error receiving multicast packet", e)
                    AppLog.add("[Discovery] ERROR receiving multicast: ${e.javaClass.simpleName}: ${e.message}")
                }
            }

            socket.leaveGroup(java.net.InetSocketAddress(group, PORT), networkInterface)
            socket.close()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set up multicast listener", e)
            AppLog.add("[Discovery] ERROR: Failed to set up multicast listener: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    private fun respondViaRegister(targetAddress: String, targetPort: Int) {
        try {
            val url = URL("http://$targetAddress:$targetPort/api/localsend/v2/register")
            val connection = url.openConnection() as HttpURLConnection
            connection.connectTimeout = 3000
            connection.readTimeout = 3000
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/json")
            connection.doOutput = true

            val payload = gson.toJson(getDeviceInfo())
            connection.outputStream.use { it.write(payload.toByteArray()) }

            val responseCode = connection.responseCode
            Log.d(TAG, "Register response to $targetAddress: $responseCode")
            AppLog.add("[Discovery] Register response to $targetAddress: HTTP $responseCode")
            connection.disconnect()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to respond via register to $targetAddress", e)
            AppLog.add("[Discovery] Register to $targetAddress FAILED: ${e.javaClass.simpleName}: ${e.message}")
            // Fallback: send multicast with announce=false
            try {
                val socket = MulticastSocket(PORT)
                socket.reuseAddress = true
                val networkInterface = getWifiNetworkInterface()
                if (networkInterface != null) socket.networkInterface = networkInterface
                val json = gson.toJson(getAnnouncement(announce = false))
                val bytes = json.toByteArray()
                val group = InetAddress.getByName(MULTICAST_GROUP)
                val packet = DatagramPacket(bytes, bytes.size, group, PORT)
                socket.send(packet)
                socket.close()
            } catch (_: Exception) { }
        }
    }

    private suspend fun announcePresence() {
        try {
            val socket = MulticastSocket(PORT)
            socket.reuseAddress = true

            val group = InetAddress.getByName(MULTICAST_GROUP)
            val networkInterface = getWifiNetworkInterface()
            if (networkInterface != null) socket.networkInterface = networkInterface

            val json = gson.toJson(getAnnouncement(announce = true))
            val bytes = json.toByteArray()

            // LocalSend-style burst: 0ms, 100ms, 500ms, 2000ms
            AppLog.add("[Discovery] Sending burst announcements to $MULTICAST_GROUP:$PORT")
            val burstDelays = longArrayOf(0, 100, 500, 2000)
            for (d in burstDelays) {
                if (d > 0) delay(d)
                try {
                    val packet = DatagramPacket(bytes, bytes.size, group, PORT)
                    socket.send(packet)
                } catch (e: Exception) {
                    Log.w(TAG, "Burst announcement failed", e)
                    AppLog.add("[Discovery] Burst announcement FAILED: ${e.javaClass.simpleName}: ${e.message}")
                }
            }
            AppLog.add("[Discovery] Burst announcements sent")

            // Then periodic announcements every 5 seconds
            while (announceJob?.isActive == true) {
                delay(5000)
                try {
                    val packet = DatagramPacket(bytes, bytes.size, group, PORT)
                    socket.send(packet)
                } catch (e: Exception) {
                    Log.w(TAG, "Periodic announcement failed", e)
                }
            }

            socket.close()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set up announce socket", e)
            AppLog.add("[Discovery] ERROR: Failed to set up announce socket: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    private suspend fun fallbackSubnetScan(onDeviceFound: (DeviceInfo) -> Unit) {
        val localIP = getLocalIPAddress() ?: return
        val subnet = localIP.split(".").take(3).joinToString(".")
        Log.d(TAG, "Starting fallback subnet scan on $subnet.0/24")
        AppLog.add("[Discovery] Starting fallback subnet scan on $subnet.0/24")

        val scanJobs = mutableListOf<Job>()
        for (i in 1..254) {
            val ip = "$subnet.$i"
            if (ip == localIP) continue

            val job = scope.launch {
                // Try /api/localsend/v2/info first, then /api/ping
                val device = tryInfoEndpoint(ip) ?: tryPingEndpoint(ip)
                if (device != null) {
                    Log.d(TAG, "Fallback found device at $ip: ${device.alias}")
                    AppLog.add("[Discovery] Fallback scan found device at $ip: ${device.alias}")
                    onDeviceFound(device)
                }
            }
            scanJobs.add(job)

            if (scanJobs.size >= 50) {
                scanJobs.first().join()
                scanJobs.removeAt(0)
            }
        }
        scanJobs.forEach { it.join() }
        Log.d(TAG, "Fallback subnet scan completed")
        AppLog.add("[Discovery] Fallback subnet scan completed")
    }

    private fun tryInfoEndpoint(ip: String): DeviceInfo? {
        return try {
            val url = URL("http://$ip:$PORT/api/localsend/v2/info")
            val connection = url.openConnection() as HttpURLConnection
            connection.connectTimeout = 500
            connection.readTimeout = 1000
            connection.requestMethod = "GET"
            val response = connection.inputStream.bufferedReader().readText()
            connection.disconnect()

            val info = gson.fromJson(response, Map::class.java)
            val fp = info["fingerprint"] as? String ?: return null
            if (fp == fingerprint) return null
            val deviceType = info["deviceType"] as? String ?: "unknown"
            if (deviceType == "mobile") return null

            DeviceInfo(
                alias = info["alias"] as? String ?: ip,
                deviceType = deviceType,
                fingerprint = fp,
                address = ip,
                port = (info["port"] as? Double)?.toInt() ?: PORT
            )
        } catch (_: Exception) { null }
    }

    private fun tryPingEndpoint(ip: String): DeviceInfo? {
        return try {
            val url = URL("http://$ip:$PORT/api/ping")
            val connection = url.openConnection() as HttpURLConnection
            connection.connectTimeout = 500
            connection.readTimeout = 1000
            connection.requestMethod = "GET"
            val response = connection.inputStream.bufferedReader().readText()
            connection.disconnect()
            if (response == "pong") {
                DeviceInfo(
                    alias = ip,
                    deviceType = "desktop",
                    fingerprint = "scan-$ip",
                    address = ip,
                    port = PORT
                )
            } else null
        } catch (_: Exception) { null }
    }

    fun getLocalIPAddress(): String? {
        return try {
            NetworkInterface.getNetworkInterfaces()?.toList()
                ?.flatMap { it.inetAddresses.toList() }
                ?.firstOrNull { it is Inet4Address && !it.isLoopbackAddress }
                ?.hostAddress
        } catch (e: Exception) {
            Log.w(TAG, "Failed to get local IP", e)
            null
        }
    }

    private fun getWifiNetworkInterface(): NetworkInterface? {
        return try {
            NetworkInterface.getNetworkInterfaces()?.toList()?.firstOrNull { ni ->
                !ni.isLoopback && ni.isUp && ni.inetAddresses.toList().any {
                    it is Inet4Address && !it.isLoopbackAddress
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to get WiFi network interface", e)
            null
        }
    }

    fun stopDiscovery() {
        listenJob?.cancel()
        announceJob?.cancel()
        fallbackScanJob?.cancel()
        multicastLock?.release()
        Log.d(TAG, "Discovery stopped")
        AppLog.add("[Discovery] Stopped")
    }
}
