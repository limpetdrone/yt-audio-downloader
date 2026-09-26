import SwiftUI
import AVFoundation

public struct ContentView: View {
    @StateObject private var viewModel = DownloaderViewModel()
    @State private var serverUrlDraft: String = ""
    @State private var showServerSettings: Bool = false

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

                #if os(iOS)
                // Section 4: Backend Server Connection (iOS only)
                Section("Backend Server") {
                    DisclosureGroup(isExpanded: $showServerSettings) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your Mac acts as your personal download engine when on the same Wi-Fi.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack {
                                TextField("http://192.168.0.61:8000", text: $serverUrlDraft)
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
                            Image(systemName: "server.rack")
                            Text("Download Server")
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(viewModel.isServerConnected ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text(viewModel.isServerConnected ? "Online" : "Offline")
                                    .font(.caption)
                                    .foregroundColor(viewModel.isServerConnected ? .green : .red)
                            }
                        }
                    }
                }
                #endif

                // Section 5: Downloaded Tracks Library
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
            .onAppear {
                serverUrlDraft = viewModel.serverUrl
                Task {
                    await viewModel.checkServerHealth()
                }
            }
        }
    }
}
