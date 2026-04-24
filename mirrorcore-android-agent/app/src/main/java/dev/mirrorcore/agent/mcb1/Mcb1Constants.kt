package dev.mirrorcore.agent.mcb1

object Mcb1Constants {
    val MAGIC: ByteArray = byteArrayOf('M'.code.toByte(), 'C'.code.toByte(), 'B'.code.toByte(), '1'.code.toByte())
    const val VERSION: Byte = 1

    const val HEADER_LEN_V1: Int = 32
    const val MAX_HEADER_LEN: Int = 256
    const val MAX_PAYLOAD: Int = 16 * 1024 * 1024
}

