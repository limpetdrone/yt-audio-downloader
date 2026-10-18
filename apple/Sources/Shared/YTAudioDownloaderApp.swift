import SwiftUI

@main
struct YTAudioDownloaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 550, idealWidth: 620, minHeight: 520, idealHeight: 620)
                #endif
        }
    }
}
