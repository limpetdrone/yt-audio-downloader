import SwiftUI
import AVFoundation
import AVKit

public struct ContentView: View {
    @StateObject private var viewModel = DownloaderViewModel()
    @State private var serverUrlDraft: String = ""
    @State private var showServerSettings: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: URL Input
                Section("1. YouTube Link") {
                    HStack {
                        TextField("https://www.youtube.com/watch?v=...", text: $viewModel.urlInput)
                            .textFieldStyle(.plain)
                            .disableAutocorrection(true)
                            #if os(iOS)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                            #endif

                        Button(action: viewModel.pasteFromClipboard) {
                            Label("Paste", systemImage: "doc.on.clipboard")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Section 2: Format & Options
                Section("2. Format & Quality") {
                    Picker("Format", selection: $viewModel.downloadType) {
                        ForEach(DownloadType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.downloadType == .audio {
                        Picker("Audio Bitrate", selection: $viewModel.selectedQuality) {
                            ForEach(DownloadQuality.allCases) { q in
                                Text(q.label).tag(q)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "film")
                                .foregroundColor(.secondary)
                            Text("Full HD / Best Video (MP4)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Section 3: Status & Action
                Section("3. Download") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.statusMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if viewModel.isDownloading {
                            ProgressView(value: viewModel.progress, total: 1.0)
                                .progressViewStyle(.linear)
                        }

                        Button(action: viewModel.startDownload) {
                            HStack {
                                Spacer()
                                Image(systemName: viewModel.downloadType == .video ? "arrow.down.to.line.circle.fill" : "arrow.down.circle.fill")
                                Text(viewModel.isDownloading ? "Downloading..." : (viewModel.downloadType == .video ? "Download Video (MP4)" : "Download MP3"))
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isDownloading || viewModel.urlInput.isEmpty)
                        .padding(.top, 4)
                    }
                }

                #if os(iOS)
                // Section 4: Cloud Backend Server Connection
                Section("Server Connection") {
                    DisclosureGroup(isExpanded: $showServerSettings) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Connected to your Mac backend via secure Cloudflare Tunnel.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack {
                                TextField("https://francis-seeing-module-bolt.trycloudflare.com", text: $serverUrlDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.URL)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)

                                Button("Save") {
                                    viewModel.updateServerUrl(serverUrlDraft)
                                }
                                .buttonStyle(.bordered)
                            }

                            Button {
                                Task {
                                    await viewModel.checkServerHealth()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Test Connection")
                                }
                                .font(.footnote)
                            }
                        }
                        .padding(.vertical, 4)
                    } label: {
                        HStack {
                            Image(systemName: "cloud.fill")
                            Text("Mac Server / Tunnel")
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(viewModel.isServerConnected ? Color.green : Color.orange)
                                    .frame(width: 8, height: 8)
                                Text(viewModel.isServerConnected ? "Online" : "Connecting...")
                                    .font(.caption)
                                    .foregroundColor(viewModel.isServerConnected ? .green : .orange)
                            }
                        }
                    }
                }
                #endif

                // Section 5: Downloaded Tracks / Videos Library
                Section("Downloads (\(viewModel.tracks.count))") {
                    if viewModel.tracks.isEmpty {
                        Text("No items downloaded yet.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.tracks) { track in
                            HStack(spacing: 12) {
                                Image(systemName: track.isVideo ? "film.fill" : "music.note")
                                    .font(.title2)
                                    .foregroundColor(track.isVideo ? .blue : .purple)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text("\(track.isVideo ? "MP4 Video" : "\(track.quality) kbps") • \(track.date.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                // Play / View Button
                                Button {
                                    viewModel.togglePlay(track: track)
                                } label: {
                                    Image(systemName: track.isVideo ? "play.rectangle.fill" : ((viewModel.currentlyPlayingID == track.id && viewModel.isPlaying) ? "pause.circle.fill" : "play.circle.fill"))
                                        .font(.title2)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)

                                // Share Button
                                ShareLink(item: viewModel.fileURL(for: track)) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)

                                // Delete Button
                                Button(role: .destructive) {
                                    viewModel.deleteTrack(track)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.subheadline)
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                            #if os(macOS)
                            .contextMenu {
                                Button("Reveal in Finder") {
                                    let url = viewModel.fileURL(for: track)
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                                Button("Delete", role: .destructive) {
                                    viewModel.deleteTrack(track)
                                }
                            }
                            #endif
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    viewModel.deleteTrack(track)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("YT Downloader")
            .onAppear {
                serverUrlDraft = viewModel.serverUrl
                Task {
                    await viewModel.checkServerHealth()
                }
            }
            .sheet(item: $viewModel.activeVideoTrack) { track in
                NavigationStack {
                    VideoPlayer(player: AVPlayer(url: viewModel.fileURL(for: track)))
                        .ignoresSafeArea()
                        .navigationTitle(track.title)
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    viewModel.activeVideoTrack = nil
                                }
                            }
                            ToolbarItem(placement: .primaryAction) {
                                ShareLink(item: viewModel.fileURL(for: track)) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                        }
                }
            }
        }
    }
}
