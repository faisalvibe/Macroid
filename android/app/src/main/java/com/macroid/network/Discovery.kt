package com.macroid.network

import android.content.Context
import android.net.wifi.WifiManager
import com.google.gson.Gson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.net.DatagramPacket
import java.net.InetAddress
import java.net.MulticastSocket
import java.net.NetworkInterface
import java.util.UUID

class Discovery(private val context: Context) {

    companion object {
        const val MULTICAST_GROUP = "224.0.0.167"
        const val PORT = 53317
        private const val ANNOUNCE_INTERVAL_MS = 3000L
    }

    private val scope = CoroutineScope(Dispatchers.IO)
    private var listenJob: Job? = null
    private var announceJob: Job? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private val gson = Gson()
    private val fingerprint = UUID.randomUUID().toString().take(8)

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

        listenJob = scope.launch {
            listenForDevices(onDeviceFound)
        }

        announceJob = scope.launch {
            announcePresence()
        }
    }

    private suspend fun listenForDevices(onDeviceFound: (DeviceInfo) -> Unit) {
        try {
            val socket = MulticastSocket(PORT)
            socket.reuseAddress = true

            val group = InetAddress.getByName(MULTICAST_GROUP)
            val networkInterface = getWifiNetworkInterface()
            if (networkInterface != null) {
                socket.networkInterface = networkInterface
            }
            socket.joinGroup(java.net.InetSocketAddress(group, PORT), networkInterface)

            val buffer = ByteArray(4096)
            val scope = CoroutineScope(Dispatchers.IO)

            while (scope.isActive) {
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
                    onDeviceFound(device)
                } catch (_: Exception) {
                    // Socket timeout or parse error, keep listening
                }
            }

            socket.leaveGroup(java.net.InetSocketAddress(group, PORT), networkInterface)
            socket.close()
        } catch (_: Exception) {
            // Failed to set up multicast
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

            val scope = CoroutineScope(Dispatchers.IO)
            while (scope.isActive) {
                try {
                    val packet = DatagramPacket(bytes, bytes.size, group, PORT)
                    socket.send(packet)
                } catch (_: Exception) {
                    // Send failed, retry next interval
                }
                delay(ANNOUNCE_INTERVAL_MS)
            }

            socket.close()
        } catch (_: Exception) {
            // Failed to set up announce socket
        }
    }

    private fun getWifiNetworkInterface(): NetworkInterface? {
        return try {
            NetworkInterface.getNetworkInterfaces()?.toList()?.firstOrNull { ni ->
                !ni.isLoopback && ni.isUp && ni.inetAddresses.toList().any {
                    it is java.net.Inet4Address && !it.isLoopbackAddress
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    fun stopDiscovery() {
        listenJob?.cancel()
        announceJob?.cancel()
        multicastLock?.release()
    }
}
