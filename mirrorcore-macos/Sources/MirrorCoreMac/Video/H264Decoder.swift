import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// Hardware-accelerated H.264 decoder using VideoToolbox.
/// Receives SPS/PPS from VIDEO_CONFIG and NAL units from VIDEO_FRAME.
class H264Decoder {
    private var formatDescription: CMVideoFormatDescription?
    private var decompressionSession: VTDecompressionSession?
    private var sps: Data?
    private var pps: Data?

    var onDecodedFrame: ((CVPixelBuffer, CMTime) -> Void)?

    /// Configure the decoder with SPS and PPS from VIDEO_CONFIG.
    func configure(sps: Data, pps: Data, width: Int, height: Int) {
        self.sps = sps
        self.pps = pps

        // Destroy existing session
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        formatDescription = nil

        // Create format description from SPS/PPS
        let spsBytes = [UInt8](sps)
        let ppsBytes = [UInt8](pps)

        let parameterSets: [[UInt8]] = [spsBytes, ppsBytes]
        let parameterSetPointers = parameterSets.map { UnsafePointer($0) }
        let parameterSetSizes = parameterSets.map { $0.count }

        var fmtDesc: CMFormatDescription?
        let status = parameterSetPointers.withUnsafeBufferPointer { ptrs in
            parameterSetSizes.withUnsafeBufferPointer { sizes in
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: ptrs.baseAddress!,
                    parameterSetSizes: sizes.baseAddress!,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &fmtDesc
                )
            }
        }

        guard status == noErr, let desc = fmtDesc else {
            Log.error("Failed to create H264 format description: \(status)")
            return
        }
        formatDescription = desc

        // Create decompression session
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]

        var session: VTDecompressionSession?
        let callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        var callbackCopy = callback
        let createStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: desc,
            decoderSpecification: nil,
            imageBufferAttributes: attrs as CFDictionary,
            outputCallback: &callbackCopy,
            decompressionSessionOut: &session
        )

        guard createStatus == noErr, let sess = session else {
            Log.error("Failed to create VT session: \(createStatus)")
            return
        }

        // Request real-time decoding
        VTSessionSetProperty(sess, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)

        decompressionSession = sess
        Log.info("H264 decoder configured: \(width)x\(height)")
    }

    /// Decode an AnnexB H.264 access unit (may contain start codes).
    func decode(annexBData: Data, pts: UInt64) {
        guard let session = decompressionSession, let fmtDesc = formatDescription else { return }

        // Convert AnnexB → AVCC (replace start codes with length prefixes)
        let avcc = annexBToAVCC(annexBData)
        guard !avcc.isEmpty else { return }

        avcc.withUnsafeBytes { rawBuf in
            guard let ptr = rawBuf.baseAddress else { return }

            var blockBuffer: CMBlockBuffer?
            let bbStatus = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: UnsafeMutableRawPointer(mutating: ptr),
                blockLength: avcc.count,
                blockAllocator: kCFAllocatorNull,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: avcc.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )

            guard bbStatus == kCMBlockBufferNoErr, let bb = blockBuffer else { return }

            var sampleBuffer: CMSampleBuffer?
            let sbStatus = CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault,
                dataBuffer: bb,
                formatDescription: fmtDesc,
                sampleCount: 1,
                sampleTimingEntryCount: 0,
                sampleTimingArray: nil,
                sampleSizeEntryCount: 0,
                sampleSizeArray: nil,
                sampleBufferOut: &sampleBuffer
            )

            guard sbStatus == noErr, let sb = sampleBuffer else { return }

            let decodeFlags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression, ._EnableTemporalProcessing]
            var flagsOut: VTDecodeInfoFlags = []
            VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: sb,
                flags: decodeFlags,
                frameRefcon: nil,
                infoFlagsOut: &flagsOut
            )
        }
    }

    func flush() {
        guard let session = decompressionSession else { return }
        VTDecompressionSessionFinishDelayedFrames(session)
        VTDecompressionSessionWaitForAsynchronousFrames(session)
    }

    func stop() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        formatDescription = nil
    }

    // MARK: - AnnexB → AVCC

    /// Convert AnnexB format (start codes) to AVCC format (4-byte length prefixes).
    private func annexBToAVCC(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        var nals: [Data] = []
        var i = 0
        let count = bytes.count

        while i < count {
            // Find start code (0x00 0x00 0x01 or 0x00 0x00 0x00 0x01)
            var scLen = 0
            if i + 3 < count && bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 0 && bytes[i+3] == 1 {
                scLen = 4
            } else if i + 2 < count && bytes[i] == 0 && bytes[i+1] == 0 && bytes[i+2] == 1 {
                scLen = 3
            }

            if scLen > 0 {
                let nalStart = i + scLen
                // Find next start code
                var nalEnd = count
                var j = nalStart
                while j < count - 2 {
                    if bytes[j] == 0 && bytes[j+1] == 0 {
                        if j + 2 < count && bytes[j+2] == 1 {
                            nalEnd = j
                            break
                        }
                        if j + 3 < count && bytes[j+2] == 0 && bytes[j+3] == 1 {
                            nalEnd = j
                            break
                        }
                    }
                    j += 1
                }
                let nalData = Data(bytes[nalStart..<nalEnd])
                if !nalData.isEmpty {
                    // Skip SPS/PPS NALs — they're in the format description
                    let nalType = nalData[nalData.startIndex] & 0x1F
                    if nalType != 7 && nalType != 8 { // Not SPS/PPS
                        nals.append(nalData)
                    }
                }
                i = nalEnd
            } else {
                i += 1
            }
        }

        // If no start codes found, treat entire data as single NAL
        if nals.isEmpty && !data.isEmpty {
            nals.append(data)
        }

        // Build AVCC: each NAL prefixed with 4-byte big-endian length
        var avcc = Data()
        for nal in nals {
            var len = UInt32(nal.count).bigEndian
            avcc.append(Data(bytes: &len, count: 4))
            avcc.append(nal)
        }
        return avcc
    }
}

// MARK: - VT Callback

private func decompressCallback(
    decompressionOutputRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTDecodeInfoFlags,
    imageBuffer: CVImageBuffer?,
    presentationTimeStamp: CMTime,
    presentationDuration: CMTime
) {
    guard status == noErr, let pixelBuffer = imageBuffer else { return }
    guard let refCon = decompressionOutputRefCon else { return }
    let decoder = Unmanaged<H264Decoder>.fromOpaque(refCon).takeUnretainedValue()
    decoder.onDecodedFrame?(pixelBuffer as CVPixelBuffer, presentationTimeStamp)
}
