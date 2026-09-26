import Foundation
import SwiftUI
import AVFoundation

@MainActor
public class DownloaderViewModel: ObservableObject {
    @Published public var urlInput: String = ""
    @Published public var selectedQuality: DownloadQuality = .best
    @Published public var isDownloading: Bool = false
    @Published public var progress: Double = 0.0
    @Published public var statusMessage: String = "Paste a YouTube link above to download."
    @Published public var tracks: [DownloadedTrack] = []
    @Published public var currentlyPlayingID: UUID? = nil
    @Published public var isPlaying: Bool = false

    private var audioPlayer: AVAudioPlayer?
    private let storageKey = "SavedDownloadedTracks"

    public init() {
        loadSavedTracks()
    }

    public var saveDirectory: URL {
        #if os(macOS)
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        #else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        #endif
    }

    public func pasteFromClipboard() {
        #if os(iOS)
        if let text = UIPasteboard.general.string {
            self.urlInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #elseif os(macOS)
        if let text = NSPasteboard.general.string(forType: .string) {
            self.urlInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
    }

    public func startDownload() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Please enter a valid YouTube link."
            return
        }

        guard trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") else {
            statusMessage = "Invalid link: must start with https://"
            return
        }

        isDownloading = true
        progress = 0.1
        statusMessage = "Contacting download service..."

        Task {
            await executeDownload(for: trimmed)
        }
    }

    private func executeDownload(for url: String) async {
        #if os(macOS)
        // Native macOS direct execution using embedded Python/yt-dlp
        await executeMacLocalDownload(for: url)
        #else
        // iOS: Communicates with local network or cloud downloader backend
        await executeRemoteDownload(for: url)
        #endif
    }

    #if os(macOS)
    private func executeMacLocalDownload(for url: String) async {
        do {
            statusMessage = "Extracting audio with yt-dlp & FFmpeg..."
            progress = 0.3

            let pythonPath = "/opt/homebrew/bin/python3"
            let ytDlpScript = """
            import os, sys, certifi, yt_dlp
            os.environ['SSL_CERT_FILE'] = certifi.where()
            ydl_opts = {
                'format': 'bestaudio/best',
                'outtmpl': '\(saveDirectory.path)/%(title)s.%(ext)s',
                'nocheckcertificate': True,
                'postprocessors': [{
                    'key': 'FFmpegExtractAudio',
                    'preferredcodec': 'mp3',
                    'preferredquality': '\(selectedQuality.rawValue)',
                }],
                'quiet': True,
                'ffmpeg_location': '/opt/homebrew/bin',
                'js_runtimes': {'node': {'path': '/opt/homebrew/bin/node'}}
            }
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info('\(url)', download=True)
                print(info.get('title', 'Audio Track'))
            """

            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = ["-c", ytDlpScript]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            self.progress = 0.7
            self.statusMessage = "Converting to MP3 (FFmpeg)..."

            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus == 0 {
                let title = output.components(separatedBy: .newlines).last ?? "Downloaded Audio"
                let fileName = "\(title).mp3"
                let newTrack = DownloadedTrack(title: title, fileName: fileName, quality: selectedQuality.rawValue)
                self.tracks.insert(newTrack, at: 0)
                self.saveTracks()

                self.progress = 1.0
                self.statusMessage = "✅ Successfully downloaded: \(title)"
            } else {
                self.statusMessage = "❌ Download error: \(output)"
            }
        } catch {
            self.statusMessage = "❌ Error: \(error.localizedDescription)"
        }
        self.isDownloading = false
    }
    #endif

    private func executeRemoteDownload(for url: String) async {
        // Backend API endpoint (Local server or Cloud Run)
        let backendUrlString = "http://localhost:8000/download"
        guard let endpoint = URL(string: backendUrlString) else { return }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: String] = [
            "url": url,
            "quality": selectedQuality.rawValue
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            statusMessage = "Downloading via server..."
            progress = 0.5

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                // Save MP3 file locally in app sandbox Documents folder
                let fileName = "Downloaded_\(Int(Date().timeIntervalSince1970)).mp3"
                let destination = saveDirectory.appendingPathComponent(fileName)
                try data.write(to: destination)

                let newTrack = DownloadedTrack(title: "YouTube Audio", fileName: fileName, quality: selectedQuality.rawValue)
                self.tracks.insert(newTrack, at: 0)
                self.saveTracks()

                progress = 1.0
                statusMessage = "✅ Download complete! Saved to library."
            } else {
                statusMessage = "Server returned an error."
            }
        } catch {
            statusMessage = "Could not reach download server. Ensure server is running."
        }
        isDownloading = false
    }

    public func togglePlay(track: DownloadedTrack) {
        let fileURL = saveDirectory.appendingPathComponent(track.fileName)

        if currentlyPlayingID == track.id {
            if isPlaying {
                audioPlayer?.pause()
                isPlaying = false
            } else {
                audioPlayer?.play()
                isPlaying = true
            }
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            currentlyPlayingID = track.id
            isPlaying = true
        } catch {
            statusMessage = "Failed to play audio file."
        }
    }

    public func deleteTrack(_ track: DownloadedTrack) {
        let fileURL = saveDirectory.appendingPathComponent(track.fileName)
        try? FileManager.default.removeItem(at: fileURL)
        if currentlyPlayingID == track.id {
            audioPlayer?.stop()
            currentlyPlayingID = nil
            isPlaying = false
        }
        tracks.removeAll { $0.id == track.id }
        saveTracks()
    }

    private func saveTracks() {
        if let encoded = try? JSONEncoder().encode(tracks) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    private func loadSavedTracks() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([DownloadedTrack].self, from: data) {
            self.tracks = decoded
        }
    }
}
