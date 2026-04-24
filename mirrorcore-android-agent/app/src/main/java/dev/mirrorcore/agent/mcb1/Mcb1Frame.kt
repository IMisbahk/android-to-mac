package dev.mirrorcore.agent.mcb1

data class Mcb1Frame(
    val header: Mcb1Header,
    val headerExtra: ByteArray = ByteArray(0),
    val payload: ByteArray,
)

