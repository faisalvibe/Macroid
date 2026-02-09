package com.macroid.util

import android.util.Log
import androidx.compose.runtime.mutableStateListOf

object AppLog {
    private const val TAG = "MacroidLog"
    val entries = mutableStateListOf<String>()
    private const val MAX_ENTRIES = 200

    fun add(message: String) {
        Log.d(TAG, message)
        val timestamp = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
            .format(java.util.Date())
        val entry = "[$timestamp] $message"
        entries.add(entry)
        if (entries.size > MAX_ENTRIES) {
            entries.removeAt(0)
        }
    }

    fun allText(): String = entries.joinToString("\n")

    fun clear() { entries.clear() }
}
