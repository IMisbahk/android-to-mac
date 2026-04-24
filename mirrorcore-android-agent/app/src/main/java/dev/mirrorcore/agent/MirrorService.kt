package dev.mirrorcore.agent

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.concurrent.atomic.AtomicBoolean

class MirrorService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    private val running = AtomicBoolean(false)

    private var projection: MediaProjection? = null
    private var projectionCallback: MediaProjection.Callback? = null
    private var controller: MirrorController? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> handleStart(intent)
            ACTION_STOP -> handleStop()
            else -> Unit
        }
        return START_STICKY
    }

    private fun handleStart(intent: Intent) {
        if (!running.compareAndSet(false, true)) return

        startForeground(NOTIFICATION_ID, buildNotification())

        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
        val data = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(EXTRA_RESULT_DATA)
        }
        val config = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(EXTRA_CONFIG, MirrorConfig::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(EXTRA_CONFIG)
        } ?: MirrorConfig(1.0f, 60, 0)

        if (resultCode == 0 || data == null) {
            Log.e(TAG, "Missing MediaProjection result")
            stopSelf()
            return
        }

        val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        projection = mgr.getMediaProjection(resultCode, data)
        if (projection == null) {
            Log.e(TAG, "Failed to acquire MediaProjection")
            stopSelf()
            return
        }

        // Android 14+ requires registering a callback before creating VirtualDisplay/capture.
        val callback = object : MediaProjection.Callback() {
            override fun onStop() {
                Log.w(TAG, "MediaProjection stopped by system/user")
                handleStop()
            }
        }
        projectionCallback = callback
        projection!!.registerCallback(callback, Handler(Looper.getMainLooper()))
        Log.i(TAG, "Registered MediaProjection callback: projection=${projection.hashCode()}")

        val controller = MirrorController(
            applicationContext = applicationContext,
            projection = projection!!,
            config = config,
        )
        this.controller = controller
        controller.start()
    }

    private fun handleStop() {
        running.set(false)
        controller?.stop()
        controller = null
        projectionCallback?.let {
            try {
                projection?.unregisterCallback(it)
            } catch (_: Throwable) {
            }
        }
        projectionCallback = null
        projection?.stop()
        projection = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun buildNotification(): Notification {
        val channelId = NOTIFICATION_CHANNEL_ID
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "MirrorCore",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("MirrorCore")
            .setContentText("Mirroring service running")
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val TAG = "MirrorService"
        const val ACTION_START = "dev.mirrorcore.agent.action.START"
        const val ACTION_STOP = "dev.mirrorcore.agent.action.STOP"

        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"
        const val EXTRA_CONFIG = "config"

        private const val NOTIFICATION_CHANNEL_ID = "mirrorcore"
        private const val NOTIFICATION_ID = 1
    }
}
