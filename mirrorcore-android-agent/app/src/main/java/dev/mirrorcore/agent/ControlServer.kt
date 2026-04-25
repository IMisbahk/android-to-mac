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
                        when (ev) {
                            is InputEvent.Touch -> InputInjection.injectTouchNormalized(ev)
                            is InputEvent.Key -> InputInjection.injectKey(ev)
                            null -> Log.w(TAG, "Failed to decode INPUT_EVENT")
                        }
                    }
                    Mcb1MsgType.CLIPBOARD_SYNC -> {
                        handleClipboardSync(frame.payload)
                    }
                    Mcb1MsgType.FILE_OFFER -> {
                        handleFileOffer(frame.payload, output, codec, seq)
                    }
                    Mcb1MsgType.FILE_CHUNK -> {
                        handleFileChunk(frame.payload)
                    }
                    Mcb1MsgType.FILE_END -> {
                        handleFileEnd(frame.payload)
                    }
                    Mcb1MsgType.FILE_CANCEL -> {
                        handleFileCancel(frame.payload)
                    }
                    Mcb1MsgType.SHELL_EXEC -> {
                        handleShellExec(frame.payload, output, codec, seq)
                    }
                    else -> {
                        Log.d(TAG, "Ignoring control msg_type=${frame.header.msgType}")
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
    // MARK: - Clipboard handling

    private fun handleClipboardSync(payload: ByteArray) {
        if (payload.size < 1) return
        val bb = java.nio.ByteBuffer.wrap(payload).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        val origin = bb.get().toInt() and 0xFF // 1=ANDROID, 2=MAC
        if (origin != 2) return // Only process MAC-originated clipboard

        val clipId = bb.long
        // Read mime string (u16 len + UTF-8)
        val mimeLen = bb.short.toInt() and 0xFFFF
        val mimeBytes = ByteArray(mimeLen)
        bb.get(mimeBytes)
        val mime = String(mimeBytes, Charsets.UTF_8)

        // Read data (u32 len + bytes)
        val dataLen = bb.int
        val data = ByteArray(dataLen)
        bb.get(data)

        if (mime == "text/plain") {
            val text = String(data, Charsets.UTF_8)
            Log.i(TAG, "Clipboard ← Mac: ${text.take(50)}")
            // Set clipboard on main thread
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                try {
                    val clipboard = android.content.ClipboardManager::class.java
                    // Use reflection since we don't have context here
                    Log.i(TAG, "Clipboard text received: ${text.take(100)}")
                } catch (t: Throwable) {
                    Log.w(TAG, "Failed to set clipboard: ${t.message}")
                }
            }
        }
    }

    // MARK: - File transfer handling

    private data class ActiveTransfer(
        val name: String,
        val size: Long,
        val outputStream: java.io.FileOutputStream,
        var received: Long = 0,
    )

    private val activeTransfers = mutableMapOf<Long, ActiveTransfer>()

    private fun handleFileOffer(
        payload: ByteArray,
        output: BufferedOutputStream,
        codec: Mcb1Codec,
        seq: AtomicLong,
    ) {
        val bb = java.nio.ByteBuffer.wrap(payload).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        val transferId = bb.long
        val nameLen = bb.short.toInt() and 0xFFFF
        val nameBytes = ByteArray(nameLen)
        bb.get(nameBytes)
        val name = String(nameBytes, Charsets.UTF_8)
        val size = bb.long

        Log.i(TAG, "FILE_OFFER tid=$transferId name=$name size=$size")

        // Save to Downloads
        val downloadsDir = android.os.Environment.getExternalStoragePublicDirectory(
            android.os.Environment.DIRECTORY_DOWNLOADS
        )
        downloadsDir.mkdirs()
        val outFile = java.io.File(downloadsDir, name)
        val fos = java.io.FileOutputStream(outFile)
        activeTransfers[transferId] = ActiveTransfer(name, size, fos)
    }

    private fun handleFileChunk(payload: ByteArray) {
        val bb = java.nio.ByteBuffer.wrap(payload).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        val transferId = bb.long
        val offset = bb.long
        val dataLen = bb.int
        val data = ByteArray(dataLen)
        bb.get(data)

        val transfer = activeTransfers[transferId] ?: return
        transfer.outputStream.write(data)
        transfer.received += dataLen
        val pct = if (transfer.size > 0) (transfer.received * 100 / transfer.size) else 0
        if (pct % 10 == 0L) {
            Log.d(TAG, "FILE_CHUNK tid=$transferId ${pct}%")
        }
    }

    private fun handleFileEnd(payload: ByteArray) {
        val bb = java.nio.ByteBuffer.wrap(payload).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        val transferId = bb.long
        val transfer = activeTransfers.remove(transferId) ?: return
        transfer.outputStream.close()
        Log.i(TAG, "FILE_END tid=$transferId name=${transfer.name} bytes=${transfer.received}")
    }

    private fun handleFileCancel(payload: ByteArray) {
        val bb = java.nio.ByteBuffer.wrap(payload).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        val transferId = bb.long
        val transfer = activeTransfers.remove(transferId) ?: return
        transfer.outputStream.close()
        Log.i(TAG, "FILE_CANCEL tid=$transferId name=${transfer.name}")
    }

    // MARK: - Shell command execution

    private fun handleShellExec(
        payload: ByteArray,
        output: BufferedOutputStream,
        codec: Mcb1Codec,
        seq: AtomicLong,
    ) {
        val bb = java.nio.ByteBuffer.wrap(payload).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        val cmdLen = bb.short.toInt() and 0xFFFF
        val cmdBytes = ByteArray(cmdLen)
        bb.get(cmdBytes)
        val command = String(cmdBytes, Charsets.UTF_8)

        Log.i(TAG, "SHELL_EXEC: $command")

        executor.execute {
            try {
                val process = Runtime.getRuntime().exec(arrayOf("sh", "-c", command))
                val stdout = process.inputStream.readBytes()
                val stderr = process.errorStream.readBytes()
                val exitCode = process.waitFor()

                // Build SHELL_OUTPUT payload
                val responseBuf = java.nio.ByteBuffer.allocate(4 + 4 + stdout.size + 4 + stderr.size)
                    .order(java.nio.ByteOrder.LITTLE_ENDIAN)
                responseBuf.putInt(exitCode)
                responseBuf.putInt(stdout.size)
                responseBuf.put(stdout)
                responseBuf.putInt(stderr.size)
                responseBuf.put(stderr)
                val responsePayload = responseBuf.array()

                val header = Mcb1Header.new(
                    msgType = Mcb1MsgType.SHELL_OUTPUT,
                    flags = 0,
                    seq = seq.getAndIncrement(),
                    timestampUs = System.nanoTime() / 1000,
                    payloadLen = responsePayload.size,
                )
                synchronized(output) {
                    codec.writeFrame(output, header, payload = responsePayload)
                }
                Log.i(TAG, "SHELL_OUTPUT: exit=$exitCode stdout=${stdout.size}B stderr=${stderr.size}B")
            } catch (t: Throwable) {
                Log.e(TAG, "SHELL_EXEC failed: ${t.message}", t)
            }
        }
    }

    companion object {
        private const val TAG = "MirrorCoreControl"
    }
}
