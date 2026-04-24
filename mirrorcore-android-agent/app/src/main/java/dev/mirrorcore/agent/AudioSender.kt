package dev.mirrorcore.agent

import dev.mirrorcore.agent.mcb1.Mcb1Codec
import dev.mirrorcore.agent.mcb1.Mcb1Header
import dev.mirrorcore.agent.mcb1.Mcb1MsgType
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicLong

class AudioSender(private val output: OutputStream) {
    private val codec = Mcb1Codec()
    private val seq = AtomicLong(1)
    @Volatile
    private var configSent: Boolean = false

    fun sendAudioConfig(sampleRate: Int, channels: Int, frameSamples: Int, timestampUs: Long) {
        val payload = ByteBuffer.allocate(1 + 4 + 1 + 2 + 2).order(ByteOrder.LITTLE_ENDIAN).apply {
            put(1) // PCM_S16LE
            putInt(sampleRate)
            put(channels.toByte())
            putShort(frameSamples.toShort())
            putShort(0)
        }.array()

        val header = Mcb1Header.new(
            msgType = Mcb1MsgType.AUDIO_CONFIG,
            flags = 0,
            seq = seq.getAndIncrement(),
            timestampUs = timestampUs,
            payloadLen = payload.size,
        )
        codec.writeFrame(output, header, payload = payload)
        configSent = true
    }

    fun sendAudioFrame(ptsUs: Long, pcm: ByteArray, timestampUs: Long) {
        if (!configSent) throw IllegalStateException("AUDIO_CONFIG must be sent before frames")
        val payload = ByteBuffer.allocate(8 + 4 + pcm.size).order(ByteOrder.LITTLE_ENDIAN).apply {
            putLong(ptsUs)
            putInt(pcm.size)
            put(pcm)
        }.array()

        val header = Mcb1Header.new(
            msgType = Mcb1MsgType.AUDIO_FRAME,
            flags = 0,
            seq = seq.getAndIncrement(),
            timestampUs = timestampUs,
            payloadLen = payload.size,
        )
        codec.writeFrame(output, header, payload = payload)
    }
}

