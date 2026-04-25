package dev.mirrorcore.agent

object Ports {
    const val CONTROL_PORT = 27183
    const val VIDEO_PORT = 27184

    /** When WiFi mode is enabled, bind to all interfaces. USB mode binds only to loopback. */
    var BIND_HOST = "127.0.0.1"
        private set

    fun enableWifiMode() {
        BIND_HOST = "0.0.0.0"
    }

    fun enableUsbMode() {
        BIND_HOST = "127.0.0.1"
    }
}
