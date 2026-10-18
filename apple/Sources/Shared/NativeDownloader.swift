import Foundation
import AVFoundation
import YouTubeKit

public struct DownloadResult: Sendable {
    public let title: String
    public let fileName: String
    public let isVideo: Bool
    public let quality: String
}

public actor NativeDownloader {
    public init() {}

    public func download(
        urlString: String,
        type: DownloadType,
        destinationDirectory: URL,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> DownloadResult {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            throw NSError(domain: "NativeDownloader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid YouTube URL."])
        }

        onProgress(0.05, "Contacting YouTube...")
        let yt = YouTube(url: url)

        onProgress(0.10, "Fetching video metadata...")
        let metadata = try await yt.metadata
        let rawTitle = metadata?.title ?? "YouTube Media"
        let safeTitle = rawTitle
            .components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:"))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = safeTitle.isEmpty ? "Media" : safeTitle

        onProgress(0.15, "Finding optimal stream...")
        let streams = try await yt.streams
        let isVideo = (type == .video)

        if !isVideo {
            // Audio Only Download
            let audioOnly = streams.filterAudioOnly()
            let m4aAudio = audioOnly.filter { $0.fileExtension == .m4a || $0.isNativelyPlayable }
            guard let targetStream = m4aAudio.highestAudioBitrateStream() ?? audioOnly.highestAudioBitrateStream() else {
                throw NSError(domain: "NativeDownloader", code: 3, userInfo: [NSLocalizedDescriptionKey: "No audio stream found for this link."])
            }

            let fileExtension = targetStream.fileExtension == .m4a ? "m4a" : targetStream.fileExtension.rawValue
            let fileName = "\(finalTitle).\(fileExtension)"
            let destinationURL = destinationDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: destinationURL)

            try await downloadChunked(
                from: targetStream.url,
                to: destinationURL,
                label: "audio",
                progressRange: 0.20...0.98,
                onProgress: onProgress
            )

            let qualityLabel = targetStream.bitrate.map { "\($0 / 1000) kbps" } ?? "Best"
            return DownloadResult(
                title: rawTitle,
                fileName: fileName,
                isVideo: false,
                quality: qualityLabel
            )
        } else {
            // Video Download: check if pre-muxed progressive stream exists
            let progressive = streams.filterVideoAndAudio().filter { $0.isNativelyPlayable }
            let fileName = "\(finalTitle).mp4"
            let destinationURL = destinationDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: destinationURL)

            if let singleStream = progressive.highestResolutionStream() {
                try await downloadChunked(
                    from: singleStream.url,
                    to: destinationURL,
                    label: "video",
                    progressRange: 0.20...0.98,
                    onProgress: onProgress
                )
                return DownloadResult(
                    title: rawTitle,
                    fileName: fileName,
                    isVideo: true,
                    quality: "HD MP4"
                )
            }

            // Modern YouTube video (separate Video and Audio streams) -> Download both and merge natively!
            let avc1Videos = streams.filterVideoOnly().filter { $0.videoCodec == .avc1 }
            guard let bestVideo = avc1Videos.highestResolutionStream() ?? streams.filterVideoOnly().filter({ $0.isNativelyPlayable }).highestResolutionStream() ?? streams.filterVideoOnly().first else {
                throw NSError(domain: "NativeDownloader", code: 2, userInfo: [NSLocalizedDescriptionKey: "No compatible video stream found for this link."])
            }

            let audioOnly = streams.filterAudioOnly()
            guard let bestAudio = audioOnly.filter({ $0.fileExtension == .m4a }).highestAudioBitrateStream() ?? audioOnly.highestAudioBitrateStream() else {
                throw NSError(domain: "NativeDownloader", code: 3, userInfo: [NSLocalizedDescriptionKey: "No audio track found to accompany video."])
            }

            let tempDir = FileManager.default.temporaryDirectory
            let tempVideoURL = tempDir.appendingPathComponent(UUID().uuidString + "_video.mp4")
            let tempAudioURL = tempDir.appendingPathComponent(UUID().uuidString + "_audio.m4a")

            defer {
                try? FileManager.default.removeItem(at: tempVideoURL)
                try? FileManager.default.removeItem(at: tempAudioURL)
            }

            // Step 1: Download video stream (progress 0.20 -> 0.75)
            try await downloadChunked(
                from: bestVideo.url,
                to: tempVideoURL,
                label: "video track",
                progressRange: 0.20...0.75,
                onProgress: onProgress
            )

            // Step 2: Download audio stream (progress 0.75 -> 0.92)
            try await downloadChunked(
                from: bestAudio.url,
                to: tempAudioURL,
                label: "audio track",
                progressRange: 0.75...0.92,
                onProgress: onProgress
            )

            // Step 3: Merge video and audio with AVFoundation (progress 0.92 -> 0.99)
            onProgress(0.93, "Merging video and audio...")
            try await merge(videoURL: tempVideoURL, audioURL: tempAudioURL, outputURL: destinationURL)

            return DownloadResult(
                title: rawTitle,
                fileName: fileName,
                isVideo: true,
                quality: "Full HD MP4"
            )
        }
    }

    private func downloadChunked(
        from url: URL,
        to destination: URL,
        label: String,
        progressRange: ClosedRange<Double>,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        var headRequest = URLRequest(url: url)
        headRequest.httpMethod = "HEAD"
        headRequest.timeoutInterval = 15

        let totalBytes: Int64
        do {
            let (_, headResponse) = try await URLSession.shared.data(for: headRequest)
            totalBytes = headResponse.expectedContentLength
        } catch {
            totalBytes = -1
        }

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let fileHandle = try? FileHandle(forWritingTo: destination) else {
            throw NSError(domain: "NativeDownloader", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to open local file for writing."])
        }
        defer {
            try? fileHandle.close()
        }

        if totalBytes > 0 {
            let chunkSize: Int64 = 1024 * 1024 // 1 MB chunks
            var offset: Int64 = 0
            let startTime = Date()

            while offset < totalBytes {
                let end = min(offset + chunkSize - 1, totalBytes - 1)
                var request = URLRequest(url: url)
                request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")
                request.timeoutInterval = 20

                let (chunkData, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 206) else {
                    throw NSError(domain: "NativeDownloader", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unexpected server response during chunk download."])
                }

                try fileHandle.write(contentsOf: chunkData)
                offset = end + 1

                let fraction = Double(offset) / Double(totalBytes)
                let currentProgress = progressRange.lowerBound + fraction * (progressRange.upperBound - progressRange.lowerBound)
                let elapsed = Date().timeIntervalSince(startTime)
                let speedMB = elapsed > 0 ? (Double(offset) / (1024 * 1024)) / elapsed : 0
                let remainingBytes = totalBytes - offset
                let speedBytesPerSec = elapsed > 0 ? Double(offset) / elapsed : 0
                let etaSec = speedBytesPerSec > 0 ? Int(Double(remainingBytes) / speedBytesPerSec) : 0

                let status = String(format: "Downloading %@: %.0f%% • %.1f MB/s • %ds remaining", label, fraction * 100, speedMB, etaSec)
                onProgress(currentProgress, status)
            }
        } else {
            onProgress(progressRange.lowerBound, "Downloading \(label)...")
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: tempURL, to: destination)
            onProgress(progressRange.upperBound, "Downloaded \(label)")
        }
    }

    private func merge(videoURL: URL, audioURL: URL, outputURL: URL) async throws {
        let composition = AVMutableComposition()

        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw NSError(domain: "NativeDownloader", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to extract tracks for merge."])
        }

        let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let duration = CMTimeMinimum(videoDuration, audioDuration)
        let timeRange = CMTimeRange(start: .zero, duration: duration)

        try compVideoTrack?.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        try compAudioTrack?.insertTimeRange(timeRange, of: audioTrack, at: .zero)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw NSError(domain: "NativeDownloader", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to create media export session."])
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        await exportSession.export()

        if let error = exportSession.error {
            throw error
        }
        if exportSession.status != .completed {
            throw NSError(domain: "NativeDownloader", code: 8, userInfo: [NSLocalizedDescriptionKey: "Video and audio merge failed with status \(exportSession.status.rawValue)"])
        }
    }
}
