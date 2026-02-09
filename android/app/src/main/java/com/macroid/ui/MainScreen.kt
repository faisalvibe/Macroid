package com.macroid.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.macroid.network.DeviceInfo

@Composable
fun MainScreen(
    clipboardText: String,
    connectedDevice: DeviceInfo?,
    isSearching: Boolean,
    clipboardHistory: List<String>,
    localIP: String,
    onTextChanged: (String) -> Unit,
    onHistoryItemClicked: (String) -> Unit,
    onClearHistory: () -> Unit,
    onConnectByIP: (String) -> Unit
) {
    var showHistory by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        TopBar(
            isConnected = connectedDevice != null,
            showHistory = showHistory,
            onToggleHistory = { showHistory = !showHistory }
        )

        HorizontalDivider(
            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
            thickness = 0.5.dp
        )

        if (showHistory) {
            HistoryPanel(
                history = clipboardHistory,
                onItemClicked = { text ->
                    onHistoryItemClicked(text)
                    showHistory = false
                },
                onClear = onClearHistory,
                modifier = Modifier.weight(1f)
            )
        } else {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp, vertical = 16.dp)
            ) {
                if (clipboardText.isEmpty()) {
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

        HorizontalDivider(
            color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
            thickness = 0.5.dp
        )

        StatusBar(
            connectedDevice = connectedDevice,
            isSearching = isSearching,
            localIP = localIP,
            onConnectByIP = onConnectByIP
        )
    }
}

@Composable
private fun TopBar(
    isConnected: Boolean,
    showHistory: Boolean,
    onToggleHistory: () -> Unit
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

        TextButton(onClick = onToggleHistory) {
            Text(
                text = if (showHistory) "Editor" else "History",
                style = TextStyle(
                    fontSize = 14.sp,
                    color = MaterialTheme.colorScheme.primary
                )
            )
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
private fun StatusBar(
    connectedDevice: DeviceInfo?,
    isSearching: Boolean,
    localIP: String,
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
                OutlinedTextField(
                    value = manualIP,
                    onValueChange = { manualIP = it },
                    label = { Text("IP address") },
                    placeholder = { Text("192.168.1.100") },
                    singleLine = true
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    val ip = manualIP.trim()
                    if (ip.isNotEmpty()) {
                        onConnectByIP(ip)
                    }
                    showConnectDialog = false
                    manualIP = ""
                }) { Text("Connect") }
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
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(
                    if (connectedDevice != null) Color(0xFF34C759) else Color(0xFFFF3B30)
                )
        )

        Spacer(modifier = Modifier.width(8.dp))

        if (connectedDevice != null) {
            Text(
                text = "Connected to: ${connectedDevice.alias}",
                style = TextStyle(
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            )
            Spacer(modifier = Modifier.weight(1f))
            Text(
                text = connectedDevice.address,
                style = TextStyle(
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
                )
            )
        } else {
            Text(
                text = "My IP: $localIP",
                style = TextStyle(
                    fontSize = 13.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            )
            Spacer(modifier = Modifier.weight(1f))
            TextButton(onClick = { showConnectDialog = true }) {
                Text(
                    text = "Connect by IP",
                    style = TextStyle(
                        fontSize = 12.sp,
                        color = MaterialTheme.colorScheme.primary
                    )
                )
            }
        }
    }
}
