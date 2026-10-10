import SwiftUI

struct SetupView: View {
    @ObservedObject var prefs: PeelPreferences
    var onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Quick setup")
                    .font(.title2.weight(.semibold))
                Text("Peel works like Archive Utility: double-click to extract without opening a window. Configure that here.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 20)

            Form {
                Section("Double-click / Open With") {
                    Toggle("Extract without opening Peel’s window", isOn: $prefs.silentBackgroundExtract)
                    Toggle("Also bring Peel to the front", isOn: $prefs.openWindowOnDrop)
                        .disabled(prefs.silentBackgroundExtract)
                    Toggle("Make Peel the default app for zip, rar, 7z…", isOn: $prefs.claimDefaultHandler)
                }
                Section("After extract") {
                    Toggle("Peel beside the original file", isOn: $prefs.extractBesideSource)
                    Toggle("Reveal folder in Finder when done", isOn: $prefs.revealAfterExtract)
                }
                Section("Finder menu") {
                    Toggle("Install “Peel Here” service / droplet", isOn: $prefs.installFinderService)
                    Text("Dock icon still opens the drop window anytime. ⌘0 shows the window while Peel is running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Skip for now") {
                    prefs.didCompleteSetup = true
                    onFinish()
                }
                .keyboardShortcut(.cancelAction)

                Button("Continue") {
                    // Keep silent default coherent
                    if prefs.silentBackgroundExtract {
                        prefs.openWindowOnDrop = false
                    }
                    prefs.didCompleteSetup = true
                    prefs.applyDefaultHandlerClaim()
                    prefs.runFinderServiceInstallIfNeeded()
                    onFinish()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 16)
        }
        .padding(28)
        .frame(width: 500, height: 540)
    }
}
