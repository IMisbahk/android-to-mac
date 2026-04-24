package dev.mirrorcore.agent

import dev.mirrorcore.agent.mcb1.Mcb1Codec
import dev.mirrorcore.agent.mcb1.Mcb1Header
import dev.mirrorcore.agent.mcb1.Mcb1MsgType
import dev.mirrorcore.agent.mcb1.Mcb1Payloads
import java.io.OutputStream
import java.util.concurrent.atomic.AtomicLong

class VideoSender(private val output: OutputStream) {
    private val codec = Mcb1Codec()
    private val seq = AtomicLong(1)
    @Volatile
    private var configSent: Boolean = false

    fun sendVideoConfig(cfg: Mcb1Payloads.VideoConfig, timestampUs: Long) {
        val payload = Mcb1Payloads.encodeVideoConfig(cfg)
        val header = Mcb1Header.new(
            msgType = Mcb1MsgType.VIDEO_CONFIG,
            flags = 0,
            seq = seq.getAndIncrement(),
            timestampUs = timestampUs,
            payloadLen = payload.size,
        )
        codec.writeFrame(output, header, payload = payload)
        configSent = true
    }

    fun sendVideoFrame(frame: Mcb1Payloads.VideoFrame, timestampUs: Long, keyframe: Boolean) {
        if (!configSent) throw IllegalStateException("VIDEO_CONFIG must be sent before frames")
        val payload = Mcb1Payloads.encodeVideoFrame(frame)
        val header = Mcb1Header.new(
            msgType = Mcb1MsgType.VIDEO_FRAME,
            flags = if (keyframe) 0x0004 else 0,
            seq = seq.getAndIncrement(),
            timestampUs = timestampUs,
            payloadLen = payload.size,
        )
        codec.writeFrame(output, header, payload = payload)
    }
}

