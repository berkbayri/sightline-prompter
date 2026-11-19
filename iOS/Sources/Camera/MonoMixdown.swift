import AVFoundation

/// Rewrites a recording with its sound folded into one channel: every channel is averaged into the mono track.
/// The video is copied as it is (no re-encode), so the picture is untouched. The caller deletes the original once the result is safe. Returns the original when the
/// sound is already one channel or there is no sound.
enum MonoMixdown {
    enum MixError: Error { case failed(String) }

    static func mixed(_ url: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
              let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { return url }
        let audioFormat = try await audioTrack.load(.formatDescriptions).first
        let videoFormat = try await videoTrack.load(.formatDescriptions).first
        let channels = audioFormat.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame } ?? 1
        guard channels > 1 else { return url }
        let transform = try await videoTrack.load(.preferredTransform)
        let total = max(try await asset.load(.duration).seconds, 0.001)

        let reader = try AVAssetReader(asset: asset)
        let videoOut = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        let audioOut = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channels,
        ])
        reader.add(videoOut)
        reader.add(audioOut)

        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Sightline-mono-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        videoIn.transform = transform
        videoIn.expectsMediaDataInRealTime = false
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
        let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 48_000,
            AVEncoderBitRateKey: 128_000,
            AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
        ])
        audioIn.expectsMediaDataInRealTime = false
        writer.add(videoIn)
        writer.add(audioIn)
        guard reader.startReading(), writer.startWriting() else {
            throw MixError.failed((reader.error ?? writer.error)?.localizedDescription ?? "start")
        }
        writer.startSession(atSourceTime: .zero)

        let group = DispatchGroup()
        pump(videoOut, into: videoIn, group: group, label: "video") { sample in
            progress(min(CMSampleBufferGetPresentationTimeStamp(sample).seconds / total, 1))
            return sample
        }
        pump(audioOut, into: audioIn, group: group, label: "audio") { foldToMono($0, channels: Int(channels)) }
        await withCheckedContinuation { continuation in group.notify(queue: .global()) { continuation.resume() } }

        if reader.status == .failed { writer.cancelWriting(); throw MixError.failed(reader.error?.localizedDescription ?? "read") }
        await writer.finishWriting()
        guard writer.status == .completed else { throw MixError.failed(writer.error?.localizedDescription ?? "write") }
        return output
    }

    private static func pump(_ source: AVAssetReaderOutput, into input: AVAssetWriterInput, group: DispatchGroup,
                             label: String, transform: @escaping (CMSampleBuffer) -> CMSampleBuffer?) {
        group.enter()
        let queue = DispatchQueue(label: "mono.\(label)")
        nonisolated(unsafe) let source = source
        nonisolated(unsafe) let input = input
        input.requestMediaDataWhenReady(on: queue) {
            while input.isReadyForMoreMediaData {
                guard let sample = source.copyNextSampleBuffer() else {
                    input.markAsFinished(); group.leave(); return
                }
                guard let out = transform(sample), input.append(out) else {
                    input.markAsFinished(); group.leave(); return
                }
            }
        }
    }

    /// Averages the interleaved Float32 channels of a PCM sample buffer into a one-channel buffer.
    private static func foldToMono(_ sample: CMSampleBuffer, channels: Int) -> CMSampleBuffer? {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        let frames = CMSampleBufferGetNumSamples(sample)
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
              let pointer, frames > 0 else { return nil }
        let samples = UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self)
        var mono = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels { sum += samples[frame * channels + channel] }
            mono[frame] = sum / Float(channels)
        }

        var description = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
                                             magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                             formatDescriptionOut: &format) == noErr, let format else { return nil }

        let byteCount = frames * 4
        var newBlock: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: byteCount, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: byteCount,
                                                 flags: 0, blockBufferOut: &newBlock) == noErr, let newBlock,
              CMBlockBufferReplaceDataBytes(with: mono, blockBuffer: newBlock, offsetIntoDestination: 0, dataLength: byteCount) == noErr
        else { return nil }

        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
                                        presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample),
                                        decodeTimeStamp: .invalid)
        var out: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: newBlock, formatDescription: format, sampleCount: frames,
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1, sampleSizeArray: [4], sampleBufferOut: &out) == noErr else { return nil }
        return out
    }
}
