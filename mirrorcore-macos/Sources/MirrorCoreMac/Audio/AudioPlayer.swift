import Foundation
import AudioToolbox
import CoreAudio

/// Low-latency PCM audio player using AudioQueue.
/// Receives PCM_S16LE data from the Android agent and plays it through the default output device.
class AudioPlayer {
    private var audioQueue: AudioQueueRef?
    private var buffers: [AudioQueueBufferRef?] = []
    private let bufferCount = 3
    private let bufferByteSize: UInt32 = 3840 * 2 // 960 samples * 2 channels * 2 bytes * 2 buffers worth

    private var ringBuffer = Data()
    private let ringLock = NSLock()
    private var isRunning = false

    private var sampleRate: Float64 = 48000
    private var channels: UInt32 = 2

    func configure(sampleRate: UInt32, channels: UInt8) {
        self.sampleRate = Float64(sampleRate)
        self.channels = UInt32(channels)
    }

    func start() {
        guard !isRunning else { return }

        var format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: channels * 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: channels * 2,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var queue: AudioQueueRef?
        let status = AudioQueueNewOutput(&format, audioQueueCallback, selfPtr, nil, nil, 0, &queue)
        guard status == noErr, let q = queue else {
            Log.error("Failed to create audio queue: \(status)")
            return
        }
        audioQueue = q

        // Allocate buffers
        for _ in 0..<bufferCount {
            var buffer: AudioQueueBufferRef?
            AudioQueueAllocateBuffer(q, bufferByteSize, &buffer)
            if let buf = buffer {
                buf.pointee.mAudioDataByteSize = 0
                fillBuffer(buf)
                buffers.append(buf)
            }
        }

        AudioQueueStart(q, nil)
        isRunning = true
        Log.info("Audio player started: rate=\(sampleRate) ch=\(channels)")
    }

    func stop() {
        guard isRunning, let queue = audioQueue else { return }
        isRunning = false
        AudioQueueStop(queue, true)
        AudioQueueDispose(queue, true)
        audioQueue = nil
        buffers.removeAll()
        ringLock.lock()
        ringBuffer.removeAll()
        ringLock.unlock()
    }

    /// Feed PCM_S16LE data into the ring buffer for playback.
    func feedPCM(_ data: Data) {
        ringLock.lock()
        // Cap ring buffer to avoid unbounded growth (~500ms of audio)
        let maxBytes = Int(sampleRate) * Int(channels) * 2 // ~1s
        if ringBuffer.count > maxBytes {
            ringBuffer.removeFirst(ringBuffer.count - maxBytes / 2)
        }
        ringBuffer.append(data)
        ringLock.unlock()
    }

    // MARK: - Private

    fileprivate func fillBuffer(_ buffer: AudioQueueBufferRef) {
        let capacity = Int(bufferByteSize)
        ringLock.lock()
        let available = min(capacity, ringBuffer.count)
        if available > 0 {
            let chunk = ringBuffer.prefix(available)
            chunk.withUnsafeBytes { rawBuf in
                memcpy(buffer.pointee.mAudioData, rawBuf.baseAddress, available)
            }
            ringBuffer.removeFirst(available)
            buffer.pointee.mAudioDataByteSize = UInt32(available)
        } else {
            // Fill with silence
            memset(buffer.pointee.mAudioData, 0, capacity)
            buffer.pointee.mAudioDataByteSize = UInt32(capacity)
        }
        ringLock.unlock()

        if let queue = audioQueue {
            AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
        }
    }
}

// MARK: - AudioQueue Callback

private func audioQueueCallback(
    inUserData: UnsafeMutableRawPointer?,
    inAQ: AudioQueueRef,
    inBuffer: AudioQueueBufferRef
) {
    guard let ptr = inUserData else { return }
    let player = Unmanaged<AudioPlayer>.fromOpaque(ptr).takeUnretainedValue()
    player.fillBuffer(inBuffer)
}
