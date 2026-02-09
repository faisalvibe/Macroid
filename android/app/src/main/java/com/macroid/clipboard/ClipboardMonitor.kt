package com.macroid.clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

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

    fun startMonitoring(onClipboardChanged: (String) -> Unit) {
        lastText = getCurrentClipboard()

        pollJob = CoroutineScope(Dispatchers.Main).launch {
            while (isActive) {
                delay(POLL_INTERVAL_MS)
                try {
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

    fun stopMonitoring() {
        pollJob?.cancel()
        Log.d(TAG, "Monitoring stopped")
    }
}
