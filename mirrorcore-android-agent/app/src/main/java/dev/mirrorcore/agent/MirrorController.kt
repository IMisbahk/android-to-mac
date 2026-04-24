package dev.mirrorcore.agent

import android.content.Context
import android.media.projection.MediaProjection
import android.util.Log
import dev.mirrorcore.agent.capture.CaptureBackend
import dev.mirrorcore.agent.capture.ImageReaderH264Backend
import dev.mirrorcore.agent.capture.SurfaceH264Backend
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
    private val activeBackend = AtomicReference<CaptureBackend?>(null)

    fun start() {
        controlServer.start()
        videoServer.start()
    }

    fun stop() {
        activeBackend.getAndSet(null)?.stop()
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

        // Replace any previous backend and restart capture on the new connection.
        activeBackend.getAndSet(null)?.stop()

        val sender = VideoSender(sock.getOutputStream())

        val backend: CaptureBackend = try {
            SurfaceH264Backend().also { it.start(projection, config, sender) }
        } catch (t: Throwable) {
            Log.w(TAG, "Surface backend failed, falling back to ImageReader: ${t.message}")
            ImageReaderH264Backend().also { it.start(projection, config, sender) }
        }

        activeBackend.set(backend)
    }

    companion object {
        private const val TAG = "MirrorCoreController"
    }
}
