package com.macroid.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.macroid.clipboard.ClipboardMonitor
import com.macroid.network.DeviceInfo
import com.macroid.network.Discovery
import com.macroid.network.SyncClient
import com.macroid.network.SyncServer

@Composable
fun MacroidApp() {
    MacroidTheme {
        val context = LocalContext.current

        var clipboardText by remember { mutableStateOf("") }
        var connectedDevice by remember { mutableStateOf<DeviceInfo?>(null) }
        var isSearching by remember { mutableStateOf(true) }

        val syncServer = remember { SyncServer() }
        val discovery = remember { Discovery(context) }
        val syncClient = remember { SyncClient() }
        val clipboardMonitor = remember { ClipboardMonitor(context) }

        DisposableEffect(Unit) {
            syncServer.start { incomingText ->
                clipboardText = incomingText
                clipboardMonitor.writeToClipboard(incomingText)
            }

            discovery.startDiscovery { device ->
                connectedDevice = device
                isSearching = false
                syncClient.setPeer(device)
            }

            clipboardMonitor.startMonitoring { newText ->
                if (newText != clipboardText) {
                    clipboardText = newText
                    syncClient.sendClipboard(newText)
                }
            }

            onDispose {
                clipboardMonitor.stopMonitoring()
                discovery.stopDiscovery()
                syncServer.stop()
            }
        }

        MainScreen(
            clipboardText = clipboardText,
            connectedDevice = connectedDevice,
            isSearching = isSearching,
            onTextChanged = { newText ->
                clipboardText = newText
                clipboardMonitor.writeToClipboard(newText)
                syncClient.sendClipboard(newText)
            }
        )
    }
}
