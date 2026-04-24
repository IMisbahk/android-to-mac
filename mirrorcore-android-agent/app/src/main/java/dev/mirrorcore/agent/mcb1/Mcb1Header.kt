package dev.mirrorcore.agent.mcb1

import java.nio.ByteBuffer
import java.nio.ByteOrder

data class Mcb1Header(
    val version: Int,
    val msgType: Int,
    val flags: Int,
    val headerLen: Int,
    val reserved: Int,
    val payloadLen: Long,
    val seq: Long,
    val timestampUs: Long,
    val crc32c: Long,
) {
    fun validateSansCrc() {
        if (version != Mcb1Constants.VERSION.toInt()) throw Mcb1Error.UnsupportedVersion(version)
        if (headerLen < Mcb1Constants.HEADER_LEN_V1 || headerLen > Mcb1Constants.MAX_HEADER_LEN) {
            throw Mcb1Error.InvalidHeaderLen(headerLen)
        }
        if (reserved != 0) throw Mcb1Error.InvalidReserved(reserved)
        if (payloadLen > Mcb1Constants.MAX_PAYLOAD.toLong()) throw Mcb1Error.PayloadTooLarge(payloadLen)
    }

    fun encodeBaseWithCrc(crc: Int): ByteArray {
        val out = ByteArray(Mcb1Constants.HEADER_LEN_V1)
        val bb = ByteBuffer.wrap(out).order(ByteOrder.LITTLE_ENDIAN)
        bb.put(Mcb1Constants.MAGIC)
        bb.put(version.toByte())
        bb.put(msgType.toByte())
        bb.putShort(flags.toShort())
        bb.putShort(headerLen.toShort())
        bb.putShort(reserved.toShort())
        bb.putInt(payloadLen.toInt())
        bb.putInt(seq.toInt())
        bb.putLong(timestampUs)
        bb.putInt(crc)
        return out
    }

    companion object {
        fun new(msgType: Int, flags: Int, seq: Long, timestampUs: Long, payloadLen: Int): Mcb1Header {
            return Mcb1Header(
                version = Mcb1Constants.VERSION.toInt(),
                msgType = msgType,
                flags = flags,
                headerLen = Mcb1Constants.HEADER_LEN_V1,
                reserved = 0,
                payloadLen = payloadLen.toLong(),
                seq = seq,
                timestampUs = timestampUs,
                crc32c = 0,
            )
        }

        fun decodeBase(bytes: ByteArray): Mcb1Header {
            if (bytes.size != Mcb1Constants.HEADER_LEN_V1) throw IllegalArgumentException("bad base header size")
            val bb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            val magic = ByteArray(4)
            bb.get(magic)
            if (!magic.contentEquals(Mcb1Constants.MAGIC)) throw Mcb1Error.InvalidMagic()

            val version = bb.get().toInt() and 0xFF
            val msgType = bb.get().toInt() and 0xFF
            val flags = bb.short.toInt() and 0xFFFF
            val headerLen = bb.short.toInt() and 0xFFFF
            val reserved = bb.short.toInt() and 0xFFFF
            val payloadLen = bb.int.toLong() and 0xFFFF_FFFFL
            val seq = bb.int.toLong() and 0xFFFF_FFFFL
            val timestampUs = bb.long
            val crc32c = bb.int.toLong() and 0xFFFF_FFFFL

            return Mcb1Header(
                version = version,
                msgType = msgType,
                flags = flags,
                headerLen = headerLen,
                reserved = reserved,
                payloadLen = payloadLen,
                seq = seq,
                timestampUs = timestampUs,
                crc32c = crc32c,
            )
        }
    }
}

