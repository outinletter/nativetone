import SwiftUI

struct RootView: View {
    @StateObject private var history = HistoryStore()
    @State private var showGuide = !AppSettings.hasSeenGuide
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            RewriteView()
                .tabItem { Label(L("교정", "Rewrite"), systemImage: "pencil.line") }
            HistoryView()
                .tabItem { Label(L("기록", "History"), systemImage: "clock") }
            SettingsView()
                .tabItem { Label(L("설정", "Settings"), systemImage: "slider.horizontal.3") }
        }
        .environmentObject(history)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { history.importKeyboardResults() }
        }
        .sheet(isPresented: $showGuide, onDismiss: { AppSettings.hasSeenGuide = true }) {
            NavigationStack { KeyboardGuideView(isSheet: true) }
        }
    }
}
