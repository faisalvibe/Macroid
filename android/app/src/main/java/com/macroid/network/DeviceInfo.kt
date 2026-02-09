package com.macroid.network

data class DeviceInfo(
    val alias: String,
    val deviceType: String,
    val fingerprint: String,
    val address: String,
    val port: Int
)
