package dev.mirrorcore.agent.input

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.SystemClock
import android.util.Log

object InputInjection {
    @Volatile
    private var service: MirrorAccessibilityService? = null

    fun bind(service: MirrorAccessibilityService) {
        this.service = service
        Log.i(TAG, "Accessibility bound")
    }

    fun unbind(service: MirrorAccessibilityService) {
        if (this.service === service) {
            this.service = null
            Log.i(TAG, "Accessibility unbound")
        }
    }

    fun injectTouchNormalized(event: InputEvent.Touch) {
        val svc = service ?: return
        svc.injectTouchNormalized(event)
    }

    private const val TAG = "MirrorCoreInput"
}

class MirrorAccessibilityService : AccessibilityService() {
    private var downAtMs: Long = 0
    private var downX: Float = 0f
    private var downY: Float = 0f
    private var lastX: Float = 0f
    private var lastY: Float = 0f

    override fun onServiceConnected() {
        super.onServiceConnected()
        InputInjection.bind(this)
    }

    override fun onDestroy() {
        InputInjection.unbind(this)
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: android.view.accessibility.AccessibilityEvent?) {}
    override fun onInterrupt() {}

    fun injectTouchNormalized(ev: InputEvent.Touch) {
        val dm = resources.displayMetrics
        val x = (ev.xNorm.coerceIn(0f, 1f) * dm.widthPixels.toFloat())
        val y = (ev.yNorm.coerceIn(0f, 1f) * dm.heightPixels.toFloat())

        when (ev.action) {
            TouchAction.Down -> {
                downAtMs = SystemClock.uptimeMillis()
                downX = x
                downY = y
                lastX = x
                lastY = y
            }
            TouchAction.Move -> {
                lastX = x
                lastY = y
            }
            TouchAction.Up -> {
                val dt = (SystemClock.uptimeMillis() - downAtMs).coerceAtLeast(1)
                val dx = (lastX - downX)
                val dy = (lastY - downY)
                val dist2 = dx * dx + dy * dy

                val path = Path().apply {
                    moveTo(downX, downY)
                    lineTo(lastX, lastY)
                }

                val duration = if (dist2 < 25f) 50L else dt.coerceIn(50L, 500L)
                dispatchGesture(
                    GestureDescription.Builder()
                        .addStroke(GestureDescription.StrokeDescription(path, 0, duration))
                        .build(),
                    null,
                    null,
                )
            }
            TouchAction.Cancel -> {
                downAtMs = 0
            }
        }
    }
}

