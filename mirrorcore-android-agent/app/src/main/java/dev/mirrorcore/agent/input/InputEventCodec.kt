package dev.mirrorcore.agent.input

import java.nio.ByteBuffer
import java.nio.ByteOrder

sealed class InputEvent {
    data class Touch(
        val action: TouchAction,
        val pointerId: Int,
        val xNorm: Float,
        val yNorm: Float,
        val pressure: Float,
        val buttons: Int,
    ) : InputEvent()

    data class Key(
        val action: KeyAction,
        val androidKeycode: Long,
        val metaState: Long,
    ) : InputEvent()
}

enum class TouchAction(val code: Int) {
    Down(0),
    Move(1),
    Up(2),
    Cancel(3),
    ;

    companion object {
        fun fromCode(code: Int): TouchAction? = entries.firstOrNull { it.code == code }
    }
}

enum class KeyAction(val code: Int) {
    Down(0),
    Up(1),
    ;

    companion object {
        fun fromCode(code: Int): KeyAction? = entries.firstOrNull { it.code == code }
    }
}

object InputEventCodec {
    fun decode(payload: ByteArray): InputEvent? {
        if (payload.isEmpty()) return null
        val bb = ByteBuffer.wrap(payload).order(ByteOrder.LITTLE_ENDIAN)
        val kind = bb.getU8()
        return when (kind) {
            1 -> decodeTouch(bb)
            2 -> decodeKey(bb)
            else -> null
        }
    }

    private fun decodeTouch(bb: ByteBuffer): InputEvent.Touch? {
        if (bb.remaining() < (1 + 1 + 4 + 4 + 4 + 2 + 2)) return null
        val action = TouchAction.fromCode(bb.getU8()) ?: return null
        val pointerId = bb.getU8()
        val x = bb.float
        val y = bb.float
        val pressure = bb.float
        val buttons = bb.short.toInt() and 0xFFFF
        bb.short // reserved
        return InputEvent.Touch(action, pointerId, x, y, pressure, buttons)
    }

    private fun decodeKey(bb: ByteBuffer): InputEvent.Key? {
        if (bb.remaining() < (1 + 4 + 4)) return null
        val action = KeyAction.fromCode(bb.getU8()) ?: return null
        val keycode = bb.int.toLong() and 0xFFFF_FFFFL
        val meta = bb.int.toLong() and 0xFFFF_FFFFL
        return InputEvent.Key(action, keycode, meta)
    }

    private fun ByteBuffer.getU8(): Int = (get().toInt() and 0xFF)
}

