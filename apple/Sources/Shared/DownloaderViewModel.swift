import Foundation
import SwiftUI
import AVFoundation

@MainActor
public class DownloaderViewModel: ObservableObject {
    @Published public var urlInput: String = ""
    @Published public var downloadType: DownloadType = .audio
    @Published public var selectedQuality: DownloadQuality = .best
    @Published public var isDownloading: Bool = false
    @Published public var progress: Double = 0.0
    @Published public var statusMessage: String = "Paste a YouTube link above to download."
    @Published public var tracks: [DownloadedTrack] = []
    @Published public var currentlyPlayingID: UUID? = nil
    @Published public var isPlaying: Bool = false
    @Published public var activeVideoTrack: DownloadedTrack? = nil
    @Published public var serverUrl: String = UserDefaults.standard.string(forKey: "backend_server_url") ?? "https://francis-seeing-module-bolt.trycloudflare.com"
    @Published public var isServerConnected: Bool = false
    private var currentMediaTitle: String = ""

    private var audioPlayer: AVAudioPlayer?
    private let storageKey = "SavedDownloadedTracks"

    public init() {
        configureAudioSession()
        loadSavedTracks()
        Task {
            await checkServerHealth()
        }
    }

    private func configureAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[AudioSession] Failed to set playback category: \(error)")
        }
        #endif
    }

    public var saveDirectory: URL {
        #if os(macOS)
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        #else
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        #endif
    }

    public func fileURL(for track: DownloadedTrack) -> URL {
        saveDirectory.appendingPathComponent(track.fileName)
    }

    public func updateServerUrl(_ newUrl: String) {
        let cleaned = newUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        self.serverUrl = cleaned
        UserDefaults.standard.set(cleaned, forKey: "backend_server_url")
        Task {
            await checkServerHealth()
        }
    }

    public func checkServerHealth() async {
        let trimmed = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed.hasSuffix("/") ? "\(trimmed)health" : "\(trimmed)/health") else {
            isServerConnected = false
            return
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                isServerConnected = true
            } else {
                isServerConnected = false
            }
        } catch {
            isServerConnected = false
        }
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
        progress = 0.05
        statusMessage = "Starting download..."

        Task {
            await executeDownload(for: trimmed)
        }
    }

    private func executeDownload(for url: String) async {
        #if os(macOS)
        await executeMacLocalDownload(for: url)
        #else
        await executeRemoteDownload(for: url)
        #endif
    }

    #if os(macOS)
    private func executeMacLocalDownload(for url: String) async {
        do {
            statusMessage = "Starting download..."
            progress = 0.05

            let pythonPath = "/opt/homebrew/bin/python3"
            let isVideo = (downloadType == .video)
            let outtmpl = isVideo ? "\(saveDirectory.path)/%(title)s.mp4" : "\(saveDirectory.path)/%(title)s.%(ext)s"

            let postproc = isVideo ? "[{'key': 'FFmpegVideoConvertor', 'preferedformat': 'mp4'}]" : """
            [{
                'key': 'FFmpegExtractAudio',
                'preferredcodec': 'mp3',
                'preferredquality': '\(selectedQuality.rawValue)',
            },
            {
                'key': 'FFmpegMetadata',
                'add_metadata': True,
            }]
            """

            let formatSpec = isVideo ? "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" : "bestaudio/best"

            let ytDlpScript = """
            import os, sys, certifi, yt_dlp
            os.environ['SSL_CERT_FILE'] = certifi.where()

            def hook(d):
                if d['status'] == 'downloading':
                    total = d.get('total_bytes') or d.get('total_bytes_estimate') or 0
                    dl = d.get('downloaded_bytes', 0)
                    pct = (dl / total) if total else 0
                    speed = (d.get('speed') or 0) / (1024 * 1024)
                    eta = d.get('eta') or 0
                    print(f"PROGRESS:{pct:.3f}:{speed:.1f}:{int(eta)}", flush=True)
                elif d['status'] == 'finished':
                    print("STAGE:CONVERTING", flush=True)

            ydl_opts = {
                'format': '\(formatSpec)',
                'outtmpl': '\(outtmpl)',
                'nocheckcertificate': True,
                'progress_hooks': [hook],
                'postprocessors': \(postproc),
                'quiet': True,
                'ffmpeg_location': '/opt/homebrew/bin',
                'js_runtimes': {'node': {'path': '/opt/homebrew/bin/node'}}
            }
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info('\(url)', download=True)
                print(f"TITLE:{info.get('title', 'Media Item')}", flush=True)
            """

            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = ["-c", ytDlpScript]

            let pipe = Pipe()
            process.standardOutput = pipe
            currentMediaTitle = ""

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                let lines = text.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("PROGRESS:") {
                        let parts = trimmed.components(separatedBy: ":")
                        if parts.count >= 4,
                           let pct = Double(parts[1]),
                           let speed = Double(parts[2]),
                           let eta = Int(parts[3]) {
                            Task { @MainActor [weak self] in
                                self?.progress = min(0.90, max(0.05, pct * 0.88))
                                self?.statusMessage = String(format: "Downloading: %.1f%% • %.1f MB/s • %ds remaining", pct * 100, speed, eta)
                            }
                        }
                    } else if trimmed.hasPrefix("STAGE:CONVERTING") {
                        Task { @MainActor [weak self] in
                            self?.progress = 0.92
                            self?.statusMessage = "Finalizing & converting with FFmpeg..."
                        }
                    } else if trimmed.hasPrefix("TITLE:") {
                        let t = String(trimmed.dropFirst(6))
                        Task { @MainActor [weak self] in
                            self?.currentMediaTitle = t
                        }
                    }
                }
            }

            try process.run()
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil

            if process.terminationStatus == 0 {
                let finalTitle = currentMediaTitle.isEmpty ? (isVideo ? "Video" : "Audio") : currentMediaTitle
                let ext = isVideo ? "mp4" : "mp3"
                let fileName = "\(finalTitle).\(ext)"
                let newTrack = DownloadedTrack(title: finalTitle, fileName: fileName, quality: selectedQuality.rawValue, isVideo: isVideo)
                self.tracks.insert(newTrack, at: 0)
                self.saveTracks()

                self.progress = 1.0
                self.statusMessage = "✅ Successfully downloaded: \(finalTitle)"
            } else {
                self.statusMessage = "❌ Download error occurred."
            }
        } catch {
            self.statusMessage = "❌ Error: \(error.localizedDescription)"
        }
        self.isDownloading = false
    }
    #endif

    private func executeRemoteDownload(for url: String) async {
        let trimmedServer = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmedServer.hasSuffix("/") ? String(trimmedServer.dropLast()) : trimmedServer
        guard let startUrl = URL(string: "\(base)/download/start") else {
            statusMessage = "Invalid Server URL."
            isDownloading = false
            return
        }

        var request = URLRequest(url: startUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let payload: [String: String] = [
            "url": url,
            "quality": selectedQuality.rawValue,
            "type": downloadType.rawValue
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            statusMessage = "Starting download job..."
            progress = 0.05

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let jobId = json["job_id"] as? String else {
                statusMessage = "❌ Failed to start download job on server."
                isDownloading = false
                return
            }

            // Poll progress from server
            var isFinished = false
            var downloadTitle = "Media"
            var isVideoResp = (downloadType == .video)

            while !isFinished {
                try await Task.sleep(nanoseconds: 500_000_000) // 500ms poll
                guard let pollUrl = URL(string: "\(base)/download/progress?id=\(jobId)") else { break }

                do {
                    let (pollData, pollResp) = try await URLSession.shared.data(from: pollUrl)
                    if let pollHttp = pollResp as? HTTPURLResponse, pollHttp.statusCode == 200,
                       let pollJson = try? JSONSerialization.jsonObject(with: pollData) as? [String: Any] {
                        let status = pollJson["status"] as? String ?? ""
                        let jobProgress = pollJson["progress"] as? Double ?? 0.0
                        let jobMsg = pollJson["message"] as? String ?? "Processing..."
                        let title = pollJson["title"] as? String ?? ""
                        if !title.isEmpty { downloadTitle = title }

                        self.progress = jobProgress
                        self.statusMessage = jobMsg

                        if status == "ready" {
                            isFinished = true
                            isVideoResp = (pollJson["media_type"] as? String == "video")
                            break
                        } else if status == "error" {
                            let err = pollJson["error"] as? String ?? "Unknown error"
                            self.statusMessage = "❌ \(err)"
                            self.isDownloading = false
                            return
                        }
                    }
                } catch {
                    // Transient poll error, continue polling
                }
            }

            // Retrieve file
            self.statusMessage = "Transferring file to device..."
            self.progress = 0.95
            guard let fileUrl = URL(string: "\(base)/download/file?id=\(jobId)") else {
                isDownloading = false
                return
            }

            let (fileData, fileResp) = try await URLSession.shared.data(from: fileUrl)
            if let fileHttp = fileResp as? HTTPURLResponse, fileHttp.statusCode == 200 {
                let sanitizedTitle = downloadTitle.replacingOccurrences(of: "/", with: "-")
                let ext = isVideoResp ? "mp4" : "mp3"
                let fileName = "\(sanitizedTitle).\(ext)"
                let destination = saveDirectory.appendingPathComponent(fileName)

                try fileData.write(to: destination)

                let newTrack = DownloadedTrack(
                    title: downloadTitle,
                    fileName: fileName,
                    quality: selectedQuality.rawValue,
                    isVideo: isVideoResp
                )
                self.tracks.insert(newTrack, at: 0)
                self.saveTracks()

                progress = 1.0
                statusMessage = "✅ Download complete: \(downloadTitle)"
                isServerConnected = true
            } else {
                statusMessage = "❌ Failed to retrieve downloaded file."
            }

        } catch {
            statusMessage = "❌ Server error: \(error.localizedDescription)"
            isServerConnected = false
        }
        isDownloading = false
    }

    public func togglePlay(track: DownloadedTrack) {
        if track.isVideo {
            // Open native video player sheet
            activeVideoTrack = track
            return
        }

        configureAudioSession()
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
            statusMessage = "Failed to play audio: \(error.localizedDescription)"
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
