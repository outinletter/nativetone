import SwiftUI

struct RootView: View {
    @StateObject private var history = HistoryStore()
    @State private var showGuide = !AppSettings.hasSeenGuide

    var body: some View {
        TabView {
            RewriteView()
                .tabItem { Label(L("교정", "Rewrite"), systemImage: "wand.and.stars") }
            HistoryView()
                .tabItem { Label(L("기록", "History"), systemImage: "clock") }
            SettingsView()
                .tabItem { Label(L("설정", "Settings"), systemImage: "gearshape") }
        }
        .environmentObject(history)
        .sheet(isPresented: $showGuide, onDismiss: { AppSettings.hasSeenGuide = true }) {
            NavigationStack { KeyboardGuideView(isSheet: true) }
        }
    }
}
