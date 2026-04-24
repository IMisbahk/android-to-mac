package dev.mirrorcore.agent.capture

import android.graphics.ImageFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
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

class ImageReaderH264Backend : CaptureBackend {
    private val running = AtomicBoolean(false)
    private var codec: MediaCodec? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var inputThread: Thread? = null
    private var outputThread: Thread? = null

    override fun start(projection: MediaProjection, config: MirrorConfig, sender: VideoSender) {
        if (!running.compareAndSet(false, true)) return

        val dm = android.content.res.Resources.getSystem().displayMetrics
        val baseW = dm.widthPixels
        val baseH = dm.heightPixels
        val w = even((baseW * config.scale).toInt().coerceAtLeast(2))
        val h = even((baseH * config.scale).toInt().coerceAtLeast(2))

        val bitrate = if (config.bitratebps > 0) config.bitratebps else autoBitrate(w, h, config.fps)

        val reader = ImageReader.newInstance(w, h, ImageFormat.YUV_420_888, 2)
        this.reader = reader

        val format = MediaFormat.createVideoFormat(MIME, w, h).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, config.fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }

        val codec = MediaCodec.createEncoderByType(MIME)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
        this.codec = codec

        val display = projection.createVirtualDisplay(
            "MirrorCoreFallback",
            w,
            h,
            dm.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface,
            null,
            null,
        )
        this.display = display

        inputThread = Thread { runInputLoop(codec, reader, w, h) }.also {
            it.name = "MirrorCoreImageInput"
            it.start()
        }
        outputThread = Thread { runOutputLoop(codec, w, h, config.fps, sender) }.also {
            it.name = "MirrorCoreImageOutput"
            it.start()
        }
    }

    override fun stop() {
        running.set(false)
        try {
            inputThread?.join(1000)
        } catch (_: Throwable) {
        }
        try {
            outputThread?.join(1000)
        } catch (_: Throwable) {
        }
        inputThread = null
        outputThread = null

        try {
            display?.release()
        } catch (_: Throwable) {
        }
        display = null

        try {
            reader?.close()
        } catch (_: Throwable) {
        }
        reader = null

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

    private fun runInputLoop(codec: MediaCodec, reader: ImageReader, w: Int, h: Int) {
        try {
            while (running.get()) {
                val image = reader.acquireLatestImage()
                if (image == null) {
                    SystemClock.sleep(2)
                    continue
                }
                image.use {
                    val i420 = imageToI420(it, w, h)
                    val inIndex = codec.dequeueInputBuffer(0)
                    if (inIndex >= 0) {
                        val inBuf = codec.getInputBuffer(inIndex)
                        if (inBuf != null && inBuf.capacity() >= i420.size) {
                            inBuf.clear()
                            inBuf.put(i420)
                            val pts = System.nanoTime() / 1000
                            codec.queueInputBuffer(inIndex, 0, i420.size, pts, 0)
                        } else {
                            codec.queueInputBuffer(inIndex, 0, 0, 0, 0)
                        }
                    }
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "input loop error: ${t.message}", t)
        }
    }

    private fun runOutputLoop(codec: MediaCodec, w: Int, h: Int, fps: Int, sender: VideoSender) {
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
                        try {
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
                        } catch (t: Throwable) {
                            Log.w(TAG, "send config failed: ${t.message}")
                            running.set(false)
                            break
                        }
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
                                try {
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
                                } catch (t: Throwable) {
                                    Log.w(TAG, "send frame failed: ${t.message}")
                                    running.set(false)
                                    break
                                }
                            }
                        }
                        codec.releaseOutputBuffer(outIndex, false)
                    }
                }

                val now = SystemClock.elapsedRealtime()
                if (now - lastLog >= 1000) {
                    val kbps = (bytes * 8.0 / (now - lastLog).toDouble()).toLong()
                    Log.i(TAG, "ImageReaderH264: fps=$frames kbps=$kbps")
                    frames = 0
                    bytes = 0
                    lastLog = now
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "output loop error: ${t.message}", t)
        }
    }

    private fun imageToI420(image: Image, w: Int, h: Int): ByteArray {
        val ySize = w * h
        val uvSize = (w / 2) * (h / 2)
        val out = ByteArray(ySize + uvSize + uvSize)

        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        copyPlane(
            plane = yPlane.buffer,
            rowStride = yPlane.rowStride,
            pixelStride = yPlane.pixelStride,
            width = w,
            height = h,
            out = out,
            outOffset = 0,
            outRowStride = w,
        )

        copyPlane(
            plane = uPlane.buffer,
            rowStride = uPlane.rowStride,
            pixelStride = uPlane.pixelStride,
            width = w / 2,
            height = h / 2,
            out = out,
            outOffset = ySize,
            outRowStride = w / 2,
        )

        copyPlane(
            plane = vPlane.buffer,
            rowStride = vPlane.rowStride,
            pixelStride = vPlane.pixelStride,
            width = w / 2,
            height = h / 2,
            out = out,
            outOffset = ySize + uvSize,
            outRowStride = w / 2,
        )

        return out
    }

    private fun copyPlane(
        plane: ByteBuffer,
        rowStride: Int,
        pixelStride: Int,
        width: Int,
        height: Int,
        out: ByteArray,
        outOffset: Int,
        outRowStride: Int,
    ) {
        val base = plane.duplicate()
        for (row in 0 until height) {
            val rowStart = row * rowStride
            for (col in 0 until width) {
                out[outOffset + row * outRowStride + col] = base.get(rowStart + col * pixelStride)
            }
        }
    }

    private fun even(v: Int): Int = if (v % 2 == 0) v else v - 1

    private fun autoBitrate(w: Int, h: Int, fps: Int): Int {
        val pixels = w.toLong() * h.toLong()
        val bpp = 0.18
        val bps = (pixels.toDouble() * fps.toDouble() * bpp).toLong()
        return bps.coerceIn(2_000_000L, 24_000_000L).toInt()
    }

    companion object {
        private const val TAG = "MirrorCoreImageReaderH264"
        private const val MIME = "video/avc"
    }
}

private inline fun <T : AutoCloseable?, R> T.use(block: (T) -> R): R {
    try {
        return block(this)
    } finally {
        try {
            this?.close()
        } catch (_: Throwable) {
        }
    }
}
