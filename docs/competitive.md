# Peel — Competitive Positioning

**How Peel can differentiate itself from The Unarchiver and 7-Zip**  
**Status:** Product direction and proposed capabilities, not verified implementation claims.

## Executive summary

Peel is not automatically better than The Unarchiver or 7-Zip today. The opportunity is to combine straightforward extraction, powerful archive management, and a more general **file-container utility**: one that can recognize, inspect, browse, preview, create, and transform supported archives, application packages, disk images, and related containers.

The goal is not simply to support more formats. It is to make supported containers behave as naturally as folders, with safe defaults and advanced operations when needed.

## 1. Competitive landscape

| Capability | The Unarchiver | 7-Zip | Peel target |
|---|---|---|---|
| macOS experience | Native, extraction-focused | Limited native desktop experience | Native |
| Windows | No official desktop app | Strong support | Native |
| Linux | No official desktop app | Supported | Native |
| Common archive extraction | Strong | Strong | Strong |
| Archive creation | Not its main purpose | Strong | Full-featured |
| Advanced compression | Limited | Strong | Full-featured |
| Browse archive contents | Limited | Yes | Rich browser |
| Edit archives | Not a focus | Format-dependent | Format-dependent |
| Batch operations | Limited | Yes | Integrated workflows |
| Archive conversion | Not a focus | Possible via workflows | Built-in |
| Nested archive navigation | Limited | Some support | Seamless where feasible |
| Application package inspection | Limited | Some formats | Context-aware |
| Disk image inspection | Limited | Some formats | Context-aware |
| Rich file previews | Limited | Limited | Integrated |
| CLI | Separate underlying tools | Yes | First-class |
| Reusable engine / SDK | Not a primary offering | Components available, licensing varies | Peel Core; commercial offering planned |

*This is a high-level positioning comparison, not an audited compatibility matrix or performance benchmark. Features in the Peel column are targets, not necessarily implemented.*

7-Zip already has mature compression technology and broad format support. Peel should not claim better compression algorithms without comparative evidence.

## 2. Five potential differentiators

### A. Universal container intelligence

Peel should identify a file's underlying structure, not rely only on its extension, and expose appropriate operations for that structure.

Examples:

- `application.exe`: inspect embedded resources or installer payloads when the executable format permits; do not execute it merely to inspect it.
- `installer.dmg`: inspect disk-image metadata and contents through supported platform-specific mechanisms.
- `application.app`: browse the bundle, executable, frameworks, resources, and relevant metadata.
- `comic.cbz`: display pages in reading order.
- `document.docx`: recognize the underlying ZIP-based package and its contents.
- `package.deb`: inspect package metadata and payload.
- `game.pak`: recognize and inspect supported variants; the extension alone does not imply a single universal format.

**Differentiator:** Peel understands what a supported container represents, not only how it is compressed.

### B. Browse without full extraction

A user opening a large archive should be able to navigate a directory tree, search filenames, preview supported content, and selectively extract files without first unpacking everything when the format permits.

7-Zip already supports browsing and selective extraction. Peel's improvement would be a more cohesive native experience with rich previews, search, and nested navigation.

Random access varies by format; solid and encrypted archives may require substantial decompression.

### C. Intelligent extraction

Default behavior should reduce repetitive decisions:

- Choose sensible folder placement based on archive structure and user preferences.
- Recognize multipart archives.
- Handle filename collisions explicitly and safely.
- Preserve supported timestamps, permissions, and metadata.
- Warn about unsafe paths, decompression bombs, and suspicious payloads.
- Make failures and partial results visible.

**Ideal everyday flow:** Double-click → Peel → Done.

### D. Cross-platform consistency

Use a shared Rust engine across macOS, Windows, and Linux while keeping each desktop UI and file-manager integration native to its platform.

The same core operation should produce equivalent results and consistent error reporting, subject to filesystem and platform differences.

### E. Programmable engine

Expose the same core through the desktop application, CLI, and SDK.

Illustrative commands (proposed syntax):

```bash
peel inspect installer.exe
peel extract archive.7z --only "*.png"
peel convert files.rar files.zip
peel verify backup.tar.zst
```

This supports developer workflows, build pipelines, digital asset processing, and commercial embedding. SDK redistribution rights depend on the licenses of underlying components.

## 3. Why users would switch

Supporting more formats is insufficient on its own. Prioritize:

1. **Speed:** Fast startup, immediate recognition, low memory overhead, and competitive extraction throughput—measured, not assumed.
2. **Simplicity:** Minimal prompts, sensible destinations, clear progress, and predictable results.
3. **Capability:** Advanced inspection, selective extraction, conversion, and batch workflows when needed.

The everyday interface should remain small and unobtrusive; advanced functionality should not complicate basic extraction.

## 4. Signature feature: Treat archives like folders

Peel's advanced interface should navigate nested containers as if they were directories:

```text
Downloads
└── Project_Backup.7z
    ├── Documents
    │   ├── Contract.pdf
    │   └── Proposal.docx
    ├── Images
    │   ├── Logo.png
    │   └── Screenshots.zip
    │       ├── Screen_01.png
    │       └── Screen_02.png
    └── Source
        └── application.exe
```

Potential operations:

- Browse and search without extracting the whole archive where possible.
- Preview individual supported files.
- Open nested archives in place where technically feasible.
- Extract selected files and directories.
- Inspect metadata, checksums, and format-specific structure.
- Safely stage writes when modifying formats that support updates.

**Engineering caveat:** This is a unified interaction model, not a promise of uniform random access. Some formats need indexing, temporary staging, or sequential decompression; others may not support safe modification at all.

## 5. Proposed engineering targets

| Metric | Initial target |
|---|---|
| Common extraction | Match or exceed established tools on representative benchmark sets |
| Startup responsiveness | Usable main interface within 300 ms on specified reference hardware |
| Archive browsing | Show initial metadata without full extraction where supported |
| Format intelligence | Identify underlying structures independently of file extensions |
| Cross-platform behavior | Equivalent core results and error semantics on macOS, Windows, and Linux |

These are goals requiring measured acceptance tests, not current performance claims.

## 6. Positioning

- **The Unarchiver:** Primarily an extraction utility.
- **7-Zip:** A mature, powerful archive manager and compression tool.
- **Peel:** A proposed universal file-container utility, pairing simple extraction with native browsing, inspection, conversion, and automation.

### Product promise

> Open what's inside.

The strongest positioning is not “7-Zip with a prettier interface.” It is an application that treats supported archives, installers, disk images, and packages as inspectable containers with operations suited to each format.

## Finder-native access as a differentiator

The macOS target includes archive-level Quick Look previews, on-demand opening of selected entries, and optional read-only Finder mounts. These are distinct capabilities: Quick Look does not itself turn an archive into a folder, and a mount requires a separately qualified filesystem backend. The fallback is the native Peel browser. Position this as progressive integration, not already shipped support. See `finder-quicklook.md`.


## 7. What is still missing

The visual identity, compact extraction progress window, and completion state are taking shape. They do not, by themselves, establish a functional advantage.

The next major product design deliverable should be the **Peel Container Browser**:

- A native Finder/Explorer-like hierarchy.
- Format-aware details and previews.
- Nested container navigation.
- Selective extraction and safe batch operations.
- Clear capability indicators for unsupported, encrypted, or read-only containers.

**Recommended priority:** Prove this interaction model on a small set of representative containers before scaling the format matrix. Benchmark the implementation against existing tools and distinguish demonstrated advantages from roadmap aspirations.

## Unified identity and commercial positioning (2026-10-10)

Peel remains **one product**, not separately branded extraction, exploration or protection applications. Finder-native Quick Look and normal encrypted-archive workflows belong in the free core. A proposed Peel Pro entitlement monetizes specialized forgotten-access recovery, with a free feasibility preflight and no success guarantees. The one-time US$29–49 price range is an unvalidated hypothesis. See `PEEL_PRODUCT_IDENTITY_AND_MONETIZATION_v0.1.md`.
