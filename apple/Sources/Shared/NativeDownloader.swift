import Foundation
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

        let targetStream: YouTubeKit.Stream
        let fileExtension: String

        if isVideo {
            // Find best native video+audio MP4 stream
            let videoStreams = streams.filterVideoAndAudio().filter { $0.isNativelyPlayable }
            if let bestVideo = videoStreams.highestResolutionStream() {
                targetStream = bestVideo
                fileExtension = "mp4"
            } else if let anyVideo = streams.filterVideoAndAudio().first {
                targetStream = anyVideo
                fileExtension = anyVideo.fileExtension.rawValue
            } else {
                throw NSError(domain: "NativeDownloader", code: 2, userInfo: [NSLocalizedDescriptionKey: "No compatible video stream found for this link."])
            }
        } else {
            // Find best native AAC/M4A audio stream
            let audioOnly = streams.filterAudioOnly()
            let m4aAudio = audioOnly.filter { $0.fileExtension == .m4a || $0.isNativelyPlayable }
            if let bestM4a = m4aAudio.highestAudioBitrateStream() {
                targetStream = bestM4a
                fileExtension = "m4a"
            } else if let bestAnyAudio = audioOnly.highestAudioBitrateStream() {
                targetStream = bestAnyAudio
                fileExtension = bestAnyAudio.fileExtension.rawValue
            } else {
                throw NSError(domain: "NativeDownloader", code: 3, userInfo: [NSLocalizedDescriptionKey: "No audio stream found for this link."])
            }
        }

        let streamURL = targetStream.url
        let fileName = "\(finalTitle).\(fileExtension)"
        let destinationURL = destinationDirectory.appendingPathComponent(fileName)

        // Remove previous file if exists
        try? FileManager.default.removeItem(at: destinationURL)

        onProgress(0.20, "Connecting to media stream...")
        var headRequest = URLRequest(url: streamURL)
        headRequest.httpMethod = "HEAD"
        headRequest.timeoutInterval = 15

        let totalBytes: Int64
        do {
            let (_, headResponse) = try await URLSession.shared.data(for: headRequest)
            totalBytes = headResponse.expectedContentLength
        } catch {
            totalBytes = -1
        }

        if totalBytes > 0 {
            // Fast chunked Range download (bypasses YouTube playback throttle)
            try await downloadChunked(
                from: streamURL,
                to: destinationURL,
                totalBytes: totalBytes,
                title: rawTitle,
                onProgress: onProgress
            )
        } else {
            // Fallback direct download
            try await downloadDirect(
                from: streamURL,
                to: destinationURL,
                title: rawTitle,
                onProgress: onProgress
            )
        }

        let qualityLabel = isVideo ? "HD MP4" : (targetStream.bitrate.map { "\($0 / 1000) kbps" } ?? "Best")
        return DownloadResult(
            title: rawTitle,
            fileName: fileName,
            isVideo: isVideo,
            quality: qualityLabel
        )
    }

    private func downloadChunked(
        from url: URL,
        to destination: URL,
        totalBytes: Int64,
        title: String,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let fileHandle = try? FileHandle(forWritingTo: destination) else {
            throw NSError(domain: "NativeDownloader", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to open local file for writing."])
        }
        defer {
            try? fileHandle.close()
        }

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

            let progressPct = Double(offset) / Double(totalBytes)
            let elapsed = Date().timeIntervalSince(startTime)
            let speedMB = elapsed > 0 ? (Double(offset) / (1024 * 1024)) / elapsed : 0
            let remainingBytes = totalBytes - offset
            let speedBytesPerSec = elapsed > 0 ? Double(offset) / elapsed : 0
            let etaSec = speedBytesPerSec > 0 ? Int(Double(remainingBytes) / speedBytesPerSec) : 0

            let status = String(format: "Downloading: %.0f%% • %.1f MB/s • %ds remaining", progressPct * 100, speedMB, etaSec)
            onProgress(min(0.99, max(0.20, progressPct)), status)
        }
    }

    private func downloadDirect(
        from url: URL,
        to destination: URL,
        title: String,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        onProgress(0.40, "Downloading media...")
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }
}
