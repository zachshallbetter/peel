# PEL-002 + RAR verification

**Date:** 2026-10-10T20:29:28.265201+00:00  
**Status:** PASS for current adapters

## cargo test --workspace

| Suite | Result |
| --- | --- |
| peel-core unit | 0 tests (ok) |
| extract_zip | 1 passed |
| safety_and_formats | 8 passed |
| **Total** | **9 passed, 0 failed** |

### safety_and_formats detail
- sanitize_rejects_traversal_and_absolute — PASS
- sanitize_rejects_nul_and_devices — PASS
- zip_extracts_safely — PASS
- zip_slip_is_rejected_or_contained — PASS
- absolute_and_drive_paths_rejected — PASS
- budget_rejects_too_many_entries — PASS
- detect_zip_and_rar_magic — PASS
- rar_list_and_extract_integration — PASS

## CLI smoke (fresh release binary)

### RAR
- Input: Sneakattack - Bound 02 Chapter 01.rar (~107 MB)
- Detect/list/extract: OK
- Output: 27 files under *-peeled folder
- All paths contained under destination

### Zip-slip
- Input: tests/fixtures/zipslip.zip (`../evil.txt`)
- Result: **rejected** — `path escape blocked: ../evil.txt`
- Exit code 1; no write outside dest

## PEL-002 controls

| Control | Status |
| --- | --- |
| Shared path sanitize | yes |
| Reject .. / absolute / C: / \ / NUL / device names | yes |
| safe_destination containment | yes |
| Symlink reject on rar/7z tree walk | yes |
| Entry/size/total budgets | yes (zip preflight + rar/7z list) |
| RAR/7z staging → assert_tree_contained → commit | yes |
| Default collision rename | yes |

## Spec gaps (honest)

- Multipart RAR, encrypted variants, bomb fuzzing: not yet
- DMG/APP/PDF/EXE: handlers exist, not in this suite
- Full transactional atomic commit across all adapters: staging on rar/7z; zip writes direct with sanitize

## Re-run

```bash
cargo test --workspace
cargo build -p peel-cli --release
./target/release/peel extract file.rar --out /tmp/out --enclosing always
```
