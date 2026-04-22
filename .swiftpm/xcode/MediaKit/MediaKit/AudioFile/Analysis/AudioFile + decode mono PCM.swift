import AVFoundation


extension AudioFile {

    /// Decoded mono PCM payload used as analysis input.
    struct DecodedPCM {

        /// Mono samples in linear PCM float format.
        let samples: [Float]

        /// Sample rate of `samples`, in Hz.
        let sampleRate: Double
    }

}


extension AudioFile {

    /// Decodes the first audio track to mono floating-point PCM.
    ///
    /// Multi-channel input is downmixed by averaging channels per frame.
    ///
    /// - Returns: Decoded mono PCM, or `nil` if no track/reader/output can be created.
    /// - Throws: Any error thrown while loading tracks from the asset.
    func decodeMonoPCM() async throws -> DecodedPCM? {
        guard let audioTrack = try await self.asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }

        guard let reader = try? AVAssetReader(asset: self.asset) else {
            return nil
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        guard reader.canAdd(output) else {
            return nil
        }

        reader.add(output)
        guard reader.startReading() else {
            return nil
        }

        var samples: [Float] = []
        var sampleRate: Double = 44_100
        var channelCount = 1

        while let sampleBuffer = output.copyNextSampleBuffer() {
            if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
                let audioFormatDescription = formatDescription as CMAudioFormatDescription
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormatDescription) {
                    sampleRate = asbd.pointee.mSampleRate
                    channelCount = max(Int(asbd.pointee.mChannelsPerFrame), 1)
                }
            }

            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }

            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            ) == kCMBlockBufferNoErr,
                  let dataPointer
            else {
                continue
            }

            let floatCount = length / MemoryLayout<Float>.size
            guard floatCount >= channelCount else {
                continue
            }

            dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { pointer in
                let frameCount = floatCount / channelCount
                samples.reserveCapacity(samples.count + frameCount)

                var frame = 0
                while frame < frameCount {
                    let base = frame * channelCount
                    var mixed: Float = 0

                    var channel = 0
                    while channel < channelCount {
                        mixed += pointer[base + channel]
                        channel += 1
                    }

                    samples.append(mixed / Float(channelCount))
                    frame += 1
                }
            }
        }

        return DecodedPCM(samples: samples, sampleRate: sampleRate)
    }

}
