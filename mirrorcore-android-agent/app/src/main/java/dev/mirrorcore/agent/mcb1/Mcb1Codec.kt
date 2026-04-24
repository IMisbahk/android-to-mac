package dev.mirrorcore.agent.mcb1

import java.io.InputStream
import java.io.OutputStream
import java.util.zip.CRC32C

class Mcb1Codec(
    private val maxHeaderLen: Int = Mcb1Constants.MAX_HEADER_LEN,
    private val maxPayload: Int = Mcb1Constants.MAX_PAYLOAD,
) {
    fun readFrame(input: InputStream): Mcb1Frame {
        val base = input.readExact(Mcb1Constants.HEADER_LEN_V1)
        val header = Mcb1Header.decodeBase(base)
        header.validateSansCrc()

        if (header.headerLen > maxHeaderLen) throw Mcb1Error.InvalidHeaderLen(header.headerLen)
        if (header.payloadLen > maxPayload.toLong()) throw Mcb1Error.PayloadTooLarge(header.payloadLen)

        val extraLen = (header.headerLen - Mcb1Constants.HEADER_LEN_V1).coerceAtLeast(0)
        val headerExtra = if (extraLen == 0) ByteArray(0) else input.readExact(extraLen)
        val payload = if (header.payloadLen == 0L) ByteArray(0) else input.readExact(header.payloadLen.toInt())

        val actual = computeCrc32c(header.encodeBaseWithCrc(0), headerExtra, payload).toLong() and 0xFFFF_FFFFL
        if (actual != header.crc32c) throw Mcb1Error.CrcMismatch(header.crc32c, actual)

        return Mcb1Frame(header = header, headerExtra = headerExtra, payload = payload)
    }

    fun writeFrame(output: OutputStream, header: Mcb1Header, headerExtra: ByteArray = ByteArray(0), payload: ByteArray) {
        if (payload.size.toLong() != header.payloadLen) throw Mcb1Error.PayloadLenMismatch(header.payloadLen, payload.size.toLong())
        if (payload.size > maxPayload) throw Mcb1Error.PayloadTooLarge(payload.size.toLong())

        header.validateSansCrc()
        val baseZero = header.encodeBaseWithCrc(0)
        val crc = computeCrc32c(baseZero, headerExtra, payload)
        val baseWithCrc = header.encodeBaseWithCrc(crc)

        output.write(baseWithCrc)
        if (headerExtra.isNotEmpty()) output.write(headerExtra)
        if (payload.isNotEmpty()) output.write(payload)
        output.flush()
    }

    private fun computeCrc32c(baseHeader: ByteArray, headerExtra: ByteArray, payload: ByteArray): Int {
        val crc = CRC32C()
        val headerCopy = baseHeader.clone()
        for (i in 28 until 32) headerCopy[i] = 0
        crc.update(headerCopy)
        if (headerExtra.isNotEmpty()) crc.update(headerExtra)
        if (payload.isNotEmpty()) crc.update(payload)
        return crc.value.toInt()
    }
}

private fun InputStream.readExact(n: Int): ByteArray {
    val buf = ByteArray(n)
    var off = 0
    while (off < n) {
        val r = read(buf, off, n - off)
        if (r < 0) throw java.io.EOFException("unexpected eof")
        off += r
    }
    return buf
}

