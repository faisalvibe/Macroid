package com.macroid.clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import com.macroid.util.AppLog
import java.io.ByteArrayOutputStream

class ClipboardMonitor(private val context: Context) {

    companion object {
        private const val TAG = "ClipboardMonitor"
        private const val POLL_INTERVAL_MS = 500L
    }

    private val clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    private var pollJob: Job? = null
    private var lastText: String = ""
    @Volatile
    private var lastRemoteText: String = ""
    @Volatile
    private var lastRemoteImageHash: Int = 0

    fun startMonitoring(onClipboardChanged: (String) -> Unit, onImageChanged: (ByteArray) -> Unit = {}) {
        lastText = getCurrentClipboard()

        pollJob = CoroutineScope(Dispatchers.Main).launch {
            while (isActive) {
                delay(POLL_INTERVAL_MS)
                try {
                    // Check for image first
                    val imageBytes = getCurrentImage()
                    if (imageBytes != null) {
                        val hash = imageBytes.contentHashCode()
                        if (hash != lastRemoteImageHash) {
                            Log.d(TAG, "Local clipboard image changed (${imageBytes.size} bytes)")
                            onImageChanged(imageBytes)
                            lastRemoteImageHash = hash
                        }
                        continue
                    }

                    // If clipboard has a URI (e.g., our own image), skip text detection
                    // to avoid syncing empty string when image was just written
                    if (hasClipboardUri()) continue

                    val current = getCurrentClipboard()
                    if (current != lastText) {
                        lastText = current
                        if (current == lastRemoteText) {
                            Log.d(TAG, "Skipping echo of remote text")
                        } else {
                            Log.d(TAG, "Local clipboard changed (${current.length} chars)")
                            onClipboardChanged(current)
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Clipboard access failed", e)
                }
            }
        }
    }

    fun writeToClipboard(text: String) {
        lastRemoteText = text
        lastText = text
        val clip = ClipData.newPlainText("Macroid", text)
        clipboardManager.setPrimaryClip(clip)
        Log.d(TAG, "Wrote remote text to clipboard (${text.length} chars)")
    }

    fun writeImageToClipboard(imageBytes: ByteArray) {
        lastRemoteImageHash = imageBytes.contentHashCode()
        try {
            val file = java.io.File(context.cacheDir, "macroid_clipboard.png")
            file.writeBytes(imageBytes)
            val uri = androidx.core.content.FileProvider.getUriForFile(
                context, "${context.packageName}.fileprovider", file
            )
            val clip = ClipData.newUri(context.contentResolver, "Macroid Image", uri)
            clipboardManager.setPrimaryClip(clip)
            Log.d(TAG, "Wrote remote image to clipboard (${imageBytes.size} bytes)")
            AppLog.add("[Clipboard] Wrote image to clipboard (${imageBytes.size} bytes) via $uri")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to write image to clipboard", e)
            AppLog.add("[Clipboard] ERROR writing image: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    private fun getCurrentClipboard(): String {
        return try {
            if (clipboardManager.hasPrimaryClip()) {
                clipboardManager.primaryClip?.getItemAt(0)?.text?.toString() ?: ""
            } else ""
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read clipboard", e)
            ""
        }
    }

    private fun hasClipboardUri(): Boolean {
        return try {
            if (!clipboardManager.hasPrimaryClip()) false
            else clipboardManager.primaryClip?.getItemAt(0)?.uri != null
        } catch (e: Exception) {
            false
        }
    }

    private fun getCurrentImage(): ByteArray? {
        return try {
            if (!clipboardManager.hasPrimaryClip()) return null
            val clip = clipboardManager.primaryClip ?: return null
            val item = clip.getItemAt(0) ?: return null
            val uri = item.uri ?: return null

            // Skip our own FileProvider URIs - these are echoes from writeImageToClipboard
            if (uri.authority == "${context.packageName}.fileprovider") return null

            val mimeType = context.contentResolver.getType(uri) ?: return null
            if (!mimeType.startsWith("image/")) return null

            context.contentResolver.openInputStream(uri)?.use { stream ->
                val bitmap = BitmapFactory.decodeStream(stream) ?: return null
                val baos = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, baos)
                baos.toByteArray()
            }
        } catch (e: Exception) {
            null
        }
    }

    fun stopMonitoring() {
        pollJob?.cancel()
        Log.d(TAG, "Monitoring stopped")
    }
}
