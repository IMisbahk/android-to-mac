package dev.mirrorcore.agent

import android.content.Context
import android.media.projection.MediaProjection
import android.util.Log
import dev.mirrorcore.agent.capture.CaptureBackend
import dev.mirrorcore.agent.capture.ImageReaderH264Backend
import dev.mirrorcore.agent.capture.SurfaceH264Backend
import dev.mirrorcore.agent.audio.AudioCapture
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

    private val activeAudioSocket = AtomicReference<Socket?>(null)
    private val audioServer = AudioServer { sock -> onAudioClient(sock) }
    private val audioCapture = AudioCapture()

    fun start() {
        controlServer.start()
        videoServer.start()
        audioServer.start()
    }

    fun stop() {
        activeBackend.getAndSet(null)?.stop()
        audioCapture.stop()
        videoServer.stop()
        controlServer.stop()
        audioServer.stop()
        activeVideoSocket.getAndSet(null)?.let {
            try {
                it.close()
            } catch (_: Throwable) {
            }
        }
        activeAudioSocket.getAndSet(null)?.let {
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

        try {
            val sender = VideoSender(sock.getOutputStream())

            val backend: CaptureBackend = try {
                Log.i(TAG, "Starting SurfaceH264 backend...")
                SurfaceH264Backend().also { it.start(projection, config, sender) }
            } catch (t: Throwable) {
                Log.w(TAG, "Surface backend failed, falling back to ImageReader", t)
                Log.i(TAG, "Starting ImageReaderH264 backend...")
                ImageReaderH264Backend().also { it.start(projection, config, sender) }
            }

            activeBackend.set(backend)
        } catch (t: Throwable) {
            Log.e(TAG, "Video client setup failed", t)
            try {
                sock.close()
            } catch (_: Throwable) {
            }
        }
    }

    private fun onAudioClient(sock: Socket) {
        sock.tcpNoDelay = true
        Log.i(TAG, "Audio client connected from ${sock.inetAddress}")
        activeAudioSocket.getAndSet(sock)?.let {
            try {
                it.close()
            } catch (_: Throwable) {
            }
        }

        try {
            val sender = AudioSender(sock.getOutputStream())
            audioCapture.stop()
            audioCapture.start(projection, sender)
        } catch (t: Throwable) {
            Log.e(TAG, "Audio client setup failed", t)
            try {
                sock.close()
            } catch (_: Throwable) {
            }
        }
    }

    companion object {
        private const val TAG = "MirrorCoreController"
    }
}
