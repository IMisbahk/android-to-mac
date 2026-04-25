package dev.mirrorcore.agent

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.util.Log
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * Handles WiFi mode: binds servers to all interfaces and broadcasts
 * the device's presence via mDNS/NSD as `_mirrorcore._tcp`.
 */
class WifiDiscovery(private val context: Context) {
    private var nsdManager: NsdManager? = null
    private var registrationListener: NsdManager.RegistrationListener? = null

    companion object {
        private const val TAG = "MirrorCoreWifi"
        private const val SERVICE_TYPE = "_mirrorcore._tcp."
        private const val SERVICE_NAME = "MirrorCore"
    }

    /**
     * Register the device on the local network via mDNS.
     */
    fun startBroadcast() {
        val nsd = context.getSystemService(Context.NSD_SERVICE) as? NsdManager ?: run {
            Log.w(TAG, "NSD not available")
            return
        }
        nsdManager = nsd

        val serviceInfo = NsdServiceInfo().apply {
            serviceName = SERVICE_NAME
            serviceType = SERVICE_TYPE
            port = Ports.CONTROL_PORT
            setAttribute("video_port", Ports.VIDEO_PORT.toString())
            setAttribute("audio_port", AudioPorts.AUDIO_PORT.toString())
            setAttribute("device", android.os.Build.MODEL ?: "Android")
        }

        val listener = object : NsdManager.RegistrationListener {
            override fun onRegistrationFailed(si: NsdServiceInfo, errorCode: Int) {
                Log.e(TAG, "NSD registration failed: $errorCode")
            }
            override fun onUnregistrationFailed(si: NsdServiceInfo, errorCode: Int) {
                Log.e(TAG, "NSD unregistration failed: $errorCode")
            }
            override fun onServiceRegistered(si: NsdServiceInfo) {
                Log.i(TAG, "NSD service registered: ${si.serviceName}")
            }
            override fun onServiceUnregistered(si: NsdServiceInfo) {
                Log.i(TAG, "NSD service unregistered")
            }
        }
        registrationListener = listener
        nsd.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    fun stopBroadcast() {
        registrationListener?.let { listener ->
            try {
                nsdManager?.unregisterService(listener)
            } catch (_: Throwable) {}
        }
        registrationListener = null
    }

    /**
     * Get the device's WiFi IP address.
     */
    fun getWifiIpAddress(): String? {
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces()
            while (interfaces.hasMoreElements()) {
                val iface = interfaces.nextElement()
                if (iface.isLoopback || !iface.isUp) continue
                val addresses = iface.inetAddresses
                while (addresses.hasMoreElements()) {
                    val addr = addresses.nextElement()
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        return addr.hostAddress
                    }
                }
            }
        } catch (_: Throwable) {}
        return null
    }
}
