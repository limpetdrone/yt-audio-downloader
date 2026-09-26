import SwiftUI

@main
struct YTAudioDownloaderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 550, idealWidth: 600, minHeight: 450, idealHeight: 520)
                #endif
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
