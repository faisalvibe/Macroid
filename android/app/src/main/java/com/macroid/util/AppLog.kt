package com.macroid.util

import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.compose.runtime.mutableStateListOf

object AppLog {
    private const val TAG = "MacroidLog"
    val entries = mutableStateListOf<String>()
    private const val MAX_ENTRIES = 200
    private val mainHandler = Handler(Looper.getMainLooper())

    fun add(message: String) {
        Log.d(TAG, message)
        val timestamp = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault())
            .format(java.util.Date())
        val entry = "[$timestamp] $message"
        if (Looper.myLooper() == Looper.getMainLooper()) {
            entries.add(entry)
            if (entries.size > MAX_ENTRIES) {
                entries.removeAt(0)
            }
        } else {
            mainHandler.post {
                entries.add(entry)
                if (entries.size > MAX_ENTRIES) {
                    entries.removeAt(0)
                }
            }
        }
    }

    fun allText(): String = entries.joinToString("\n")

    fun clear() {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            entries.clear()
        } else {
            mainHandler.post { entries.clear() }
        }
    }
}
