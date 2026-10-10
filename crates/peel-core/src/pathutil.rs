use crate::safety::{safe_destination, ResourceBudget};
use crate::Result;
use std::path::{Path, PathBuf};

pub fn safe_join(root: &Path, name: &str) -> Result<PathBuf> {
    safe_destination(root, name, &ResourceBudget::default())
}

pub fn unique_path(path: &Path) -> PathBuf {
    if !path.exists() {
        return path.to_path_buf();
    }
    let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("file");
    let ext = path.extension().and_then(|s| s.to_str());
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    for i in 1..10_000 {
        let name = match ext {
            Some(e) => format!("{stem}-{i}.{e}"),
            None => format!("{stem}-{i}"),
        };
        let candidate = parent.join(name);
        if !candidate.exists() {
            return candidate;
        }
    }
    path.to_path_buf()
}

pub fn default_peel_folder(archive: &Path, base: &Path) -> PathBuf {
    let stem = archive
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("peeled");
    let stem = stem
        .strip_suffix(".tar")
        .or_else(|| stem.strip_suffix(".app"))
        .unwrap_or(stem);
    // If destination already exists and is non-empty, create a fresh unique folder
    // so re-extract doesn't flood "-1" collision renames inside the same tree.
    let candidate = base.join(format!("{stem}-peeled"));
    if candidate.exists() {
        unique_path(&candidate)
    } else {
        candidate
    }
}
