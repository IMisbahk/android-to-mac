package dev.mirrorcore.agent.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.os.Build
import android.os.Process
import android.util.Log
import dev.mirrorcore.agent.AudioSender
import java.util.concurrent.atomic.AtomicBoolean

class AudioCapture {
    private val running = AtomicBoolean(false)
    private var thread: Thread? = null
    private var record: AudioRecord? = null

    fun start(projection: MediaProjection, sender: AudioSender) {
        if (!running.compareAndSet(false, true)) return
        if (Build.VERSION.SDK_INT < 29) {
            Log.w(TAG, "Audio capture requires API 29+")
            running.set(false)
            return
        }

        val sampleRate = 48_000
        val channels = 2
        val channelMask = AudioFormat.CHANNEL_IN_STEREO
        val encoding = AudioFormat.ENCODING_PCM_16BIT

        val frameSamples = 960 // 20ms at 48k
        val bytesPerFrame = frameSamples * channels * 2

        val playbackConfig = AudioPlaybackCaptureConfiguration.Builder(projection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()

        val format = AudioFormat.Builder()
            .setSampleRate(sampleRate)
            .setEncoding(encoding)
            .setChannelMask(channelMask)
            .build()

        val minBuf = AudioRecord.getMinBufferSize(sampleRate, channelMask, encoding).coerceAtLeast(bytesPerFrame * 4)
        val rec = AudioRecord.Builder()
            .setAudioPlaybackCaptureConfig(playbackConfig)
            .setAudioFormat(format)
            .setBufferSizeInBytes(minBuf)
            .build()

        record = rec
        rec.startRecording()

        sender.sendAudioConfig(sampleRate, channels, frameSamples, timestampUs())

        thread = Thread {
            Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
            val buf = ByteArray(bytesPerFrame)
            var ptsUs = 0L
            try {
                while (running.get()) {
                    val n = rec.read(buf, 0, buf.size)
                    if (n <= 0) continue
                    if (n != buf.size) {
                        // Keep framing fixed-size for low-latency playback on host.
                        continue
                    }
                    ptsUs += 20_000
                    sender.sendAudioFrame(ptsUs, buf, timestampUs())
                }
            } catch (t: Throwable) {
                Log.e(TAG, "audio loop error: ${t.message}", t)
            }
        }.also { it.name = "MirrorCoreAudioCapture"; it.start() }
    }

    fun stop() {
        running.set(false)
        try {
            thread?.join(500)
        } catch (_: Throwable) {
        }
        thread = null
        try {
            record?.stop()
        } catch (_: Throwable) {
        }
        try {
            record?.release()
        } catch (_: Throwable) {
        }
        record = null
    }

    private fun timestampUs(): Long = System.nanoTime() / 1000

    companion object {
        private const val TAG = "MirrorCoreAudioCapture"
    }
}

