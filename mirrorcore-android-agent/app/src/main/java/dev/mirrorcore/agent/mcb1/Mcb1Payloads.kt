package dev.mirrorcore.agent.mcb1

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

object Mcb1Payloads {
    data class Hello(
        val role: Int,
        val caps: Long,
        val deviceName: String,
        val sessionNonce: Long,
    )

    fun encodeHello(v: Hello): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(byteArrayOf(v.role.toByte()))
        out.write(le32(v.caps.toInt()))
        writeStrU16(out, v.deviceName)
        out.write(le64(v.sessionNonce))
        return out.toByteArray()
    }

    data class Ping(val echoTimestampUs: Long)

    fun encodePing(v: Ping): ByteArray = le64(v.echoTimestampUs)

    data class VideoConfig(
        val codec: Int,
        val width: Int,
        val height: Int,
        val fpsTimes1000: Long,
        val sps: ByteArray,
        val pps: ByteArray,
    )

    fun encodeVideoConfig(v: VideoConfig): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(byteArrayOf(v.codec.toByte()))
        out.write(le16(v.width))
        out.write(le16(v.height))
        out.write(le32(v.fpsTimes1000.toInt()))
        out.write(le32(v.sps.size))
        out.write(v.sps)
        out.write(le32(v.pps.size))
        out.write(v.pps)
        return out.toByteArray()
    }

    data class VideoFrame(
        val ptsUs: Long,
        val data: ByteArray,
    )

    fun encodeVideoFrame(v: VideoFrame): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(le64(v.ptsUs))
        out.write(le32(v.data.size))
        out.write(v.data)
        return out.toByteArray()
    }

    private fun le16(v: Int): ByteArray =
        ByteBuffer.allocate(2).order(ByteOrder.LITTLE_ENDIAN).putShort(v.toShort()).array()

    private fun le32(v: Int): ByteArray =
        ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(v).array()

    private fun le64(v: Long): ByteArray =
        ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putLong(v).array()

    private fun writeStrU16(out: ByteArrayOutputStream, s: String) {
        val bytes = s.toByteArray(Charsets.UTF_8)
        require(bytes.size <= 0xFFFF) { "string too long" }
        out.write(le16(bytes.size))
        out.write(bytes)
    }
}

