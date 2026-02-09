package com.macroid.clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.util.Log
import androidx.core.content.FileProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File

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
    private var lastImageHash: Int = 0
    @Volatile
    private var lastRemoteImageHash: Int = 0

    fun startMonitoring(onClipboardChanged: (String) -> Unit, onImageChanged: ((ByteArray) -> Unit)? = null) {
        lastText = getCurrentClipboard()

        pollJob = CoroutineScope(Dispatchers.Main).launch {
            while (isActive) {
                delay(POLL_INTERVAL_MS)
                try {
                    // Check for image first
                    val imageBytes = getCurrentClipboardImage()
                    if (imageBytes != null) {
                        val hash = imageBytes.contentHashCode()
                        if (hash != lastImageHash) {
                            lastImageHash = hash
                            lastText = ""
                            if (hash == lastRemoteImageHash) {
                                Log.d(TAG, "Skipping echo of remote image")
                            } else {
                                Log.d(TAG, "Local clipboard image changed (${imageBytes.size} bytes)")
                                onImageChanged?.invoke(imageBytes)
                            }
                        }
                        continue
                    }

                    // Check for text
                    val current = getCurrentClipboard()
                    if (current != lastText) {
                        lastText = current
                        lastImageHash = 0
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
        lastRemoteImageHash = 0
        lastText = text
        lastImageHash = 0
        val clip = ClipData.newPlainText("Macroid", text)
        clipboardManager.setPrimaryClip(clip)
        Log.d(TAG, "Wrote remote text to clipboard (${text.length} chars)")
    }

    fun writeImageToClipboard(data: ByteArray) {
        try {
            lastRemoteImageHash = data.contentHashCode()
            lastRemoteText = ""
            lastImageHash = data.contentHashCode()
            lastText = ""

            val file = File(context.cacheDir, "clipboard_image.png")
            file.writeBytes(data)

            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
            val clip = ClipData.newUri(context.contentResolver, "Macroid Image", uri)
            clipboardManager.setPrimaryClip(clip)
            Log.d(TAG, "Wrote remote image to clipboard (${data.size} bytes)")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to write image to clipboard", e)
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

    private fun getCurrentClipboardImage(): ByteArray? {
        return try {
            if (!clipboardManager.hasPrimaryClip()) return null
            val clip = clipboardManager.primaryClip ?: return null
            if (clip.itemCount == 0) return null

            val item = clip.getItemAt(0)
            val uri = item.uri ?: return null

            val mimeType = context.contentResolver.getType(uri) ?: return null
            if (!mimeType.startsWith("image/")) return null

            context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
        } catch (e: Exception) {
            null
        }
    }

    fun stopMonitoring() {
        pollJob?.cancel()
        Log.d(TAG, "Monitoring stopped")
    }
}
