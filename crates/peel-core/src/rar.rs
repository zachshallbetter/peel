use crate::extract::ArchiveEntry;
use crate::policy::ExtractPolicy;
use crate::safety::{safe_destination, sanitize_entry_name};
use crate::{PeelError, Result};
use std::fs;
use std::path::{Path, PathBuf};
use unrar_ng::Archive;

/// Build an Archive handle, resolving multi-volume sets to the first part.
fn open_handle<'a>(path: &'a Path, password: Option<&'a str>) -> Archive<'a> {
    let archive = match password {
        Some(pw) => Archive::with_password(path, pw),
        None => Archive::new(path),
    };
    if archive.is_multipart() {
        archive.as_first_part()
    } else {
        archive
    }
}

/// Public helper: true when path is (or belongs to) a multi-volume RAR set.
pub fn is_rar_multipart(path: &Path) -> bool {
    if Archive::new(path).is_multipart() {
        return true;
    }
    // Classic naming: name.rar + name.r00, name.r01, … (unrar may not flag .rar alone).
    classic_rar_volumes(path).len() > 1
}

/// List every volume path for a multipart RAR (or just the file itself).
pub fn rar_volume_paths(path: &Path) -> Vec<PathBuf> {
    let a = Archive::new(path);
    if a.is_multipart() {
        let first = a.first_part();
        let mut out = Vec::new();
        for n in 1..10_000 {
            if let Some(p) = a.nth_part(n) {
                if p.exists() {
                    out.push(p);
                } else if n > 1 {
                    break;
                }
            } else {
                break;
            }
            if n > 512 {
                break;
            }
        }
        if out.is_empty() {
            out.push(path.to_path_buf());
        }
        // Prefer ordered unique list; include first if missing.
        if !out.iter().any(|p| p == &first) && first.exists() {
            out.insert(0, first);
        }
        // Merge classic .rar/.rXX siblings (unrar nth_part often omits .rar when opened via .r00).
        for p in classic_rar_volumes(path) {
            if !out.iter().any(|e| e == &p) {
                out.push(p);
            }
        }
        out.sort();
        // Re-order: .rar first, then .r00 ascending, then partN.
        out.sort_by(|a, b| volume_sort_key(a).cmp(&volume_sort_key(b)));
        return out;
    }

    let classic = classic_rar_volumes(path);
    if classic.len() > 1 {
        return classic;
    }
    vec![path.to_path_buf()]
}

/// Classic multi-volume layout on disk: `stem.rar` + `stem.r00`…`stem.rNN` or `stem.part1.rar`…
fn classic_rar_volumes(path: &Path) -> Vec<PathBuf> {
    let parent = match path.parent() {
        Some(p) => p,
        None => return vec![path.to_path_buf()],
    };
    let name = match path.file_name().and_then(|s| s.to_str()) {
        Some(n) => n,
        None => return vec![path.to_path_buf()],
    };
    let lower = name.to_ascii_lowercase();

    // partN.rar style
    if let Some(stem) = strip_part_rar(&lower) {
        let mut parts: Vec<(u32, PathBuf)> = Vec::new();
        if let Ok(rd) = fs::read_dir(parent) {
            for ent in rd.flatten() {
                let fn_ = ent.file_name();
                let s = fn_.to_string_lossy();
                let sl = s.to_ascii_lowercase();
                if let Some(n) = parse_part_index(&sl, stem) {
                    parts.push((n, ent.path()));
                }
            }
        }
        parts.sort_by_key(|(n, _)| *n);
        let out: Vec<_> = parts.into_iter().map(|(_, p)| p).collect();
        if out.len() > 1 {
            return out;
        }
    }

    // stem.rar + stem.r00 style
    let stem = if lower.ends_with(".rar") {
        &name[..name.len() - 4]
    } else if let Some(rest) = strip_rxx(&lower) {
        // opened a .r00 — stem is before .rNN
        let original = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or(name);
        // file_stem of file.r00 is file.r00 on some systems? actually stem is file for .r00? 
        // On Unix, Path::file_stem for "a.r00" is "a" — wrong. Use strip_rxx on full name.
        let _ = original;
        rest
    } else {
        return vec![path.to_path_buf()];
    };

    // Re-derive stem from original casing of the path when possible.
    let stem_os = if lower.ends_with(".rar") {
        &name[..name.len() - 4]
    } else if let Some(idx) = lower.rfind(".r") {
        // .r00 / .r12
        if lower.len() >= idx + 4
            && lower.as_bytes()[idx + 2].is_ascii_digit()
            && lower.as_bytes()[idx + 3].is_ascii_digit()
            && (lower.len() == idx + 4)
        {
            &name[..idx]
        } else {
            return vec![path.to_path_buf()];
        }
    } else {
        return vec![path.to_path_buf()];
    };

    let mut out = Vec::new();
    let rar = parent.join(format!("{stem_os}.rar"));
    if rar.exists() {
        out.push(rar);
    }
    for n in 0..512u32 {
        let p = parent.join(format!("{stem_os}.r{n:02}"));
        if p.exists() {
            out.push(p);
        } else if n > 0 && !out.is_empty() {
            // allow missing .r00 only if we already have .rar; stop after first gap past r00
            if n >= 1 {
                break;
            }
        } else if n > 0 {
            break;
        }
    }
    if out.is_empty() {
        out.push(path.to_path_buf());
    }
    let _ = stem;
    out
}

fn strip_part_rar(lower: &str) -> Option<&str> {
    // foo.part01.rar / foo.part1.rar
    if !lower.ends_with(".rar") {
        return None;
    }
    let base = &lower[..lower.len() - 4];
    if let Some(idx) = base.rfind(".part") {
        let rest = &base[idx + 5..];
        if !rest.is_empty() && rest.chars().all(|c| c.is_ascii_digit()) {
            return Some(&base[..idx]);
        }
    }
    None
}

fn parse_part_index(lower_name: &str, stem: &str) -> Option<u32> {
    if !lower_name.starts_with(stem) {
        return None;
    }
    let rest = &lower_name[stem.len()..];
    // .partN.rar
    if let Some(r) = rest.strip_prefix(".part") {
        let num = r.strip_suffix(".rar")?;
        return num.parse().ok();
    }
    None
}

fn volume_sort_key(path: &Path) -> (u8, u32, String) {
    let name = path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();
    if name.ends_with(".rar") && !name.contains(".part") {
        return (0, 0, name);
    }
    if let Some(stem) = name.strip_suffix(".rar") {
        if let Some(rest) = stem.rsplit_once(".part") {
            if let Ok(n) = rest.1.parse::<u32>() {
                return (1, n, name);
            }
        }
    }
    if name.len() >= 4 {
        let b = name.as_bytes();
        let n = b.len();
        if b[n - 4] == b'.'
            && b[n - 3] == b'r'
            && b[n - 2].is_ascii_digit()
            && b[n - 1].is_ascii_digit()
        {
            let idx = (b[n - 2] - b'0') as u32 * 10 + (b[n - 1] - b'0') as u32;
            return (2, idx, name);
        }
    }
    (9, 0, name)
}

fn strip_rxx(lower: &str) -> Option<&str> {
    // name.r00
    if lower.len() < 5 {
        return None;
    }
    let bytes = lower.as_bytes();
    let n = bytes.len();
    if bytes[n - 4] == b'.'
        && bytes[n - 3] == b'r'
        && bytes[n - 2].is_ascii_digit()
        && bytes[n - 1].is_ascii_digit()
    {
        return Some(&lower[..n - 4]);
    }
    None
}

pub fn list_rar(path: &Path) -> Result<Vec<ArchiveEntry>> {
    list_rar_with_password(path, None)
}

pub fn list_rar_with_password(path: &Path, password: Option<&str>) -> Result<Vec<ArchiveEntry>> {
    // Keep path alive for Archive lifetime
    let path_buf = if Archive::new(path).is_multipart() {
        Archive::new(path).first_part()
    } else {
        path.to_path_buf()
    };
    let archive = open_handle(&path_buf, password);
    let mut listing = archive
        .open_for_listing()
        .map_err(|e| PeelError::Rar(e.to_string()))?;
    let mut out = Vec::new();
    loop {
        match listing.read_header() {
            Ok(Some(header)) => {
                let e = header.entry();
                let name = e.filename.to_string_lossy().replace('\\', "/");
                let _ = sanitize_entry_name(&name, &crate::safety::ResourceBudget::default())?;
                out.push(ArchiveEntry {
                    name,
                    is_dir: e.is_directory(),
                    size: Some(e.unpacked_size),
                });
                listing = header.skip().map_err(|e| PeelError::Rar(e.to_string()))?;
            }
            Ok(None) => break,
            Err(e) => return Err(PeelError::Rar(e.to_string())),
        }
    }
    policy_budget_list(&out, &crate::safety::ResourceBudget::default())?;
    Ok(out)
}

fn policy_budget_list(entries: &[ArchiveEntry], budget: &crate::safety::ResourceBudget) -> Result<()> {
    budget.check_entry_count(entries.len() as u64)?;
    let mut total = 0u64;
    for e in entries {
        if let Some(sz) = e.size {
            budget.check_entry_size(sz)?;
            total = total.saturating_add(sz);
        }
    }
    budget.check_total(total)?;
    Ok(())
}

pub fn extract_rar(
    path: &Path,
    dest: &Path,
    policy: &ExtractPolicy,
    extracted: &mut Vec<PathBuf>,
    skipped: &mut Vec<PathBuf>,
) -> Result<()> {
    let password = policy.password.as_deref();
    // Resolve multipart to first volume path (owned)
    let resolved = if Archive::new(path).is_multipart() {
        Archive::new(path).first_part()
    } else {
        path.to_path_buf()
    };

    // Preflight: list + sanitize + budgets (once — callers should not re-list unnecessarily).
    let entries = list_rar_with_password(&resolved, password)?;
    policy.budget.check_entry_count(entries.len() as u64)?;
    let mut total = 0u64;
    for e in &entries {
        sanitize_entry_name(&e.name, &policy.budget)?;
        if let Some(sz) = e.size {
            policy.budget.check_entry_size(sz)?;
            total = total.saturating_add(sz);
        }
    }
    policy.budget.check_total(total)?;

    fs::create_dir_all(dest)?;

    // Stream each entry straight into dest (no full-archive staging).
    // extract_all + rename doubled disk use and looked "stuck" on multi-GB RARs.
    let archive = open_handle(&resolved, password);
    let mut cursor = archive
        .open_for_processing()
        .map_err(|e| PeelError::Rar(e.to_string()))?;

    loop {
        let header = match cursor.read_header() {
            Ok(Some(h)) => h,
            Ok(None) => break,
            Err(e) => return Err(PeelError::Rar(e.to_string())),
        };
        let entry = header.entry();
        let name = entry.filename.to_string_lossy().replace('\\', "/");
        if !policy.wants_entry(&name) {
            cursor = header.skip().map_err(|e| PeelError::Rar(e.to_string()))?;
            continue;
        }

        let out_path = safe_destination(dest, &name, &policy.budget)?;

        if entry.is_directory() {
            fs::create_dir_all(&out_path)?;
            extracted.push(out_path);
            cursor = header.skip().map_err(|e| PeelError::Rar(e.to_string()))?;
            continue;
        }

        if let Some(parent) = out_path.parent() {
            fs::create_dir_all(parent)?;
        }

        let target = match policy.collision {
            crate::policy::Collision::Skip if out_path.exists() => {
                skipped.push(out_path);
                cursor = header.skip().map_err(|e| PeelError::Rar(e.to_string()))?;
                continue;
            }
            crate::policy::Collision::Error if out_path.exists() => {
                return Err(PeelError::Collision {
                    path: out_path,
                    policy: policy.collision,
                });
            }
            crate::policy::Collision::Rename if out_path.exists() => {
                crate::pathutil::unique_path(&out_path)
            }
            crate::policy::Collision::Overwrite if out_path.exists() => {
                if out_path.is_dir() {
                    fs::remove_dir_all(&out_path)?;
                } else {
                    let _ = fs::remove_file(&out_path);
                }
                out_path.clone()
            }
            _ => out_path.clone(),
        };

        cursor = header
            .extract_to(&target)
            .map_err(|e| PeelError::Rar(e.to_string()))?;
        // Reject symlink outputs (unrar shouldn't create them for normal files).
        if let Ok(meta) = fs::symlink_metadata(&target) {
            if meta.file_type().is_symlink() {
                let _ = fs::remove_file(&target);
                return Err(PeelError::UnsafeEntry(format!(
                    "symlink not allowed: {}",
                    target.display()
                )));
            }
        }
        extracted.push(target);
    }

    Ok(())
}
