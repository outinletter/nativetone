import SwiftUI

@main
struct NativeToneApp: App {
    @State private var refresh = 0

    init() { Theme.applyAppearance() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.primary)
                .id(refresh)
                .onReceive(NotificationCenter.default.publisher(for: .uiLanguageChanged)) { _ in refresh += 1 }
        }
    }
}
