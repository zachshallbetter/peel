//! Non-classic-archive peel targets: DMG, .app, PDF, EXE.
use crate::extract::ArchiveEntry;
use crate::pathutil::unique_path;
use crate::policy::{Collision, ExtractPolicy};
use crate::{PeelError, Result};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn list_app(path: &Path) -> Result<Vec<ArchiveEntry>> {
    Ok(vec![ArchiveEntry {
        name: path
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("App.app")
            .to_string(),
        is_dir: true,
        size: None,
    }])
}

/// Expand a .app bundle (or any directory package) into dest as a full tree copy.
pub fn extract_app(
    path: &Path,
    dest: &Path,
    policy: &ExtractPolicy,
    extracted: &mut Vec<PathBuf>,
    skipped: &mut Vec<PathBuf>,
) -> Result<()> {
    let name = path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("App.app");
    let target = dest.join(name);
    let target = match apply_collision(&target, policy.collision)? {
        None => {
            skipped.push(target);
            return Ok(());
        }
        Some(t) => t,
    };
    copy_recursive(path, &target)?;
    extracted.push(target);
    Ok(())
}

/// Mount DMG with hdiutil (macOS system API, not Unarchiver), copy contents, detach.
pub fn extract_dmg(
    path: &Path,
    dest: &Path,
    policy: &ExtractPolicy,
    extracted: &mut Vec<PathBuf>,
    skipped: &mut Vec<PathBuf>,
) -> Result<()> {
    #[cfg(not(target_os = "macos"))]
    {
        let _ = (path, dest, policy, extracted, skipped);
        return Err(PeelError::Unsupported(
            "DMG peeling requires macOS".into(),
        ));
    }
    #[cfg(target_os = "macos")]
    {
        fs::create_dir_all(dest)?;
        let mount_root = tempfile_mount_dir()?;
        let output = Command::new("hdiutil")
            .args([
                "attach",
                "-nobrowse",
                "-readonly",
                "-mountpoint",
                mount_root.to_str().unwrap(),
                path.to_str().unwrap(),
            ])
            .output()
            .map_err(|e| PeelError::Other(format!("hdiutil attach failed: {e}")))?;
        if !output.status.success() {
            let err = String::from_utf8_lossy(&output.stderr);
            return Err(PeelError::Other(format!("hdiutil attach: {err}")));
        }
        let result = (|| {
            let volume_name = path
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("dmg");
            let target = dest.join(format!("{volume_name}-contents"));
            let target = match apply_collision(&target, policy.collision)? {
                None => {
                    skipped.push(target);
                    return Ok(());
                }
                Some(t) => t,
            };
            copy_recursive(&mount_root, &target)?;
            extracted.push(target);
            Ok(())
        })();
        let _ = Command::new("hdiutil")
            .args(["detach", mount_root.to_str().unwrap(), "-quiet"])
            .status();
        let _ = fs::remove_dir_all(&mount_root);
        result
    }
}

fn tempfile_mount_dir() -> Result<PathBuf> {
    let base = std::env::temp_dir().join(format!("peel-dmg-{}", std::process::id()));
    fs::create_dir_all(&base)?;
    Ok(base)
}

/// PDF "peel": copy the PDF and write a sidecar note; embedded file extraction can grow later.
pub fn extract_pdf(
    path: &Path,
    dest: &Path,
    policy: &ExtractPolicy,
    extracted: &mut Vec<PathBuf>,
    _skipped: &mut Vec<PathBuf>,
) -> Result<()> {
    fs::create_dir_all(dest)?;
    let name = path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("document.pdf");
    let target = dest.join(name);
    let target = match apply_collision(&target, policy.collision)? {
        None => return Ok(()),
        Some(t) => t,
    };
    fs::copy(path, &target)?;
    let note = dest.join("PEEL-README.txt");
    fs::write(
        &note,
        format!(
            "Peeled PDF: {name}\n\n\
             Peel copied this PDF into a folder. Embedded attachment extraction is planned.\n\
             Source: {}\n",
            path.display()
        ),
    )?;
    extracted.push(target);
    extracted.push(note);
    Ok(())
}

/// EXE/Mach-O peel: place binary in a folder with a short note (inspection staging).
pub fn extract_exe(
    path: &Path,
    dest: &Path,
    policy: &ExtractPolicy,
    extracted: &mut Vec<PathBuf>,
    _skipped: &mut Vec<PathBuf>,
) -> Result<()> {
    fs::create_dir_all(dest)?;
    let name = path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("binary");
    let target = dest.join(name);
    let target = match apply_collision(&target, policy.collision)? {
        None => return Ok(()),
        Some(t) => t,
    };
    fs::copy(path, &target)?;
    let note = dest.join("PEEL-README.txt");
    fs::write(
        &note,
        format!(
            "Peeled executable: {name}\nSource: {}\n\n\
             This is a staging folder for inspection — not a full reverse-engineering unpack.\n",
            path.display()
        ),
    )?;
    extracted.push(target);
    extracted.push(note);
    Ok(())
}

fn copy_recursive(src: &Path, dst: &Path) -> Result<()> {
    if src.is_file() {
        if let Some(parent) = dst.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::copy(src, dst)?;
        return Ok(());
    }
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let from = entry.path();
        let to = dst.join(entry.file_name());
        if from.is_dir() {
            copy_recursive(&from, &to)?;
        } else {
            if let Some(parent) = to.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::copy(&from, &to)?;
        }
    }
    Ok(())
}

fn apply_collision(path: &Path, policy: Collision) -> Result<Option<PathBuf>> {
    if !path.exists() {
        return Ok(Some(path.to_path_buf()));
    }
    match policy {
        Collision::Error => Err(PeelError::Collision {
            path: path.to_path_buf(),
            policy,
        }),
        Collision::Overwrite => {
            if path.is_dir() {
                fs::remove_dir_all(path)?;
            } else {
                fs::remove_file(path)?;
            }
            Ok(Some(path.to_path_buf()))
        }
        Collision::Rename => Ok(Some(unique_path(path))),
        Collision::Skip => Ok(None),
    }
}
