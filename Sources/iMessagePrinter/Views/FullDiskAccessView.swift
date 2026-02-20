import SwiftUI

struct FullDiskAccessView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue)
                .symbolRenderingMode(.hierarchical)

            Text("Full Disk Access Required")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("iMessagePrinter needs Full Disk Access to read your message history.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            VStack(alignment: .leading, spacing: 16) {
                instructionRow(
                    number: 1,
                    icon: "gearshape.fill",
                    title: "Open Privacy Settings",
                    detail: "Click the button below to open System Settings"
                )
                instructionRow(
                    number: 2,
                    icon: "plus.circle.fill",
                    title: "Add the app",
                    detail: "Click the + button, navigate to this app, and add it"
                )
                instructionRow(
                    number: 3,
                    icon: "togglepower",
                    title: "Enable access",
                    detail: "Toggle the switch next to iMessagePrinter"
                )
                instructionRow(
                    number: 4,
                    icon: "arrow.clockwise.circle.fill",
                    title: "Come back here",
                    detail: "Click \"I've Granted Access\" below"
                )
            }
            .padding(20)
            .frame(maxWidth: 480)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 16) {
                Button {
                    FullDiskAccessChecker.triggerTCCPrompt()
                    FullDiskAccessChecker.openSystemSettings()
                } label: {
                    Label("Open Privacy Settings", systemImage: "gearshape")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    appState.checkAccess()
                    if appState.hasFullDiskAccess {
                        appState.loadConversations()
                    }
                } label: {
                    Label("I've Granted Access", systemImage: "checkmark.circle")
                        .frame(minWidth: 180)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Text("You may need to quit and relaunch the app after granting access.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Trigger TCC so the app appears in the System Settings list
            FullDiskAccessChecker.triggerTCCPrompt()
        }
    }

    private func instructionRow(number: Int, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(.blue)
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.callout.bold())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundStyle(.blue)
                        .font(.callout)
                    Text(title)
                        .font(.body.bold())
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
