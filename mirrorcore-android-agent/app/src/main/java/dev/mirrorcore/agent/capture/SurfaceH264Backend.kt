package dev.mirrorcore.agent.capture

import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.os.SystemClock
import android.util.Log
import dev.mirrorcore.agent.MirrorConfig
import dev.mirrorcore.agent.VideoSender
import dev.mirrorcore.agent.mcb1.Mcb1Payloads
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

class SurfaceH264Backend : CaptureBackend {
    private val running = AtomicBoolean(false)
    private var codec: MediaCodec? = null
    private var display: VirtualDisplay? = null
    private var thread: Thread? = null

    override fun start(projection: MediaProjection, config: MirrorConfig, sender: VideoSender) {
        if (!running.compareAndSet(false, true)) return

        val dm = android.content.res.Resources.getSystem().displayMetrics
        val baseW = dm.widthPixels
        val baseH = dm.heightPixels
        val w = even((baseW * config.scale).toInt().coerceAtLeast(2))
        val h = even((baseH * config.scale).toInt().coerceAtLeast(2))

        val bitrate = if (config.bitratebps > 0) config.bitratebps else autoBitrate(w, h, config.fps)

        val format = MediaFormat.createVideoFormat(MIME, w, h).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, config.fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }

        val codec = MediaCodec.createEncoderByType(MIME)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val surface = codec.createInputSurface()
        codec.start()
        this.codec = codec

        val display = projection.createVirtualDisplay(
            "MirrorCore",
            w,
            h,
            dm.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            surface,
            null,
            null,
        )
        this.display = display

        thread = Thread {
            runEncoderLoop(codec, w, h, config.fps, sender)
        }.also { it.name = "MirrorCoreSurfaceH264"; it.start() }
    }

    override fun stop() {
        running.set(false)
        try {
            thread?.join(1000)
        } catch (_: Throwable) {
        }
        thread = null
        try {
            display?.release()
        } catch (_: Throwable) {
        }
        display = null
        try {
            codec?.stop()
        } catch (_: Throwable) {
        }
        try {
            codec?.release()
        } catch (_: Throwable) {
        }
        codec = null
    }

    private fun runEncoderLoop(codec: MediaCodec, w: Int, h: Int, fps: Int, sender: VideoSender) {
        val info = MediaCodec.BufferInfo()
        var sentConfig = false

        var frames = 0
        var bytes = 0L
        var lastLog = SystemClock.elapsedRealtime()

        try {
            while (running.get()) {
                val outIndex = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val fmt = codec.outputFormat
                        val sps = fmt.getByteBuffer("csd-0")?.let { H264Util.stripStartCode(H264Util.toByteArray(it)) } ?: ByteArray(0)
                        val pps = fmt.getByteBuffer("csd-1")?.let { H264Util.stripStartCode(H264Util.toByteArray(it)) } ?: ByteArray(0)
                        sender.sendVideoConfig(
                            Mcb1Payloads.VideoConfig(
                                codec = 1,
                                width = w,
                                height = h,
                                fpsTimes1000 = fps.toLong() * 1000L,
                                sps = sps,
                                pps = pps,
                            ),
                            timestampUs = System.nanoTime() / 1000,
                        )
                        sentConfig = true
                    }
                    outIndex >= 0 -> {
                        val buf: ByteBuffer = codec.getOutputBuffer(outIndex) ?: run {
                            codec.releaseOutputBuffer(outIndex, false)
                            continue
                        }
                        if (info.size > 0) {
                            buf.position(info.offset)
                            buf.limit(info.offset + info.size)
                            val chunk = ByteArray(info.size)
                            buf.get(chunk)
                            val annexb = if (H264Util.isAnnexB(chunk)) chunk else H264Util.avccToAnnexB(chunk)
                            val keyframe = (info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0
                            if (sentConfig) {
                                sender.sendVideoFrame(
                                    Mcb1Payloads.VideoFrame(
                                        ptsUs = info.presentationTimeUs,
                                        data = annexb,
                                    ),
                                    timestampUs = System.nanoTime() / 1000,
                                    keyframe = keyframe,
                                )
                                frames += 1
                                bytes += annexb.size.toLong()
                            }
                        }
                        codec.releaseOutputBuffer(outIndex, false)
                    }
                }

                val now = SystemClock.elapsedRealtime()
                if (now - lastLog >= 1000) {
                    val kbps = (bytes * 8.0 / (now - lastLog).toDouble()).toLong()
                    Log.i(TAG, "SurfaceH264: fps=$frames kbps=$kbps")
                    frames = 0
                    bytes = 0
                    lastLog = now
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "encoder loop error: ${t.message}", t)
        }
    }

    private fun even(v: Int): Int = if (v % 2 == 0) v else v - 1

    private fun autoBitrate(w: Int, h: Int, fps: Int): Int {
        val pixels = w.toLong() * h.toLong()
        val bpp = 0.12
        val bps = (pixels.toDouble() * fps.toDouble() * bpp).toLong()
        return bps.coerceIn(2_000_000L, 24_000_000L).toInt()
    }

    companion object {
        private const val TAG = "MirrorCoreSurfaceH264"
        private const val MIME = "video/avc"
    }
}
