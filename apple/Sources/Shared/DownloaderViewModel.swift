import Foundation
import SwiftUI
import AVFoundation
#if os(iOS)
import UIKit
#endif

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

    private var audioPlayer: AVAudioPlayer?
    private let storageKey = "SavedDownloadedTracks"
    private let downloader = NativeDownloader()

    public init() {
        configureAudioSession()
        loadSavedTracks()
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
        statusMessage = "Connecting to YouTube..."

        #if os(iOS)
        var backgroundTaskID = UIBackgroundTaskIdentifier.invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "YouTubeDownload") {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        #endif

        Task {
            await executeDownload(for: trimmed)

            #if os(iOS)
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
            #endif
        }
    }

    private func executeDownload(for url: String) async {
        do {
            let result = try await downloader.download(
                urlString: url,
                type: downloadType,
                destinationDirectory: saveDirectory
            ) { [weak self] pct, message in
                Task { @MainActor [weak self] in
                    self?.progress = pct
                    self?.statusMessage = message
                }
            }

            let newTrack = DownloadedTrack(
                title: result.title,
                fileName: result.fileName,
                quality: result.quality,
                isVideo: result.isVideo
            )

            // Remove existing duplicate if re-downloaded
            tracks.removeAll { $0.fileName == result.fileName }
            tracks.insert(newTrack, at: 0)
            saveTracks()

            progress = 1.0
            statusMessage = "✅ Successfully downloaded: \(result.title)"
            urlInput = ""
        } catch {
            print("[Downloader] Download error: \(error)")
            statusMessage = "❌ Error: \(error.localizedDescription)"
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
