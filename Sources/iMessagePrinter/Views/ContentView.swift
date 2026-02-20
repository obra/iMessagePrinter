import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if !appState.hasFullDiskAccess {
                FullDiskAccessView()
            } else {
                NavigationSplitView {
                    ConversationListView()
                } detail: {
                    MessageDetailView()
                }
            }
        }
        .onAppear {
            appState.checkAccess()
            if appState.hasFullDiskAccess {
                appState.loadConversations()
            }
        }
        .alert("Error", isPresented: .constant(appState.errorMessage != nil)) {
            Button("OK") { appState.errorMessage = nil }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }
}
