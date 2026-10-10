use crate::extract::ArchiveEntry;
use crate::policy::ExtractPolicy;
use crate::safety::{
    assert_tree_contained, sanitize_entry_name, staging_dir,
};
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

/// Public helper: true when path looks like a RAR volume piece.
pub fn is_rar_multipart(path: &Path) -> bool {
    Archive::new(path).is_multipart()
}

/// List every volume path for a multipart RAR (or just the file itself).
pub fn rar_volume_paths(path: &Path) -> Vec<PathBuf> {
    let a = Archive::new(path);
    if a.is_multipart() {
        // Glob expansion via all_parts string pattern — walk directory for matches.
        let first = a.first_part();
        let parent = first.parent().unwrap_or_else(|| Path::new("."));
        let stem = first.file_name().and_then(|s| s.to_str()).unwrap_or("");
        // Collect sibling volumes by probing nth_part
        let mut out = Vec::new();
        // Include first and scan upward until missing
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
            // safety
            if n > 512 {
                break;
            }
        }
        if out.is_empty() {
            out.push(path.to_path_buf());
        }
        let _ = (parent, stem);
        out
    } else {
        vec![path.to_path_buf()]
    }
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

    // Preflight: list + sanitize + budgets
    let entries = list_rar_with_password(&resolved, password)?;
    policy.budget.check_entry_count(entries.len() as u64)?;
    for e in &entries {
        sanitize_entry_name(&e.name, &policy.budget)?;
        if let Some(sz) = e.size {
            policy.budget.check_entry_size(sz)?;
        }
    }

    fs::create_dir_all(dest)?;
    let stage = staging_dir(dest)?;

    // unrar extract_all always dumps full archive; for selection we extract all then filter move
    let archive = open_handle(&resolved, password);
    let open = archive
        .open_for_processing()
        .map_err(|e| PeelError::Rar(e.to_string()))?;
    if let Err(e) = open.extract_all(&stage).map_err(|e| PeelError::Rar(e.to_string())) {
        let _ = fs::remove_dir_all(&stage);
        return Err(e);
    }
    if let Err(e) = assert_tree_contained(&stage) {
        let _ = fs::remove_dir_all(&stage);
        return Err(e);
    }

    // If selection set, prune staged tree
    if policy.selection.as_ref().map(|s| !s.is_empty()).unwrap_or(false) {
        prune_stage_to_selection(&stage, policy)?;
    }

    // Move staged tree into dest
    for entry in fs::read_dir(&stage)? {
        let entry = entry?;
        let to = dest.join(entry.file_name());
        if to.exists() {
            match policy.collision {
                crate::policy::Collision::Skip => {
                    skipped.push(to);
                    continue;
                }
                crate::policy::Collision::Error => {
                    let _ = fs::remove_dir_all(&stage);
                    return Err(PeelError::Collision {
                        path: to,
                        policy: policy.collision,
                    });
                }
                crate::policy::Collision::Rename => {
                    let to = crate::pathutil::unique_path(&to);
                    fs::rename(entry.path(), &to).map_err(PeelError::Io)?;
                }
                crate::policy::Collision::Overwrite => {
                    if to.is_dir() {
                        fs::remove_dir_all(&to)?;
                    } else {
                        fs::remove_file(&to)?;
                    }
                    fs::rename(entry.path(), &to).map_err(PeelError::Io)?;
                }
            }
        } else {
            fs::rename(entry.path(), &to).map_err(PeelError::Io)?;
        }
    }
    let _ = fs::remove_dir_all(&stage);
    collect_tree(dest, extracted)?;
    Ok(())
}

fn prune_stage_to_selection(stage: &Path, policy: &ExtractPolicy) -> Result<()> {
    fn walk(dir: &Path, stage: &Path, policy: &ExtractPolicy) -> Result<()> {
        let entries: Vec<_> = fs::read_dir(dir)?.collect();
        for entry in entries {
            let entry = entry?;
            let p = entry.path();
            let rel = p.strip_prefix(stage).unwrap_or(&p);
            let rel_s = rel.to_string_lossy().replace('\\', "/");
            let meta = fs::symlink_metadata(&p)?;
            if meta.file_type().is_dir() {
                walk(&p, stage, policy)?;
                // remove empty dirs that aren't wanted
                if fs::read_dir(&p)?.next().is_none() && !policy.wants_entry(&rel_s) {
                    let _ = fs::remove_dir(&p);
                }
            } else if !policy.wants_entry(&rel_s) {
                let _ = fs::remove_file(&p);
            }
        }
        Ok(())
    }
    walk(stage, stage, policy)
}

fn collect_tree(root: &Path, out: &mut Vec<PathBuf>) -> Result<()> {
    if !root.exists() {
        return Ok(());
    }
    if root.is_file() {
        out.push(root.to_path_buf());
        return Ok(());
    }
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        let p = entry.path();
        let meta = fs::symlink_metadata(&p)?;
        if meta.file_type().is_symlink() {
            return Err(PeelError::UnsafeEntry(format!(
                "symlink not allowed: {}",
                p.display()
            )));
        }
        if p.is_dir() {
            collect_tree(&p, out)?;
        } else {
            out.push(p);
        }
    }
    Ok(())
}
