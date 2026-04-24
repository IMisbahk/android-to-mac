package dev.mirrorcore.agent

import android.content.Context
import android.media.projection.MediaProjection
import android.util.Log
import java.net.Socket
import java.util.concurrent.atomic.AtomicReference

class MirrorController(
    private val applicationContext: Context,
    private val projection: MediaProjection,
    private val config: MirrorConfig,
) {
    private val controlServer = ControlServer()
    private val activeVideoSocket = AtomicReference<Socket?>(null)
    private val videoServer = VideoServer { sock -> onVideoClient(sock) }

    fun start() {
        controlServer.start()
        videoServer.start()
    }

    fun stop() {
        videoServer.stop()
        controlServer.stop()
        activeVideoSocket.getAndSet(null)?.let {
            try {
                it.close()
            } catch (_: Throwable) {
            }
        }
    }

    private fun onVideoClient(sock: Socket) {
        sock.tcpNoDelay = true
        Log.i(TAG, "Video client connected from ${sock.inetAddress}")
        activeVideoSocket.getAndSet(sock)?.let {
            try {
                it.close()
            } catch (_: Throwable) {
            }
        }

        // Capture backend wiring is implemented in subsequent commits.
    }

    companion object {
        private const val TAG = "MirrorCoreController"
    }
}
