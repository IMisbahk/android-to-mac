package dev.mirrorcore.agent

import android.util.Log
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class AudioServer(private val onClient: (Socket) -> Unit) {
    private val running = AtomicBoolean(false)
    private val executor = Executors.newSingleThreadExecutor()
    private var serverSocket: ServerSocket? = null

    fun start() {
        if (!running.compareAndSet(false, true)) return
        val addr = InetAddress.getByName(Ports.BIND_HOST)
        val ss = ServerSocket(AudioPorts.AUDIO_PORT, 1, addr)
        serverSocket = ss
        executor.execute {
            Log.i(TAG, "Audio server listening on ${Ports.BIND_HOST}:${AudioPorts.AUDIO_PORT}")
            while (running.get()) {
                val sock = try {
                    ss.accept()
                } catch (_: Throwable) {
                    break
                }
                try {
                    onClient(sock)
                } catch (t: Throwable) {
                    Log.w(TAG, "Audio client handler error", t)
                    try {
                        sock.close()
                    } catch (_: Throwable) {
                    }
                }
            }
        }
    }

    fun stop() {
        running.set(false)
        try {
            serverSocket?.close()
        } catch (_: Throwable) {
        }
        executor.shutdownNow()
    }

    companion object {
        private const val TAG = "MirrorCoreAudio"
    }
}

