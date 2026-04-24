package dev.mirrorcore.agent

import android.os.Build
import android.util.Log
import dev.mirrorcore.agent.input.InputEventCodec
import dev.mirrorcore.agent.input.InputEvent
import dev.mirrorcore.agent.input.InputInjection
import dev.mirrorcore.agent.mcb1.Mcb1Codec
import dev.mirrorcore.agent.mcb1.Mcb1Header
import dev.mirrorcore.agent.mcb1.Mcb1MsgType
import dev.mirrorcore.agent.mcb1.Mcb1Payloads
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class ControlServer {
    private val running = AtomicBoolean(false)
    private val executor = Executors.newCachedThreadPool()
    private var serverSocket: ServerSocket? = null

    fun start() {
        if (!running.compareAndSet(false, true)) return
        val addr = InetAddress.getByName(Ports.BIND_HOST)
        val ss = ServerSocket(Ports.CONTROL_PORT, 1, addr)
        serverSocket = ss
        executor.execute {
            Log.i(TAG, "Control server listening on ${Ports.BIND_HOST}:${Ports.CONTROL_PORT}")
            while (running.get()) {
                val sock = try {
                    ss.accept()
                } catch (_: Throwable) {
                    break
                }
                executor.execute { handle(sock) }
            }
        }
    }

    fun stop() {
        running.set(false)
        try {
            serverSocket?.close()
        } catch (_: Throwable) {
        }
        executor.shutdownNow()
    }

    private fun handle(sock: Socket) {
        sock.tcpNoDelay = true
        val codec = Mcb1Codec()
        val seq = AtomicLong(1)
        val input = BufferedInputStream(sock.getInputStream())
        val output = BufferedOutputStream(sock.getOutputStream())

        Log.i(TAG, "Control client connected from ${sock.inetAddress}")
        try {
            while (running.get() && !sock.isClosed) {
                val frame = codec.readFrame(input)
                when (frame.header.msgType) {
                    Mcb1MsgType.PING -> {
                        // Payload is echo_timestamp_us:u64, but we can just echo raw payload.
                        val header = Mcb1Header.new(
                            msgType = Mcb1MsgType.PONG,
                            flags = 0,
                            seq = seq.getAndIncrement(),
                            timestampUs = System.nanoTime() / 1000,
                            payloadLen = frame.payload.size,
                        )
                        codec.writeFrame(output, header, payload = frame.payload)
                    }
                    Mcb1MsgType.HELLO -> {
                        val hello = Mcb1Payloads.Hello(
                            role = 1, // ANDROID
                            caps = 0x0000_0001L, // VIDEO (Phase 2)
                            deviceName = Build.MODEL ?: "Android",
                            sessionNonce = (System.nanoTime() ushr 1),
                        )
                        val payload = Mcb1Payloads.encodeHello(hello)
                        val header = Mcb1Header.new(
                            msgType = Mcb1MsgType.HELLO,
                            flags = 0,
                            seq = seq.getAndIncrement(),
                            timestampUs = System.nanoTime() / 1000,
                            payloadLen = payload.size,
                        )
                        codec.writeFrame(output, header, payload = payload)
                    }
                    Mcb1MsgType.INPUT_EVENT -> {
                        val ev = InputEventCodec.decode(frame.payload)
                        if (ev is InputEvent.Touch) {
                            InputInjection.injectTouchNormalized(ev)
                        }
                    }
                    else -> {
                        // Unknown control messages are ignored in Phase 2.
                    }
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Control session ended: ${t.message}")
        } finally {
            try {
                sock.close()
            } catch (_: Throwable) {
            }
            Log.i(TAG, "Control client disconnected")
        }
    }

    companion object {
        private const val TAG = "MirrorCoreControl"
    }
}
