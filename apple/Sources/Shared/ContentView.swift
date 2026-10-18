import SwiftUI
import AVFoundation
import AVKit

public struct ContentView: View {
    @StateObject private var viewModel = DownloaderViewModel()

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
                Section("2. Format") {
                    Picker("Format", selection: $viewModel.downloadType) {
                        ForEach(DownloadType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.downloadType == .audio {
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundColor(.purple)
                            Text("High Quality Audio (M4A / AAC)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack {
                            Image(systemName: "film")
                                .foregroundColor(.blue)
                            Text("Full HD Video (MP4)")
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
                                Text(viewModel.isDownloading ? "Downloading..." : (viewModel.downloadType == .video ? "Download Video (MP4)" : "Download Audio (M4A)"))
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isDownloading || viewModel.urlInput.isEmpty)
                        .padding(.top, 4)
                    }
                }

                // Section 4: Downloaded Tracks / Videos Library
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
                                    Text("\(track.isVideo ? "MP4 Video" : "Audio") • \(track.date.formatted(date: .abbreviated, time: .shortened))")
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
