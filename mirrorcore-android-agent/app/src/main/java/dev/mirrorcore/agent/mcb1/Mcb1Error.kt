package dev.mirrorcore.agent.mcb1

sealed class Mcb1Error(message: String) : Exception(message) {
    class InvalidMagic : Mcb1Error("invalid magic")
    class UnsupportedVersion(val version: Int) : Mcb1Error("unsupported version: $version")
    class InvalidHeaderLen(val headerLen: Int) : Mcb1Error("invalid header length: $headerLen")
    class InvalidReserved(val reserved: Int) : Mcb1Error("invalid reserved field: $reserved")
    class PayloadTooLarge(val payloadLen: Long) : Mcb1Error("payload too large: $payloadLen")
    class PayloadLenMismatch(val expected: Long, val actual: Long) :
        Mcb1Error("payload length mismatch: expected=$expected actual=$actual")

    class CrcMismatch(val expected: Long, val actual: Long) :
        Mcb1Error("crc mismatch: expected=${expected.toString(16)} actual=${actual.toString(16)}")
}

