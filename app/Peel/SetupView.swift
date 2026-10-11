import SwiftUI
import AppKit

struct SetupView: View {
    @ObservedObject var prefs: PeelPreferences
    var onFinish: () -> Void

    @StateObject private var fskitStatus = PeelFSStatusModel()
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 16)

            TabView(selection: $step) {
                welcomeStep.tag(0)
                browseStep.tag(1)
                extractStep.tag(2)
                finishStep.tag(3)
            }
            .tabViewStyle(.automatic)
            .frame(maxHeight: .infinity)

            footer
                .padding(.top, 16)
        }
        .padding(28)
        .frame(width: 560, height: 620)
        .onAppear { fskitStatus.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome to Peel")
                .font(.title2.weight(.semibold))
            Text(stepSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // Step indicator
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? Color.orange : Color.primary.opacity(0.15))
                        .frame(width: i == step ? 22 : 10, height: 4)
                }
                Spacer()
                Text("\(step + 1) / 4")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 8)
        }
    }

    private var stepSubtitle: String {
        switch step {
        case 0: return "Snack Studio’s archiver — open what’s inside, or extract when you mean to."
        case 1: return "Double-click should open an archive like a folder, not dump files immediately."
        case 2: return "Extract stays on purpose: Services, drop on Peel, or the Extract action."
        default: return "Apply defaults and finish. You can change everything later in Settings."
        }
    }

    // MARK: Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            labelRow("folder", "Browse", "Double-click opens contents in Finder (PeelFS when macOS allows).")
            labelRow("shippingbox", "Extract", "Right-click → Services → Peel, or drop onto the Peel window.")
            labelRow("gearshape", "You stay in control", "Default handler, Services, and PeelFS enablement are set up next.")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var browseStep: some View {
        ScrollView {
            PeelBrowseAndFSKitSection(
                prefs: prefs,
                status: fskitStatus,
                showAdvancedExtractFallback: false
            )
            .padding(.vertical, 4)
        }
    }

    private var extractStep: some View {
        Form {
            Section("When you extract") {
                Toggle("Peel beside the original file", isOn: $prefs.extractBesideSource)
                Toggle("Reveal folder in Finder when done", isOn: $prefs.revealAfterExtract)
                Toggle("Delete archive after successful extract", isOn: $prefs.deleteArchiveAfterExtract)
                Toggle("Services use progress popup only", isOn: $prefs.silentBackgroundExtract)
            }
            Section("Finder Services") {
                Toggle("Install Peel / Peel to… / Peel & Reveal", isOn: $prefs.installFinderService)
                Text("Services always extract. Browse-on-open is separate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            PeelFSStatusBanner(status: fskitStatus)

            Text("Continue will:")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                bullet(prefs.claimDefaultHandler
                       ? "Set Peel as the default app for zip, rar, 7z…"
                       : "Leave default app handlers unchanged")
                bullet(prefs.installFinderService
                       ? "Install Finder Services for extract"
                       : "Skip Finder Services install")
                bullet(prefs.browseOnOpen
                       ? "Keep browse-on-double-click on"
                       : "Double-click will extract instead of browse")
                bullet("Try enabling PeelFS via PluginKit")
            }
            .font(.callout)

            Text("If System Settings still shows multiple Peel rows, keep only /Applications/Peel.app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
            }
            Button("Skip setup") {
                prefs.didCompleteSetup = true
                onFinish()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if step < 3 {
                Button("Next") { step += 1 }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Finish") { finish() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func finish() {
        prefs.didCompleteSetup = true
        // Ensure browse default stays coherent
        if prefs.browseOnOpen {
            prefs.openWindowOnDrop = false
        }
        fskitStatus.enableModule()
        prefs.applyDefaultHandlerClaim()
        prefs.runFinderServiceInstallIfNeeded()
        // Give enable a moment then close
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onFinish()
        }
    }

    private func labelRow(_ system: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: system)
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
