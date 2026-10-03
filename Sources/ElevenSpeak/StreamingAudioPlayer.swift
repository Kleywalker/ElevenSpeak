import Foundation
import AudioToolbox
import os

private let streamingPropertyListener: AudioFileStream_PropertyListenerProc = {
    userData, stream, propertyID, _ in
    let player = Unmanaged<StreamingAudioPlayer>.fromOpaque(userData).takeUnretainedValue()
    if propertyID == kAudioFileStreamProperty_DataFormat {
        player.setupQueue(for: stream)
    }
}

private let streamingPacketsCallback: AudioFileStream_PacketsProc = {
    userData, numberBytes, numberPackets, inputData, packetDescriptions in
    let player = Unmanaged<StreamingAudioPlayer>.fromOpaque(userData).takeUnretainedValue()
    player.enqueue(
        bytes: inputData,
        byteCount: numberBytes,
        packetCount: numberPackets,
        descriptions: packetDescriptions
    )
}

private let streamingQueueCallback: AudioQueueOutputCallback = {
    userData, queue, buffer in
    guard let userData else { return }
    let player = Unmanaged<StreamingAudioPlayer>.fromOpaque(userData).takeUnretainedValue()

    let shouldFinish = player.lock.withLock {
        player.buffers.remove(UnsafeMutableRawPointer(buffer))
        return player.finished && player.buffers.isEmpty
    }

    AudioQueueFreeBuffer(queue, buffer)

    if shouldFinish {
        player.finish()
    }
}

final class StreamingAudioPlayer {
    private var stream: AudioFileStreamID?
    private var queue: AudioQueueRef?
    fileprivate var buffers = Set<UnsafeMutableRawPointer>()
    fileprivate let lock = OSAllocatedUnfairLock()
    fileprivate var finished = false
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

            let shouldFinish = lock.withLock {
                finished = true
                return started && buffers.isEmpty
            }

            if shouldFinish {
                finish()
            }
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        let resources = lock.withLock {
            let resources = (queue, stream)
            queue = nil
            stream = nil
            buffers.removeAll()
            finished = false
            started = false
            return resources
        }

        if let queueRef = resources.0 {
            AudioQueueStop(queueRef, true)
            AudioQueueDispose(queueRef, true)
        }

        if let streamRef = resources.1 {
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

    fileprivate func setupQueue(for stream: AudioFileStreamID) {
        lock.withLock {
            if queue != nil {
                return
            }

            var format = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

            guard AudioFileStreamGetProperty(
                stream,
                kAudioFileStreamProperty_DataFormat,
                &size,
                &format
            ) == noErr else {
                return
            }

            var newQueue: AudioQueueRef?
            guard AudioQueueNewOutput(
                &format,
                streamingQueueCallback,
                Unmanaged.passUnretained(self).toOpaque(),
                nil,
                nil,
                0,
                &newQueue
            ) == noErr else {
                return
            }

            queue = newQueue
        }
    }

    fileprivate func enqueue(
        bytes: UnsafeRawPointer,
        byteCount: UInt32,
        packetCount: UInt32,
        descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?
    ) {
        guard let queue else { return }

        var buffer: AudioQueueBufferRef?
        let status: OSStatus

        if descriptions != nil {
            status = AudioQueueAllocateBufferWithPacketDescriptions(
                queue,
                byteCount,
                packetCount,
                &buffer
            )
        } else {
            status = AudioQueueAllocateBuffer(queue, byteCount, &buffer)
        }

        guard status == noErr, let buffer else { return }

        buffer.pointee.mAudioDataByteSize = byteCount
        memcpy(buffer.pointee.mAudioData, bytes, Int(byteCount))

        if let descriptions,
           let destination = buffer.pointee.mPacketDescriptions {
            buffer.pointee.mPacketDescriptionCount = packetCount
            destination.update(from: descriptions, count: Int(packetCount))
        }

        let shouldStart = lock.withLock {
            buffers.insert(UnsafeMutableRawPointer(buffer))
            let shouldStart = !started
            started = true
            return shouldStart
        }

        let count = descriptions == nil ? 0 : packetCount
        let descriptionPointer = descriptions == nil
            ? nil
            : buffer.pointee.mPacketDescriptions

        guard AudioQueueEnqueueBuffer(
            queue,
            buffer,
            count,
            descriptionPointer
        ) == noErr else {
            lock.withLock {
                buffers.remove(UnsafeMutableRawPointer(buffer))
            }
            AudioQueueFreeBuffer(queue, buffer)
            return
        }

        if shouldStart {
            _ = AudioQueueStart(queue, nil)
        }
    }

    fileprivate func finish() {
        let callback = lock.withLock {
            let callback = completion
            completion = nil
            return callback
        }
        callback?()
    }
}
