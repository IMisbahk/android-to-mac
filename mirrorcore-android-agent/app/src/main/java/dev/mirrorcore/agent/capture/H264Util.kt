package dev.mirrorcore.agent.capture

import java.nio.ByteBuffer

object H264Util {
    private val START_CODE_4 = byteArrayOf(0, 0, 0, 1)
    private val START_CODE_3 = byteArrayOf(0, 0, 1)

    fun isAnnexB(data: ByteArray): Boolean {
        if (data.size >= 4 && data[0] == 0.toByte() && data[1] == 0.toByte() && data[2] == 0.toByte() && data[3] == 1.toByte()) {
            return true
        }
        if (data.size >= 3 && data[0] == 0.toByte() && data[1] == 0.toByte() && data[2] == 1.toByte()) {
            return true
        }
        return false
    }

    fun avccToAnnexB(avcc: ByteArray): ByteArray {
        val out = ArrayList<ByteArray>()
        var offset = 0
        var total = 0
        while (offset + 4 <= avcc.size) {
            val len =
                ((avcc[offset].toInt() and 0xFF) shl 24) or
                    ((avcc[offset + 1].toInt() and 0xFF) shl 16) or
                    ((avcc[offset + 2].toInt() and 0xFF) shl 8) or
                    (avcc[offset + 3].toInt() and 0xFF)
            offset += 4
            if (len <= 0 || offset + len > avcc.size) break
            val chunk = ByteArray(START_CODE_4.size + len)
            System.arraycopy(START_CODE_4, 0, chunk, 0, START_CODE_4.size)
            System.arraycopy(avcc, offset, chunk, START_CODE_4.size, len)
            out.add(chunk)
            total += chunk.size
            offset += len
        }
        if (out.isEmpty()) return avcc
        val merged = ByteArray(total)
        var dst = 0
        for (c in out) {
            System.arraycopy(c, 0, merged, dst, c.size)
            dst += c.size
        }
        return merged
    }

    fun stripStartCode(nal: ByteArray): ByteArray {
        if (nal.size >= 4 && nal[0] == 0.toByte() && nal[1] == 0.toByte() && nal[2] == 0.toByte() && nal[3] == 1.toByte()) {
            return nal.copyOfRange(4, nal.size)
        }
        if (nal.size >= 3 && nal[0] == 0.toByte() && nal[1] == 0.toByte() && nal[2] == 1.toByte()) {
            return nal.copyOfRange(3, nal.size)
        }
        return nal
    }

    fun toByteArray(buf: ByteBuffer): ByteArray {
        val dup = buf.duplicate()
        val out = ByteArray(dup.remaining())
        dup.get(out)
        return out
    }
}

