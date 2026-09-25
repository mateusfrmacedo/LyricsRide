import SwiftUI

@main
struct LyricsRideApp: App {
    @StateObject private var session = LyricsSession()
    @StateObject private var spotify = SpotifyManager()
    @StateObject private var driveMode = DriveModeManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(spotify)
                .environmentObject(driveMode)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { spotify.reconnectWhenActive() }
        }
    }
}
