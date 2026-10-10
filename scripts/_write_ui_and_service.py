#!/usr/bin/env python3
"""Write Peel glass UI + Finder helpers without shell heredocs."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def w(rel: str, text: str, mode=None) -> None:
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    if mode is not None:
        path.chmod(mode)
    print("wrote", path)


w(
    "app/Peel/ContentView.swift",
    r"""import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.14, blue: 0.20),
                    Color(red: 0.08, green: 0.09, blue: 0.12),
                    Color(red: 0.14, green: 0.12, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                header
                dropZone
                controls
                footer
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 440)
        .onAppear { appState.consumePendingOpens() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Peel")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Peel any archive into a folder")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            if appState.isWorking {
                ProgressView()
                    .tint(.white)
            }
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.ultraThinMaterial)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(appState.isTargeted ? 0.14 : 0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(appState.isTargeted ? 0.55 : 0.28),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: appState.isTargeted ? 1.5 : 1
                    )
            }
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            .overlay {
                VStack(spacing: 14) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(appState.status)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    if let detail = appState.detail {
                        Text(detail)
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(4)
                            .padding(.horizontal, 28)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDrop(of: [UTType.fileURL], isTargeted: $appState.isTargeted) { providers in
                appState.handleDrop(providers: providers)
            }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            glassButton("Open…", systemImage: "folder") { appState.pickArchive() }
            glassButton(appState.chooseFolderLabel, systemImage: "folder.badge.plus") {
                appState.pickDestination()
            }
            if appState.lastOutputFolder != nil {
                glassButton("Show", systemImage: "eye") { appState.revealOutput() }
            }
            Spacer()
            Toggle(isOn: $appState.peelBesideSource) {
                Text("Beside source")
            }
            .labelsHidden()
            .toggleStyle(.switch)
            Text(appState.peelBesideSource ? "Beside file" : "Choose folder")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func glassButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
        .foregroundStyle(.white.opacity(0.9))
    }

    private var footer: some View {
        HStack {
            Text(appState.engineLabel)
                .font(.caption2.monospaced())
                .foregroundStyle(.white.opacity(0.35))
            Spacer()
            Text("zip · rar · 7z · tar · dmg · app · pdf · exe")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

#Preview {
    ContentView().environmentObject(AppState())
}
""",
)

w(
    "app/Peel/AppState.swift",
    r"""import SwiftUI
import UniformTypeIdentifiers
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var status = "Drop zip, rar, 7z, dmg, app, pdf…"
    @Published var detail: String?
    @Published var isWorking = false
    @Published var isTargeted = false
    @Published var lastOutputFolder: URL?
    @Published var engineLabel = "Engine: …"
    @Published var peelBesideSource = true
    @Published var fixedDestination: URL?

    private var pending: [URL] = []

    var chooseFolderLabel: String {
        if let fixedDestination {
            return fixedDestination.lastPathComponent
        }
        return "Peel to…"
    }

    init() {
        refreshEngineLabel()
    }

    func refreshEngineLabel() {
        if PeelExtractor.engineURL() != nil {
            engineLabel = "Native engine · peel"
        } else {
            engineLabel = "Engine: missing"
        }
    }

    func enqueueOpen(_ url: URL) {
        pending.append(url)
        consumePendingOpens()
    }

    func consumePendingOpens() {
        guard !pending.isEmpty, !isWorking else { return }
        extract(archive: pending.removeFirst())
    }

    private static let archiveTypes: [UTType] = {
        var types: [UTType] = [.zip]
        for ext in ["rar", "7z", "tar", "gz", "tgz", "tbz2", "bz2", "dmg", "pdf", "exe", "app"] {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        return types
    }()

    func pickArchive() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.archiveTypes
        panel.message = "Choose items to peel into a folder"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            extract(archive: url)
        }
    }

    func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Peel Here"
        panel.message = "Contents go into a new folder inside this location"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fixedDestination = url
        peelBesideSource = false
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
            guard let url else { return }
            Task { @MainActor in self?.extract(archive: url) }
        }
        return true
    }

    func revealOutput() {
        guard let folder = lastOutputFolder else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    func extract(archive: URL) {
        guard !isWorking else {
            pending.append(archive)
            return
        }
        isWorking = true
        status = "Peeling \(archive.lastPathComponent)…"
        detail = archive.path
        refreshEngineLabel()

        let dest: URL? = peelBesideSource ? nil : fixedDestination
        let scoped = archive.startAccessingSecurityScopedResource()
        Task.detached(priority: .userInitiated) {
            let result: Result<String, Error>
            do {
                let json = try PeelExtractor.extract(archive: archive, to: dest)
                result = .success(json)
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                if scoped { archive.stopAccessingSecurityScopedResource() }
                self.isWorking = false
                switch result {
                case .success(let json):
                    self.status = "Peeled \(archive.lastPathComponent)"
                    self.detail = Self.summarize(json)
                    self.lastOutputFolder = PeelExtractor.defaultDestination(for: archive)
                    if let data = json.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let d = obj["destination"] as? String {
                        self.lastOutputFolder = URL(fileURLWithPath: d)
                    }
                case .failure(let error):
                    self.status = "Failed"
                    self.detail = error.localizedDescription
                }
                self.consumePendingOpens()
            }
        }
    }

    private static func summarize(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return json
        }
        let format = obj["format"] as? String ?? "?"
        let dest = obj["destination"] as? String ?? ""
        let n = (obj["extracted"] as? [Any])?.count ?? 0
        return "\(format) · \(n) items\n\(dest)"
    }
}
""",
)

w(
    "mac/peel-here.sh",
    """#!/bin/bash
set -euo pipefail
ENGINE="/Applications/Peel.app/Contents/Helpers/peel"
if [[ ! -x "$ENGINE" ]]; then
  ENGINE="$HOME/Projects/peel/target/release/peel"
fi
if [[ ! -x "$ENGINE" ]]; then
  osascript -e 'display notification "Install Peel.app first." with title "Peel"' >&2
  exit 1
fi
for f in "$@"; do
  dir=$(dirname "$f")
  "$ENGINE" extract "$f" --out "$dir" --collision overwrite --enclosing always || true
done
osascript -e 'display notification "Finished peeling." with title "Peel"' || true
""",
    mode=0o755,
)

w(
    "mac/README-CONTEXT-MENU.md",
    """# Finder / context menu

## Built-in
Right-click an archive → **Open With → Peel**

## Peel Here (beside the file)
```bash
./scripts/install-finder-service.sh
```
Then enable under:
**System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders → Peel Here**

Or drop files on `mac/Peel Here.app` after install.

## Windows (planned)
`HKEY_CLASSES_ROOT\\*\\shell\\Peel` → `peel.exe extract "%1" --enclosing always`
""",
)

w(
    "scripts/install-finder-service.sh",
    r"""#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
chmod +x "$ROOT/mac/peel-here.sh"
SERVICES="${HOME}/Library/Services"
mkdir -p "$SERVICES"

# AppleScript droplet service app
TMP_SCRIPT="$(mktemp).applescript"
cat > "$TMP_SCRIPT" <<'APPLESCRIPT'
on open droppedItems
  set peelEngine to "/Applications/Peel.app/Contents/Helpers/peel"
  repeat with f in droppedItems
    set p to POSIX path of f
    try
      do shell script quoted form of peelEngine & " extract " & quoted form of p & " --collision overwrite --enclosing always"
    end try
  end repeat
  display notification "Finished peeling." with title "Peel"
end open

on run
  display dialog "Drop files on Peel Here, or use Open With → Peel." buttons {"OK"} default button 1
end run
APPLESCRIPT

OUT_APP="${SERVICES}/Peel Here.app"
rm -rf "$OUT_APP"
osacompile -o "$OUT_APP" "$TMP_SCRIPT"
rm -f "$TMP_SCRIPT"

# Also expose shell helper for Automator users
cp -f "$ROOT/mac/peel-here.sh" "${SERVICES}/peel-here.sh"
chmod +x "${SERVICES}/peel-here.sh"

echo "Installed: $OUT_APP"
echo "Enable Services if needed: System Settings → Keyboard → Keyboard Shortcuts → Services"
echo "Right-click archives → Open With → Peel also works via document types."
""",
    mode=0o755,
)

w(
    "README.md",
    """# Peel

**Single installable macOS app** — Swift glass UI + **native Rust** extraction engine.

No Unarchiver / `unar` / XADMaster dependency. Peel rebuilds that capability.

## Formats (native)

| Format | Engine |
| --- | --- |
| zip | peel-core |
| tar / tar.gz / tar.bz2 / gz | peel-core |
| **rar** | unrar-ng (native lib) |
| **7z** | sevenz-rust2 (pure Rust) |
| dmg | hdiutil + copy (macOS) |
| .app | package expand |
| pdf / exe | staged peel folder |

Everything peels **into a folder** (`*-peeled` beside the source by default).

## Install

```bash
cd ~/Projects/peel
./scripts/install-app.sh          # → /Applications/Peel.app
./scripts/install-finder-service.sh
open -a Peel
```

## Use

- Drop archives on the glass window
- **Open…** / **Peel to…**
- Finder: **Open With → Peel**
- Optional: **Peel Here** service / droplet

## Develop

```bash
export PATH="$HOME/.cargo/bin:$PATH"
cargo test -p peel-core
cargo build -p peel-cli --release
./scripts/build-app.sh
```

## Windows

Planned: same Rust CLI + Explorer context menu. macOS app is the product focus today.
""",
)

print("done")
