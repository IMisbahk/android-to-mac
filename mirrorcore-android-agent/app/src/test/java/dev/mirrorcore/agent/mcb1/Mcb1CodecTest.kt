package dev.mirrorcore.agent.mcb1

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream

class Mcb1CodecTest {
    @Test
    fun decode_golden_hello_frame_ok() {
        val bytes = load("vectors/hello_android.bin")
        val codec = Mcb1Codec()
        val frame = codec.readFrame(ByteArrayInputStream(bytes))

        assertEquals(Mcb1MsgType.HELLO, frame.header.msgType)
        assertTrue(frame.payload.isNotEmpty())
    }

    @Test
    fun decode_golden_ping_frame_ok() {
        val bytes = load("vectors/ping.bin")
        val codec = Mcb1Codec()
        val frame = codec.readFrame(ByteArrayInputStream(bytes))

        assertEquals(Mcb1MsgType.PING, frame.header.msgType)
        assertEquals(8, frame.payload.size)
    }

    @Test(expected = Mcb1Error.CrcMismatch::class)
    fun crc_mismatch_rejected() {
        val bytes = load("vectors/ping.bin").copyOf()
        bytes[bytes.size - 1] = (bytes[bytes.size - 1].toInt() xor 0x01).toByte()
        val codec = Mcb1Codec()
        codec.readFrame(ByteArrayInputStream(bytes))
    }

    private fun load(path: String): ByteArray {
        val stream = this::class.java.classLoader!!.getResourceAsStream(path)
            ?: throw IllegalStateException("missing resource: $path")
        return stream.use { it.readBytes() }
    }
}

