import SwiftUI

struct RootView: View {
    @StateObject private var history = HistoryStore()
    @State private var showGuide = !AppSettings.hasSeenGuide

    var body: some View {
        TabView {
            RewriteView()
                .tabItem { Label("교정", systemImage: "wand.and.stars") }
            HistoryView()
                .tabItem { Label("기록", systemImage: "clock") }
            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
        }
        .environmentObject(history)
        .sheet(isPresented: $showGuide, onDismiss: { AppSettings.hasSeenGuide = true }) {
            NavigationStack { KeyboardGuideView(isSheet: true) }
        }
    }
}
