import Foundation
import AudioToolbox

private func streamingPropertyListener(
    _ userData: UnsafeMutableRawPointer,
    _ stream: AudioFileStreamID,
    _ propertyID: AudioFileStreamPropertyID,
    _ flags: UnsafeMutablePointer<AudioFileStreamPropertyFlags>
) {
    let player = Unmanaged<StreamingAudioPlayer>.fromOpaque(userData).takeUnretainedValue()
    if propertyID == kAudioFileStreamProperty_DataFormat {
        player.setupQueue(for: stream)
    }
}

private func streamingPacketsCallback(
    _ userData: UnsafeMutableRawPointer,
    _ numberBytes: UInt32,
    _ numberPackets: UInt32,
    _ inputData: UnsafeRawPointer,
    _ packetDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
) {
    let player = Unmanaged<StreamingAudioPlayer>.fromOpaque(userData).takeUnretainedValue()
    player.enqueue(
        bytes: inputData,
        byteCount: numberBytes,
        packetCount: numberPackets,
        descriptions: packetDescriptions
    )
}

private func streamingQueueCallback(
    _ userData: UnsafeMutableRawPointer?,
    _ queue: AudioQueueRef,
    _ buffer: AudioQueueBufferRef
) {
    guard let userData else { return }
    let player = Unmanaged<StreamingAudioPlayer>.fromOpaque(userData).takeUnretainedValue()
    player.lock.lock()
    player.buffers.remove(UnsafeMutableRawPointer(buffer))
    let shouldFinish = player.finished && player.buffers.isEmpty
    player.lock.unlock()
    AudioQueueFreeBuffer(queue, buffer)
    if shouldFinish {
        player.finish()
    }
}

final class StreamingAudioPlayer {
    private var stream: AudioFileStreamID?
    private var queue: AudioQueueRef?
    private var buffers = Set<UnsafeMutableRawPointer>()
    private let lock = NSLock()
    private var finished = false
    private var started = false
    private var completion: (() -> Void)?

    func start(request: URLRequest, completion: @escaping () -> Void) async throws {
        stop()
        self.completion = completion

        var streamRef: AudioFileStreamID?
        let status = AudioFileStreamOpen(
            Unmanaged.passUnretained(self).toOpaque(),
            streamingPropertyListener,
            streamingPacketsCallback,
            kAudioFileMP3Type,
            &streamRef
        )
        guard status == noErr, let streamRef else {
            throw NSError(
                domain: "ElevenSpeak",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Could not open MP3 stream."]
            )
        }
        stream = streamRef

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw NSError(
                    domain: "ElevenSpeak",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "ElevenLabs returned an HTTP error."]
                )
            }

            var chunk = [UInt8]()
            chunk.reserveCapacity(32 * 1024)

            for try await byte in bytes {
                chunk.append(byte)
                if chunk.count >= 32 * 1024 {
                    parse(chunk)
                    chunk.removeAll(keepingCapacity: true)
                }
            }

            if !chunk.isEmpty {
                parse(chunk)
            }

            lock.lock()
            finished = true
            let shouldFinish = started && buffers.isEmpty
            lock.unlock()

            if shouldFinish {
                finish()
            }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        lock.lock()
        let queueRef = queue
        let streamRef = stream
        queue = nil
        stream = nil
        buffers.removeAll()
        finished = false
        started = false
        lock.unlock()

        if let queueRef {
            AudioQueueStop(queueRef, true)
            AudioQueueDispose(queueRef, true)
        }
        if let streamRef {
            AudioFileStreamClose(streamRef)
        }

        completion = nil
    }

    private func parse(_ bytes: [UInt8]) {
        guard let stream else { return }

        bytes.withUnsafeBytes { raw in
            guard let baseAddress = raw.baseAddress else { return }
            _ = AudioFileStreamParseBytes(
                stream,
                UInt32(bytes.count),
                baseAddress,
                []
            )
        }
    }

    private func setupQueue(for stream: AudioFileStreamID) {
        lock.lock()
        if queue != nil {
            lock.unlock()
            return
        }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioFileStreamGetProperty(
            stream,
            kAudioFileStreamProperty_DataFormat,
            &size,
            &format
        )

        guard status == noErr else {
            lock.unlock()
            return
        }

        var newQueue: AudioQueueRef?
        let queueStatus = AudioQueueNewOutput(
            &format,
            streamingQueueCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            nil,
            0,
            &newQueue
        )

        guard queueStatus == noErr, let newQueue else {
            lock.unlock()
            return
        }

        queue = newQueue
        lock.unlock()
    }

    private func enqueue(
        bytes: UnsafeRawPointer,
        byteCount: UInt32,
        packetCount: UInt32,
        descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
    ) {
        guard let queue else { return }

        var buffer: AudioQueueBufferRef?
        let allocationStatus: OSStatus

        if descriptions != nil {
            allocationStatus = AudioQueueAllocateBufferWithPacketDescriptions(
                queue,
                byteCount,
                packetCount,
                &buffer
            )
        } else {
            allocationStatus = AudioQueueAllocateBuffer(queue, byteCount, &buffer)
        }

        guard allocationStatus == noErr, let buffer else { return }

        buffer.pointee.mAudioDataByteSize = byteCount
        memcpy(buffer.pointee.mAudioData, bytes, Int(byteCount))

        if let descriptions,
           let destination = buffer.pointee.mPacketDescriptions {
            buffer.pointee.mPacketDescriptionCount = packetCount
            destination.update(from: descriptions, count: Int(packetCount))
        }

        lock.lock()
        buffers.insert(UnsafeMutableRawPointer(buffer))
        let shouldStart = !started
        started = true
        lock.unlock()

        let count = descriptions == nil ? 0 : packetCount
        let descriptionPointer = descriptions == nil
            ? nil
            : buffer.pointee.mPacketDescriptions

        let enqueueStatus = AudioQueueEnqueueBuffer(
            queue,
            buffer,
            count,
            descriptionPointer
        )

        guard enqueueStatus == noErr else {
            lock.lock()
            buffers.remove(UnsafeMutableRawPointer(buffer))
            lock.unlock()
            AudioQueueFreeBuffer(queue, buffer)
            return
        }

        if shouldStart {
            _ = AudioQueueStart(queue, nil)
        }
    }

    private func finish() {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()
        callback?()
    }

    private static func propertyListener(
        _ userData: UnsafeMutableRawPointer?,
        _ stream: AudioFileStreamID,
        _ propertyID: AudioFileStreamPropertyID,
        _ flags: UnsafeMutablePointer<UInt32>
    ) {
        guard let userData else { return }
        let player = Unmanaged<StreamingAudioPlayer>
            .fromOpaque(userData)
            .takeUnretainedValue()

        if propertyID == kAudioFileStreamProperty_DataFormat {
            player.setupQueue(for: stream)
        }
    }

    private static func packetsCallback(
        _ userData: UnsafeMutableRawPointer?,
        _ numberBytes: UInt32,
        _ numberPackets: UInt32,
        _ inputData: UnsafeRawPointer,
        _ packetDescriptions: UnsafePointer<AudioStreamPacketDescription>?
    ) {
        guard let userData else { return }
        let player = Unmanaged<StreamingAudioPlayer>
            .fromOpaque(userData)
            .takeUnretainedValue()

        player.enqueue(
            bytes: inputData,
            byteCount: numberBytes,
            packetCount: numberPackets,
            descriptions: packetDescriptions
        )
    }

    private static func queueCallback(
        _ userData: UnsafeMutableRawPointer?,
        _ queue: AudioQueueRef,
        _ buffer: AudioQueueBufferRef
    ) {
        guard let userData else { return }
        let player = Unmanaged<StreamingAudioPlayer>
            .fromOpaque(userData)
            .takeUnretainedValue()

        player.lock.lock()
        player.buffers.remove(UnsafeMutableRawPointer(buffer))
        let shouldFinish = player.finished && player.buffers.isEmpty
        player.lock.unlock()

        AudioQueueFreeBuffer(queue, buffer)

        if shouldFinish {
            player.finish()
        }
    }
}
