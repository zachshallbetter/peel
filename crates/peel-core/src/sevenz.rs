use crate::extract::ArchiveEntry;
use crate::policy::ExtractPolicy;
use crate::safety::{assert_tree_contained, sanitize_entry_name, staging_dir};
use crate::{PeelError, Result};
use sevenz_rust2::{decompress_file, decompress_file_with_password, ArchiveReader, Password};
use std::fs::{self, File};
use std::path::{Path, PathBuf};

pub fn list_7z(path: &Path) -> Result<Vec<ArchiveEntry>> {
    match try_list(path) {
        Ok(v) if !v.is_empty() => {
            let budget = crate::safety::ResourceBudget::default();
            budget.check_entry_count(v.len() as u64)?;
            for e in &v {
                sanitize_entry_name(&e.name, &budget)?;
            }
            Ok(v)
        }
        Ok(_) | Err(_) => Ok(vec![ArchiveEntry {
            name: path
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("archive.7z")
                .to_string(),
            is_dir: false,
            size: path.metadata().ok().map(|m| m.len()),
        }]),
    }
}

fn try_list(path: &Path) -> Result<Vec<ArchiveEntry>> {
    let file = File::open(path)?;
    let reader =
        ArchiveReader::new(file, Password::empty()).map_err(|e| PeelError::SevenZ(e.to_string()))?;
    let mut out = Vec::new();
    let archive = reader.archive();
    for f in &archive.files {
        out.push(ArchiveEntry {
            name: f.name().replace('\\', "/"),
            is_dir: f.is_directory(),
            size: Some(f.size()),
        });
    }
    Ok(out)
}

pub fn extract_7z(
    path: &Path,
    dest: &Path,
    policy: &ExtractPolicy,
    extracted: &mut Vec<PathBuf>,
    skipped: &mut Vec<PathBuf>,
) -> Result<()> {
    let _ = skipped;
    if let Ok(entries) = try_list(path) {
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
    }

    fs::create_dir_all(dest)?;
    let stage = staging_dir(dest)?;
    let res = match &policy.password {
        Some(pw) => decompress_file_with_password(path, &stage, Password::from(pw.as_str())),
        None => decompress_file(path, &stage),
    };
    if let Err(e) = res {
        let _ = fs::remove_dir_all(&stage);
        return Err(PeelError::SevenZ(e.to_string()));
    }
    if let Err(e) = assert_tree_contained(&stage) {
        let _ = fs::remove_dir_all(&stage);
        return Err(e);
    }
    for entry in fs::read_dir(&stage)? {
        let entry = entry?;
        let to = dest.join(entry.file_name());
        if to.exists() && matches!(policy.collision, crate::policy::Collision::Skip) {
            continue;
        }
        if to.exists() && matches!(policy.collision, crate::policy::Collision::Overwrite) {
            if to.is_dir() {
                fs::remove_dir_all(&to)?;
            } else {
                fs::remove_file(&to)?;
            }
        }
        if to.exists() && matches!(policy.collision, crate::policy::Collision::Rename) {
            let to = crate::pathutil::unique_path(&to);
            fs::rename(entry.path(), &to)?;
            continue;
        }
        if to.exists() && matches!(policy.collision, crate::policy::Collision::Error) {
            let _ = fs::remove_dir_all(&stage);
            return Err(PeelError::Collision {
                path: to,
                policy: policy.collision,
            });
        }
        fs::rename(entry.path(), &to)?;
    }
    let _ = fs::remove_dir_all(&stage);
    collect_tree(dest, extracted)?;
    Ok(())
}

fn collect_tree(root: &Path, out: &mut Vec<PathBuf>) -> Result<()> {
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
