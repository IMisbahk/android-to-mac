import Foundation

/// Handles file transfer to the Android device via MCB1 FILE_* messages.
/// Supports drag-and-drop from the Mac mirror window.
class FileTransferManager {
    private let chunkSize = 256 * 1024 // 256 KiB per protocol spec
    private var transferIdCounter: UInt64 = 1
    private var activeTransfers: [UInt64: FileTransfer] = [:]

    var sendOffer: ((FileOfferPayload) -> Void)?
    var sendChunk: ((FileChunkPayload) -> Void)?
    var sendEnd: ((FileEndPayload) -> Void)?

    var onProgress: ((UInt64, Double) -> Void)? // (transferId, progress 0..1)

    struct FileTransfer {
        let id: UInt64
        let url: URL
        let name: String
        let size: UInt64
        var offset: UInt64 = 0
    }

    /// Initiate a file transfer for the given URL.
    func sendFile(url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else {
            Log.error("Cannot read file: \(url.path)")
            return
        }

        let tid = transferIdCounter
        transferIdCounter += 1

        let transfer = FileTransfer(id: tid, url: url, name: url.lastPathComponent, size: size)
        activeTransfers[tid] = transfer

        Log.info("File offer: \(transfer.name) (\(size) bytes) tid=\(tid)")
        sendOffer?(FileOfferPayload(transferId: tid, name: transfer.name, size: size))

        // Start sending chunks on a background queue
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.sendChunks(transferId: tid)
        }
    }

    /// Send files from URLs (for drag-and-drop).
    func sendFiles(urls: [URL]) {
        for url in urls {
            sendFile(url: url)
        }
    }

    // MARK: - Private

    private func sendChunks(transferId: UInt64) {
        guard var transfer = activeTransfers[transferId] else { return }

        guard let handle = try? FileHandle(forReadingFrom: transfer.url) else {
            Log.error("Cannot open file: \(transfer.url.path)")
            activeTransfers.removeValue(forKey: transferId)
            return
        }

        defer { handle.closeFile() }

        while transfer.offset < transfer.size {
            let remaining = Int(transfer.size - transfer.offset)
            let readSize = min(chunkSize, remaining)

            guard let data = try? handle.read(upToCount: readSize), !data.isEmpty else { break }

            sendChunk?(FileChunkPayload(
                transferId: transferId,
                offset: transfer.offset,
                data: data
            ))

            transfer.offset += UInt64(data.count)
            activeTransfers[transferId] = transfer

            let progress = Double(transfer.offset) / Double(transfer.size)
            DispatchQueue.main.async { [weak self] in
                self?.onProgress?(transferId, progress)
            }

            // Small delay to avoid overwhelming the connection
            Thread.sleep(forTimeInterval: 0.001)
        }

        sendEnd?(FileEndPayload(transferId: transferId))
        activeTransfers.removeValue(forKey: transferId)
        Log.info("File transfer complete: \(transfer.name)")
    }
}
