//! PEL-002: Safe extraction policy shared by every adapter.
use crate::{PeelError, Result};
use std::path::{Component, Path, PathBuf};

/// Resource budgets for untrusted archives (spec §7).
#[derive(Debug, Clone)]
pub struct ResourceBudget {
    pub max_entries: u64,
    pub max_total_uncompressed_bytes: u64,
    pub max_single_entry_bytes: u64,
    pub max_path_components: usize,
    pub max_path_bytes: usize,
}

impl Default for ResourceBudget {
    fn default() -> Self {
        Self {
            max_entries: 100_000,
            max_total_uncompressed_bytes: 32 * 1024 * 1024 * 1024, // 32 GiB
            max_single_entry_bytes: 8 * 1024 * 1024 * 1024, // 8 GiB
            max_path_components: 64,
            max_path_bytes: 4096,
        }
    }
}

impl ResourceBudget {
    pub fn check_entry_count(&self, n: u64) -> Result<()> {
        if n > self.max_entries {
            return Err(PeelError::BudgetExceeded(format!(
                "entry count {n} exceeds max {}",
                self.max_entries
            )));
        }
        Ok(())
    }

    pub fn check_entry_size(&self, size: u64) -> Result<()> {
        if size > self.max_single_entry_bytes {
            return Err(PeelError::BudgetExceeded(format!(
                "entry size {size} exceeds max {}",
                self.max_single_entry_bytes
            )));
        }
        Ok(())
    }

    pub fn check_total(&self, total: u64) -> Result<()> {
        if total > self.max_total_uncompressed_bytes {
            return Err(PeelError::BudgetExceeded(format!(
                "total uncompressed {total} exceeds max {}",
                self.max_total_uncompressed_bytes
            )));
        }
        Ok(())
    }
}

/// Normalize an archive entry name into safe relative components.
/// Rejects absolute paths, traversal, nulls, Windows drive letters, UNC, empty.
pub fn sanitize_entry_name(name: &str, budget: &ResourceBudget) -> Result<String> {
    if name.is_empty() {
        return Err(PeelError::PathEscape("empty entry name".into()));
    }
    if name.as_bytes().contains(&0) {
        return Err(PeelError::PathEscape("NUL in entry name".into()));
    }
    if name.len() > budget.max_path_bytes {
        return Err(PeelError::PathEscape(format!(
            "path too long ({} bytes)",
            name.len()
        )));
    }

    // Unify separators
    let unified = name.replace('\\', "/");

    // Strip repeated leading ./ 
    let mut s = unified.as_str();
    while s.starts_with("./") {
        s = &s[2..];
    }

    // Reject absolute / UNC / drive
    if s.starts_with('/') || s.starts_with("//") {
        return Err(PeelError::PathEscape(name.into()));
    }
    // Windows drive "C:/" or "C:"
    if s.len() >= 2 && s.as_bytes()[1] == b':' {
        return Err(PeelError::PathEscape(name.into()));
    }
    if s.starts_with("\\\\") || s.starts_with("//") {
        return Err(PeelError::PathEscape(name.into()));
    }

    let path = Path::new(s);
    let mut parts: Vec<String> = Vec::new();
    for c in path.components() {
        match c {
            Component::Normal(os) => {
                let p = os.to_string_lossy();
                if p.is_empty() || p == "." {
                    continue;
                }
                // Reject Windows device names
                let upper = p.to_ascii_uppercase();
                let device = upper.split('.').next().unwrap_or("");
                if matches!(
                    device,
                    "CON" | "PRN" | "AUX" | "NUL"
                        | "COM1" | "COM2" | "COM3" | "COM4"
                        | "LPT1" | "LPT2" | "LPT3"
                ) {
                    return Err(PeelError::PathEscape(format!(
                        "reserved name: {p}"
                    )));
                }
                parts.push(p.into_owned());
            }
            Component::CurDir => {}
            Component::ParentDir => {
                return Err(PeelError::PathEscape(name.into()));
            }
            Component::RootDir | Component::Prefix(_) => {
                return Err(PeelError::PathEscape(name.into()));
            }
        }
    }
    if parts.is_empty() {
        return Err(PeelError::PathEscape(format!(
            "empty after sanitize: {name}"
        )));
    }
    if parts.len() > budget.max_path_components {
        return Err(PeelError::PathEscape(format!(
            "too many path components in {name}"
        )));
    }
    Ok(parts.join("/"))
}

/// Join sanitized relative name under root; ensure final path stays in root.
pub fn safe_destination(root: &Path, entry_name: &str, budget: &ResourceBudget) -> Result<PathBuf> {
    let rel = sanitize_entry_name(entry_name, budget)?;
    let mut out = root.to_path_buf();
    for part in rel.split('/') {
        out.push(part);
    }

    // Containment check using components relative to root (works even if parents missing)
    let root_abs = if root.exists() {
        root.canonicalize().unwrap_or_else(|_| root.to_path_buf())
    } else {
        root.to_path_buf()
    };

    // Build absolute candidate without requiring existence
    let mut abs = root_abs.clone();
    for part in rel.split('/') {
        abs.push(part);
    }
    // Ensure abs starts with root_abs as path prefix component-wise
    let root_comps: Vec<_> = root_abs.components().collect();
    let abs_comps: Vec<_> = abs.components().collect();
    if abs_comps.len() < root_comps.len()
        || abs_comps
            .iter()
            .zip(root_comps.iter())
            .any(|(a, b)| a != b)
    {
        return Err(PeelError::PathEscape(entry_name.into()));
    }
    Ok(out)
}

/// After an adapter writes freely into `dir`, verify every file is contained.
pub fn assert_tree_contained(root: &Path) -> Result<()> {
    let root_c = root
        .canonicalize()
        .map_err(|e| PeelError::Other(format!("canonicalize root: {e}")))?;
    fn walk(dir: &Path, root_c: &Path) -> Result<()> {
        for entry in std::fs::read_dir(dir)? {
            let entry = entry?;
            let p = entry.path();
            // reject symlinks entirely for v1 safety
            let meta = std::fs::symlink_metadata(&p)?;
            if meta.file_type().is_symlink() {
                return Err(PeelError::UnsafeEntry(format!(
                    "symlink not allowed: {}",
                    p.display()
                )));
            }
            if p.is_dir() {
                let pc = p.canonicalize().map_err(|e| {
                    PeelError::Other(format!("canonicalize {}: {e}", p.display()))
                })?;
                if !pc.starts_with(root_c) {
                    return Err(PeelError::PathEscape(p.display().to_string()));
                }
                walk(&p, root_c)?;
            } else {
                // file may not canonicalize if weird; check parent
                if let Some(parent) = p.parent() {
                    if parent.exists() {
                        let pc = parent.canonicalize().unwrap_or_else(|_| parent.to_path_buf());
                        if !pc.starts_with(root_c) {
                            return Err(PeelError::PathEscape(p.display().to_string()));
                        }
                    }
                }
            }
        }
        Ok(())
    }
    walk(&root_c, &root_c)
}

/// Create a private staging directory under dest parent.
pub fn staging_dir(final_dest: &Path) -> Result<PathBuf> {
    let parent = final_dest
        .parent()
        .unwrap_or_else(|| Path::new("."));
    std::fs::create_dir_all(parent)?;
    let stage = parent.join(format!(
        ".peel-stage-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0)
    ));
    std::fs::create_dir_all(&stage)?;
    Ok(stage)
}

pub fn commit_stage(stage: &Path, final_dest: &Path) -> Result<()> {
    assert_tree_contained(stage)?;
    if final_dest.exists() {
        if final_dest.is_dir() {
            // merge: move children
            for entry in std::fs::read_dir(stage)? {
                let entry = entry?;
                let name = entry.file_name();
                let to = final_dest.join(&name);
                if to.exists() {
                    if to.is_dir() {
                        std::fs::remove_dir_all(&to)?;
                    } else {
                        std::fs::remove_file(&to)?;
                    }
                }
                std::fs::rename(entry.path(), &to).or_else(|_| {
                    // cross-device fallback
                    if entry.path().is_dir() {
                        copy_dir(&entry.path(), &to)?;
                        std::fs::remove_dir_all(entry.path())?;
                    } else {
                        std::fs::copy(entry.path(), &to)?;
                        std::fs::remove_file(entry.path())?;
                    }
                    Ok(()) as Result<()>
                })?;
            }
            let _ = std::fs::remove_dir_all(stage);
        } else {
            return Err(PeelError::Other(format!(
                "destination exists as file: {}",
                final_dest.display()
            )));
        }
    } else {
        std::fs::rename(stage, final_dest).or_else(|_| {
            copy_dir(stage, final_dest)?;
            std::fs::remove_dir_all(stage)?;
            Ok(()) as Result<()>
        })?;
    }
    Ok(())
}

fn copy_dir(src: &Path, dst: &Path) -> Result<()> {
    std::fs::create_dir_all(dst)?;
    for entry in std::fs::read_dir(src)? {
        let entry = entry?;
        let from = entry.path();
        let to = dst.join(entry.file_name());
        if from.is_dir() {
            copy_dir(&from, &to)?;
        } else {
            std::fs::copy(&from, &to)?;
        }
    }
    Ok(())
}
