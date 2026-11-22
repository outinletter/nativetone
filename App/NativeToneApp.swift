import SwiftUI

@main
struct NativeToneApp: App {
    @State private var refresh = 0

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(refresh)
                .onReceive(NotificationCenter.default.publisher(for: .uiLanguageChanged)) { _ in refresh += 1 }
        }
    }
}
