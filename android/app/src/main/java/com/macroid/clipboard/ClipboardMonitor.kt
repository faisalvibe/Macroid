package com.macroid.clipboard

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class ClipboardMonitor(private val context: Context) {

    companion object {
        private const val POLL_INTERVAL_MS = 500L
    }

    private val clipboardManager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    private var pollJob: Job? = null
    private var lastText: String = ""
    private var ignoreNextChange = false

    fun startMonitoring(onClipboardChanged: (String) -> Unit) {
        lastText = getCurrentClipboard()

        pollJob = CoroutineScope(Dispatchers.Main).launch {
            while (isActive) {
                delay(POLL_INTERVAL_MS)
                try {
                    val current = getCurrentClipboard()
                    if (current != lastText && !ignoreNextChange) {
                        lastText = current
                        onClipboardChanged(current)
                    }
                    ignoreNextChange = false
                } catch (_: Exception) {
                    // Clipboard access may fail
                }
            }
        }
    }

    fun writeToClipboard(text: String) {
        ignoreNextChange = true
        lastText = text
        val clip = ClipData.newPlainText("Macroid", text)
        clipboardManager.setPrimaryClip(clip)
    }

    private fun getCurrentClipboard(): String {
        return try {
            if (clipboardManager.hasPrimaryClip()) {
                clipboardManager.primaryClip?.getItemAt(0)?.text?.toString() ?: ""
            } else ""
        } catch (_: Exception) {
            ""
        }
    }

    fun stopMonitoring() {
        pollJob?.cancel()
    }
}
