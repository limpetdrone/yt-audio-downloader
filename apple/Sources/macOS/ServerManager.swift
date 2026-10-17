import Foundation
import SwiftUI
import AppKit
import Security
import CoreImage
import CoreImage.CIFilterBuiltins

/// Finds command-line tools installed with Homebrew or the python.org installer.
enum Tools {
    static func find(_ name: String) -> String? {
        let dirs = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/Library/Frameworks/Python.framework/Versions/Current/bin",
            "/usr/bin",
        ]
        return dirs
            .map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var python: String? { find("python3") }
    static var ngrok: String? { find("ngrok") }
    static var ffmpegDir: String? { find("ffmpeg").map { ($0 as NSString).deletingLastPathComponent } }
    static var node: String? { find("node") }

    /// PATH for child processes, so yt-dlp can find ffmpeg and node.
    static var searchPath: String {
        "/opt/homebrew/bin:/usr/local/bin:/Library/Frameworks/Python.framework/Versions/Current/bin:/usr/bin:/bin"
    }
}

/// Holds the running child processes so they can be stopped when the app quits.
private final class ProcessBag: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [Process] = []

    func add(_ p: Process) {
        lock.lock(); processes.append(p); lock.unlock()
    }

    func terminateAll() {
        lock.lock()
        let all = processes
        processes.removeAll()
        lock.unlock()
        for p in all where p.isRunning { p.terminate() }
    }
}

/// Runs server.py and an ngrok tunnel so the iPhone app can download through this Mac.
@MainActor
final class ServerManager: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var publicURL: String = ""
    @Published var ngrokToken: String {
        didSet { UserDefaults.standard.set(ngrokToken, forKey: Keys.token) }
    }
    @Published var ngrokDomain: String {
        didSet { UserDefaults.standard.set(ngrokDomain, forKey: Keys.domain) }
    }
    @Published private(set) var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Keys.apiKey) }
    }
    @Published var autoStart: Bool {
        didSet { UserDefaults.standard.set(autoStart, forKey: Keys.autoStart) }
    }

    /// Local port for server.py. Only reachable from this Mac; ngrok forwards to it.
    let port = 8765

    private var serverProcess: Process?
    private var tunnelProcess: Process?
    private var isStopping = false
    /// Bumped on every start, so exit callbacks from an earlier run are ignored.
    private var generation = 0
    private var lastTunnelError = ""
    private let bag = ProcessBag()

    private enum Keys {
        static let token = "ngrok_authtoken"
        static let domain = "ngrok_domain"
        static let apiKey = "server_api_key"
        static let autoStart = "server_autostart"
    }

    init() {
        let defaults = UserDefaults.standard
        ngrokToken = defaults.string(forKey: Keys.token) ?? ""
        ngrokDomain = defaults.string(forKey: Keys.domain) ?? ""
        autoStart = defaults.bool(forKey: Keys.autoStart)
        if let saved = defaults.string(forKey: Keys.apiKey), !saved.isEmpty {
            apiKey = saved
        } else {
            let fresh = ServerManager.makeKey()
            apiKey = fresh
            defaults.set(fresh, forKey: Keys.apiKey)
        }

        let bag = self.bag
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in
            bag.terminateAll()
        }

        if autoStart {
            Task { @MainActor [weak self] in self?.start() }
        }
    }

    var isActive: Bool {
        state == .starting || state == .running
    }

    /// Link the iPhone app understands; shown as a QR code.
    var pairingLink: String? {
        guard !publicURL.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = "ytdownloader"
        c.host = "connect"
        c.queryItems = [
            URLQueryItem(name: "url", value: publicURL),
            URLQueryItem(name: "key", value: apiKey),
        ]
        return c.url?.absoluteString
    }

    var pairingQRCode: NSImage? {
        guard let link = pairingLink else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width, height: output.extent.height))
    }

    func start() {
        guard serverProcess == nil, tunnelProcess == nil else { return }

        let token = ngrokToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = cleanedDomain
        guard let python = Tools.python else {
            state = .failed("Python 3 not found. Install it with: brew install python")
            return
        }
        guard let ngrok = Tools.ngrok else {
            state = .failed("ngrok not found. Install it with: brew install ngrok")
            return
        }
        guard !token.isEmpty else {
            state = .failed("Enter your ngrok authtoken (ngrok.com dashboard > Your Authtoken).")
            return
        }
        guard let script = Bundle.main.path(forResource: "server", ofType: "py") else {
            state = .failed("server.py is missing from the app bundle.")
            return
        }

        isStopping = false
        generation += 1
        let gen = generation
        lastTunnelError = ""
        publicURL = domain.isEmpty ? "" : "https://\(domain)"
        state = .starting

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Tools.searchPath
        env["PORT"] = String(port)
        env["HOST"] = "127.0.0.1"
        env["API_KEY"] = apiKey
        env["PYTHONUNBUFFERED"] = "1"

        let server = Process()
        server.executableURL = URL(fileURLWithPath: python)
        server.arguments = [script]
        server.environment = env
        server.terminationHandler = { [weak self] p in
            let code = p.terminationStatus
            Task { @MainActor in self?.childExited(name: "Server", code: code, generation: gen) }
        }

        var tunnelEnv = env
        tunnelEnv["NGROK_AUTHTOKEN"] = token
        var args = ["http", String(port), "--log", "stdout", "--log-format", "logfmt"]
        if !domain.isEmpty { args += ["--url", domain] }

        let tunnel = Process()
        tunnel.executableURL = URL(fileURLWithPath: ngrok)
        tunnel.arguments = args
        tunnel.environment = tunnelEnv
        let pipe = Pipe()
        tunnel.standardOutput = pipe
        tunnel.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.readTunnelLog(text) }
        }
        tunnel.terminationHandler = { [weak self] p in
            let code = p.terminationStatus
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in self?.childExited(name: "Tunnel", code: code, generation: gen) }
        }

        do {
            try server.run()
            serverProcess = server
            bag.add(server)
        } catch {
            state = .failed("Could not start Python: \(error.localizedDescription)")
            return
        }
        do {
            try tunnel.run()
            tunnelProcess = tunnel
            bag.add(tunnel)
        } catch {
            stop()
            state = .failed("Could not start ngrok: \(error.localizedDescription)")
            return
        }

        Task { await waitUntilOnline() }
    }

    func stop() {
        isStopping = true
        bag.terminateAll()
        serverProcess = nil
        tunnelProcess = nil
        publicURL = ""
        state = .stopped
    }

    /// Makes a new key. The iPhone app must be updated with it afterwards.
    func regenerateKey() {
        let wasActive = isActive
        if wasActive { stop() }
        apiKey = ServerManager.makeKey()
        if wasActive {
            // Give the old server a moment to release the port.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.start()
            }
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Private

    private var cleanedDomain: String {
        var d = ngrokDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where d.hasPrefix(prefix) {
            d = String(d.dropFirst(prefix.count))
        }
        while d.hasSuffix("/") { d = String(d.dropLast()) }
        return d
    }

    private func readTunnelLog(_ text: String) {
        for line in text.components(separatedBy: .newlines) {
            if publicURL.isEmpty,
               let range = line.range(of: #"url=https://[^\s"]+"#, options: .regularExpression) {
                publicURL = String(line[range].dropFirst("url=".count))
            }
            if line.contains("lvl=eror") || line.contains("lvl=crit") || line.contains("ERROR") {
                if let range = line.range(of: #"err="[^"]*""#, options: .regularExpression) {
                    lastTunnelError = String(line[range].dropFirst(5).dropLast())
                } else {
                    lastTunnelError = line
                }
            }
        }
    }

    private func childExited(name: String, code: Int32, generation gen: Int) {
        guard gen == generation, !isStopping, isActive else { return }
        var message = "\(name) stopped unexpectedly (exit code \(code))."
        if name == "Tunnel" && !lastTunnelError.isEmpty {
            message += " \(lastTunnelError)"
        } else if name == "Server" {
            message += " Check that yt-dlp is installed: python3 -m pip install yt-dlp certifi"
        }
        stop()
        state = .failed(message)
    }

    /// Polls the public address until the server answers through the tunnel.
    private func waitUntilOnline() async {
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard state == .starting else { return }
            guard !publicURL.isEmpty, let url = URL(string: "\(publicURL)/health") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            request.setValue("1", forHTTPHeaderField: "ngrok-skip-browser-warning")
            if let (_, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                if state == .starting { state = .running }
                return
            }
        }
        if state == .starting {
            let detail = lastTunnelError.isEmpty ? "" : " \(lastTunnelError)"
            stop()
            state = .failed("The server did not come online through ngrok.\(detail)")
        }
    }

    private static func makeKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Settings section in the Mac app for sharing this Mac with the iPhone app.
struct MacServerSection: View {
    @ObservedObject var server: ServerManager

    var body: some View {
        Section("iPhone Access") {
            HStack {
                Image(systemName: "iphone.radiowaves.left.and.right")
                Text("Let the iPhone app download through this Mac")
                Spacer()
                statusBadge
            }

            Text("Runs the download server on this Mac and makes it reachable through a secure ngrok address. Every request needs the key below.")
                .font(.caption)
                .foregroundColor(.secondary)

            SecureField("ngrok authtoken", text: $server.ngrokToken)
                .disabled(server.isActive)
            TextField("ngrok domain (e.g. name.ngrok-free.dev)", text: $server.ngrokDomain)
                .disabled(server.isActive)
            Toggle("Start automatically when the app opens", isOn: $server.autoStart)

            HStack {
                Text("Key")
                Spacer()
                Text(server.apiKey)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                Button("Copy") { server.copyToClipboard(server.apiKey) }
                Button("New Key") { server.regenerateKey() }
            }

            if !server.publicURL.isEmpty {
                HStack {
                    Text("Address")
                    Spacer()
                    Text(server.publicURL)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                    Button("Copy") { server.copyToClipboard(server.publicURL) }
                }
            }

            if server.state == .running, let qr = server.pairingQRCode {
                HStack(alignment: .center, spacing: 16) {
                    Image(nsImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 150, height: 150)
                    Text("Scan this with the iPhone camera to set the address and key in the iPhone app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if case .failed(let message) = server.state {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .textSelection(.enabled)
            }

            Button {
                server.isActive ? server.stop() : server.start()
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: server.isActive ? "stop.circle.fill" : "play.circle.fill")
                    Text(server.isActive ? "Stop Sharing" : "Start Sharing")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(server.isActive ? .red : .accentColor)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (color, label): (Color, String) = {
            switch server.state {
            case .stopped: return (.gray, "Off")
            case .starting: return (.orange, "Starting...")
            case .running: return (.green, "Online")
            case .failed: return (.red, "Error")
            }
        }()
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundColor(color)
        }
    }
}
