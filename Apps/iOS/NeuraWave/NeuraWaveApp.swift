import NeuraWaveCore
import SwiftUI

@main
struct NeuraWaveApp: App {
    init() {
        // Category only: activating here would stop your music just for
        // opening the app. The engine activates the session on Start.
        PlaybackAudioSession.configure(mixWithOthers: AppSettings.mixWithOthers)
        AudioSessionEvents.shared.start()
        // Registers the lock screen / AirPods commands right away.
        _ = SessionController.shared
    }

    var body: some Scene {
        WindowGroup {
            PlayerView()
                .preferredColorScheme(.dark)
        }
    }
}
