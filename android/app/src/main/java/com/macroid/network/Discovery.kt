package com.macroid.network

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log
import com.google.gson.Gson
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
        private const val ANNOUNCE_INTERVAL_MS = 3000L
        private const val FALLBACK_DELAY_MS = 10000L
    }

    private val scope = CoroutineScope(Dispatchers.IO)
    private var listenJob: Job? = null
    private var announceJob: Job? = null
    private var fallbackJob: Job? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private val gson = Gson()
    val fingerprint: String = UUID.randomUUID().toString().take(8)
    @Volatile
    private var deviceFound = false

    private val announcement: Map<String, Any> = mapOf(
        "alias" to (android.os.Build.MODEL ?: "Android"),
        "version" to "2.1",
        "deviceModel" to (android.os.Build.MODEL ?: "Unknown"),
        "deviceType" to "mobile",
        "fingerprint" to fingerprint,
        "port" to PORT,
        "protocol" to "http",
        "download" to false,
        "announce" to true
    )

    fun startDiscovery(onDeviceFound: (DeviceInfo) -> Unit) {
        val wifiManager = context.applicationContext
            .getSystemService(Context.WIFI_SERVICE) as WifiManager
        multicastLock = wifiManager.createMulticastLock("macroid_multicast")
        multicastLock?.setReferenceCounted(true)
        multicastLock?.acquire()
        Log.d(TAG, "Multicast lock acquired, starting discovery")

        listenJob = scope.launch {
            listenForDevices(onDeviceFound)
        }

        announceJob = scope.launch {
            announcePresence()
        }

        fallbackJob = scope.launch {
            delay(FALLBACK_DELAY_MS)
            if (!deviceFound) {
                Log.d(TAG, "No device found via multicast after ${FALLBACK_DELAY_MS}ms, starting subnet scan")
                subnetScan(onDeviceFound)
            }
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
            }
            socket.joinGroup(java.net.InetSocketAddress(group, PORT), networkInterface)
            Log.d(TAG, "Joined multicast group $MULTICAST_GROUP:$PORT")

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

                    val device = DeviceInfo(
                        alias = alias,
                        deviceType = deviceType,
                        fingerprint = msgFingerprint,
                        address = packet.address.hostAddress ?: "unknown",
                        port = port
                    )
                    Log.d(TAG, "Found device via multicast: ${device.alias} at ${device.address}:${device.port}")
                    deviceFound = true
                    onDeviceFound(device)
                } catch (_: java.net.SocketTimeoutException) {
                    // Normal timeout, keep listening
                } catch (e: Exception) {
                    Log.w(TAG, "Error receiving multicast packet", e)
                }
            }

            socket.leaveGroup(java.net.InetSocketAddress(group, PORT), networkInterface)
            socket.close()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set up multicast listener", e)
        }
    }

    private suspend fun announcePresence() {
        try {
            val socket = MulticastSocket(PORT)
            socket.reuseAddress = true

            val group = InetAddress.getByName(MULTICAST_GROUP)
            val networkInterface = getWifiNetworkInterface()
            if (networkInterface != null) {
                socket.networkInterface = networkInterface
            }

            val json = gson.toJson(announcement)
            val bytes = json.toByteArray()

            while (announceJob?.isActive == true) {
                try {
                    val packet = DatagramPacket(bytes, bytes.size, group, PORT)
                    socket.send(packet)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to send announcement", e)
                }
                delay(ANNOUNCE_INTERVAL_MS)
            }

            socket.close()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set up announce socket", e)
        }
    }

    private suspend fun subnetScan(onDeviceFound: (DeviceInfo) -> Unit) {
        val localIP = getLocalIPAddress()
        if (localIP == null) {
            Log.w(TAG, "Could not determine local IP for subnet scan")
            return
        }

        val subnet = localIP.substringBeforeLast(".")
        Log.d(TAG, "Starting subnet scan on $subnet.0/24 (local=$localIP)")

        val scanJobs = mutableListOf<Job>()
        for (i in 1..254) {
            val ip = "$subnet.$i"
            if (ip == localIP) continue
            if (deviceFound) break

            scanJobs.add(scope.launch {
                try {
                    val url = URL("http://$ip:$PORT/api/ping")
                    val connection = url.openConnection() as HttpURLConnection
                    connection.connectTimeout = 500
                    connection.readTimeout = 500
                    connection.requestMethod = "GET"

                    val responseCode = connection.responseCode
                    if (responseCode == 200) {
                        val response = connection.inputStream.bufferedReader().readText()
                        if (response == "pong") {
                            val device = DeviceInfo(
                                alias = ip,
                                deviceType = "desktop",
                                fingerprint = "fallback",
                                address = ip,
                                port = PORT
                            )
                            Log.d(TAG, "Found device via subnet scan at $ip")
                            deviceFound = true
                            onDeviceFound(device)
                        }
                    }
                    connection.disconnect()
                } catch (_: Exception) {
                    // Expected for most IPs
                }
            })
        }

        scanJobs.forEach { it.join() }
        Log.d(TAG, "Subnet scan completed")

        // Repeat scan every 15 seconds if still no device found
        if (!deviceFound && fallbackJob?.isActive == true) {
            delay(15000)
            if (!deviceFound) {
                subnetScan(onDeviceFound)
            }
        }
    }

    private fun getLocalIPAddress(): String? {
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
                    it is java.net.Inet4Address && !it.isLoopbackAddress
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
        fallbackJob?.cancel()
        multicastLock?.release()
        Log.d(TAG, "Discovery stopped")
    }
}
