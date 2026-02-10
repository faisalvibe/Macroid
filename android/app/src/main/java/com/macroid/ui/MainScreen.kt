package com.macroid.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.macroid.network.DeviceInfo
import com.macroid.util.AppLog

@Composable
fun MainScreen(
    clipboardText: String,
    connectedDevice: DeviceInfo?,
    isSearching: Boolean,
    clipboardHistory: List<String>,
    localIP: String,
    connectionStatus: String,
    lastReceivedImage: ByteArray? = null,
    onTextChanged: (String) -> Unit,
    onHistoryItemClicked: (String) -> Unit,
    onClearHistory: () -> Unit,
    onConnectByIP: (String) -> Unit
) {
    // 0 = editor, 1 = history, 2 = logs
    var currentTab by remember { mutableStateOf(0) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        TopBar(
            isConnected = connectedDevice != null,
            currentTab = currentTab,
            onTabChanged = { currentTab = it }
        )

        HorizontalDivider(
            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
            thickness = 0.5.dp
        )

        when (currentTab) {
            1 -> {
                HistoryPanel(
                    history = clipboardHistory,
                    onItemClicked = { text ->
                        onHistoryItemClicked(text)
                        currentTab = 0
                    },
                    onClear = onClearHistory,
                    modifier = Modifier.weight(1f)
                )
            }
            2 -> {
                LogPanel(modifier = Modifier.weight(1f))
            }
            else -> {
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                ) {
                    // Image preview
                    if (lastReceivedImage != null) {
                        val bitmap = remember(lastReceivedImage) {
                            BitmapFactory.decodeByteArray(lastReceivedImage, 0, lastReceivedImage.size)
                        }
                        if (bitmap != null) {
                            val clipboardManager = LocalClipboardManager.current
                            val context = androidx.compose.ui.platform.LocalContext.current
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 24.dp, vertical = 8.dp),
                                horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally
                            ) {
                                Image(
                                    bitmap = bitmap.asImageBitmap(),
                                    contentDescription = "Synced image",
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .heightIn(max = 200.dp)
                                        .clip(RoundedCornerShape(8.dp))
                                        .clickable {
                                            // Copy image to clipboard
                                            val file = java.io.File(context.cacheDir, "macroid_share.png")
                                            file.writeBytes(lastReceivedImage)
                                            val uri = androidx.core.content.FileProvider.getUriForFile(
                                                context, "${context.packageName}.fileprovider", file
                                            )
                                            val clip = android.content.ClipData.newUri(context.contentResolver, "Macroid Image", uri)
                                            val cm = context.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                                            cm.setPrimaryClip(clip)
                                            AppLog.add("[UI] Image copied to clipboard")
                                        },
                                    contentScale = androidx.compose.ui.layout.ContentScale.Fit
                                )
                                Text(
                                    text = "Tap image to copy",
                                    style = TextStyle(
                                        fontSize = 11.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                                    ),
                                    modifier = Modifier.padding(top = 4.dp)
                                )
                            }
                        }
                    }

                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth()
                            .padding(horizontal = 24.dp, vertical = 8.dp)
                    ) {
                        if (clipboardText.isEmpty() && lastReceivedImage == null) {
                            Text(
                                text = "Copy something on either device...",
                                style = TextStyle(
                                    fontSize = 16.sp,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                                )
                            )
                        }

                        BasicTextField(
                            value = clipboardText,
                            onValueChange = onTextChanged,
                            modifier = Modifier.fillMaxSize(),
                            textStyle = TextStyle(
                                fontSize = 16.sp,
                                lineHeight = 24.sp,
                                color = MaterialTheme.colorScheme.onBackground
                            ),
                            cursorBrush = SolidColor(MaterialTheme.colorScheme.primary)
                        )
                    }
                }
            }
        }

        HorizontalDivider(
            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
            thickness = 0.5.dp
        )

        StatusBar(
            connectedDevice = connectedDevice,
            isSearching = isSearching,
            localIP = localIP,
            connectionStatus = connectionStatus,
            onConnectByIP = onConnectByIP
        )
    }
}

@Composable
private fun TopBar(
    isConnected: Boolean,
    currentTab: Int,
    onTabChanged: (Int) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(52.dp)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = "Macroid",
            style = TextStyle(
                fontSize = 18.sp,
                color = MaterialTheme.colorScheme.onBackground
            )
        )

        Spacer(modifier = Modifier.weight(1f))

        val tabs = listOf("Editor", "History", "Logs")
        tabs.forEachIndexed { index, label ->
            TextButton(onClick = { onTabChanged(index) }) {
                Text(
                    text = label,
                    style = TextStyle(
                        fontSize = 14.sp,
                        color = if (currentTab == index)
                            MaterialTheme.colorScheme.primary
                        else
                            MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                    )
                )
            }
        }

        Spacer(modifier = Modifier.width(8.dp))

        Box(
            modifier = Modifier
                .size(10.dp)
                .clip(CircleShape)
                .background(
                    if (isConnected) Color(0xFF34C759) else Color(0xFFFF3B30)
                )
        )
    }
}

@Composable
private fun HistoryPanel(
    history: List<String>,
    onItemClicked: (String) -> Unit,
    onClear: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier) {
        if (history.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "No clipboard history yet",
                    style = TextStyle(
                        fontSize = 15.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                    )
                )
            }
        } else {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "${history.size} items",
                    style = TextStyle(
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                )
                Spacer(modifier = Modifier.weight(1f))
                TextButton(onClick = onClear) {
                    Text(
                        text = "Clear",
                        style = TextStyle(
                            fontSize = 13.sp,
                            color = MaterialTheme.colorScheme.error
                        )
                    )
                }
            }

            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
            ) {
                items(history) { item ->
                    HistoryItem(text = item, onClick = { onItemClicked(item) })
                }
            }
        }
    }
}

@Composable
private fun HistoryItem(text: String, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 12.dp)
    ) {
        Text(
            text = text,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
            style = TextStyle(
                fontSize = 14.sp,
                lineHeight = 20.sp,
                color = MaterialTheme.colorScheme.onBackground
            )
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "${text.length} characters",
            style = TextStyle(
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
            )
        )
    }
    HorizontalDivider(
        color = MaterialTheme.colorScheme.outline.copy(alpha = 0.15f),
        thickness = 0.5.dp,
        modifier = Modifier.padding(horizontal = 16.dp)
    )
}

@Composable
private fun LogPanel(modifier: Modifier = Modifier) {
    val clipboardManager = LocalClipboardManager.current
    val logEntries = AppLog.entries

    Column(modifier = modifier) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "${logEntries.size} entries",
                style = TextStyle(
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            )
            Spacer(modifier = Modifier.weight(1f))
            TextButton(onClick = {
                clipboardManager.setText(AnnotatedString(AppLog.allText()))
            }) {
                Text(
                    text = "Copy All",
                    style = TextStyle(fontSize = 13.sp, color = MaterialTheme.colorScheme.primary)
                )
            }
            TextButton(onClick = { AppLog.clear() }) {
                Text(
                    text = "Clear",
                    style = TextStyle(fontSize = 13.sp, color = MaterialTheme.colorScheme.error)
                )
            }
        }

        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .padding(horizontal = 12.dp),
            reverseLayout = false
        ) {
            items(logEntries) { entry ->
                Text(
                    text = entry,
                    style = TextStyle(
                        fontSize = 11.sp,
                        lineHeight = 15.sp,
                        fontFamily = FontFamily.Monospace,
                        color = when {
                            entry.contains("ERROR") || entry.contains("FAILED") -> Color(0xFFFF3B30)
                            entry.contains("OK") || entry.contains("success", ignoreCase = true) || entry.contains("Connected") -> Color(0xFF34C759)
                            else -> MaterialTheme.colorScheme.onBackground.copy(alpha = 0.8f)
                        }
                    ),
                    modifier = Modifier.padding(vertical = 1.dp)
                )
            }
        }
    }
}

@Composable
private fun StatusBar(
    connectedDevice: DeviceInfo?,
    isSearching: Boolean,
    localIP: String,
    connectionStatus: String,
    onConnectByIP: (String) -> Unit
) {
    var showConnectDialog by remember { mutableStateOf(false) }
    var manualIP by remember { mutableStateOf("") }

    if (showConnectDialog) {
        AlertDialog(
            onDismissRequest = {
                showConnectDialog = false
                manualIP = ""
            },
            title = { Text("Connect by IP") },
            text = {
                Column {
                    Text(
                        text = "My IP: $localIP",
                        style = TextStyle(
                            fontSize = 13.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    )
                    Spacer(modifier = Modifier.height(12.dp))
                    OutlinedTextField(
                        value = manualIP,
                        onValueChange = { manualIP = it },
                        label = { Text("Device IP address") },
                        placeholder = { Text("192.168.1.100") },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                    )
                    if (connectionStatus.isNotEmpty()) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            if (connectionStatus == "Connecting...") {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(14.dp),
                                    strokeWidth = 2.dp
                                )
                                Spacer(modifier = Modifier.width(8.dp))
                            }
                            Text(
                                text = connectionStatus,
                                style = TextStyle(
                                    fontSize = 12.sp,
                                    color = when {
                                        connectionStatus.startsWith("Connected") -> Color(0xFF34C759)
                                        connectionStatus.startsWith("Failed") -> Color(0xFFFF3B30)
                                        else -> MaterialTheme.colorScheme.onSurfaceVariant
                                    }
                                )
                            )
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val ip = manualIP.trim()
                        if (ip.isNotEmpty()) {
                            onConnectByIP(ip)
                        }
                    },
                    enabled = connectionStatus != "Connecting..."
                ) { Text("Connect") }
            },
            dismissButton = {
                TextButton(onClick = {
                    showConnectDialog = false
                    manualIP = ""
                }) { Text("Cancel") }
            }
        )
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(
                    if (connectedDevice != null) Color(0xFF34C759) else Color(0xFFFF9500)
                )
        )

        Spacer(modifier = Modifier.width(10.dp))

        if (connectedDevice != null) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Connected to: ${connectedDevice.alias}",
                    style = TextStyle(
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onBackground
                    )
                )
                Text(
                    text = connectedDevice.address,
                    style = TextStyle(
                        fontSize = 11.sp,
                        color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.5f)
                    )
                )
            }
        } else {
            Text(
                text = if (isSearching) "Searching for devices..." else "Not connected",
                style = TextStyle(
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f)
                ),
                modifier = Modifier.weight(1f)
            )
            TextButton(onClick = { showConnectDialog = true }) {
                Text(
                    text = "Connect by IP",
                    style = TextStyle(
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.primary
                    )
                )
            }
        }
    }
}
