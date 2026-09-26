import SwiftUI
import AVFoundation

public struct ContentView: View {
    @StateObject private var viewModel = DownloaderViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: URL Input
                Section("1. YouTube URL") {
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

                // Section 2: Quality & Options
                Section("2. Audio Settings") {
                    Picker("Quality", selection: $viewModel.selectedQuality) {
                        ForEach(DownloadQuality.allCases) { q in
                            Text(q.label).tag(q)
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
                                Image(systemName: "arrow.down.circle.fill")
                                Text(viewModel.isDownloading ? "Downloading..." : "Download MP3")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isDownloading || viewModel.urlInput.isEmpty)
                        .padding(.top, 4)
                    }
                }

                // Section 4: Downloaded Tracks Library
                Section("Downloaded Tracks (\(viewModel.tracks.count))") {
                    if viewModel.tracks.isEmpty {
                        Text("No tracks downloaded yet.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(viewModel.tracks) { track in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text("\(track.quality) kbps • \(track.date.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button {
                                    viewModel.togglePlay(track: track)
                                } label: {
                                    Image(systemName: (viewModel.currentlyPlayingID == track.id && viewModel.isPlaying) ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                            #if os(macOS)
                            .contextMenu {
                                Button("Reveal in Finder") {
                                    let url = viewModel.saveDirectory.appendingPathComponent(track.fileName)
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
            .navigationTitle("YouTube MP3")
        }
    }
}
