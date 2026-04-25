package dev.mirrorcore.agent.mcb1

object Mcb1MsgType {
    const val HELLO: Int = 0x01
    const val PING: Int = 0x02
    const val PONG: Int = 0x03

    const val VIDEO_CONFIG: Int = 0x10
    const val VIDEO_FRAME: Int = 0x11
    const val AUDIO_CONFIG: Int = 0x12
    const val AUDIO_FRAME: Int = 0x13

    const val INPUT_EVENT: Int = 0x20
    const val CLIPBOARD_SYNC: Int = 0x30

    const val FILE_OFFER: Int = 0x40
    const val FILE_CHUNK: Int = 0x41
    const val FILE_END: Int = 0x42
    const val FILE_CANCEL: Int = 0x43

    const val SHELL_EXEC: Int = 0x50
    const val SHELL_OUTPUT: Int = 0x51
}
