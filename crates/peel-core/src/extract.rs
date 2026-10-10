use crate::container::{
    extract_app, extract_dmg, extract_exe, extract_pdf, list_app,
};
use crate::detect::{detect_format, Format};
use crate::pathutil::{default_peel_folder, unique_path};
use crate::safety::safe_destination;
use crate::policy::{Collision, EnclosingDirectory, ExtractPolicy};
use crate::rar::{extract_rar, list_rar};
use crate::sevenz::{extract_7z, list_7z};
use crate::{PeelError, Result};
use flate2::read::GzDecoder;
use serde::Serialize;
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use tar::Archive as TarArchive;
use zip::ZipArchive;

#[derive(Debug, Clone, Serialize)]
pub struct ArchiveEntry {
    pub name: String,
    pub is_dir: bool,
    pub size: Option<u64>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ExtractResult {
    pub format: String,
    pub destination: PathBuf,
    pub extracted: Vec<PathBuf>,
    pub skipped: Vec<PathBuf>,
}

pub fn list_archive(path: &Path) -> Result<Vec<ArchiveEntry>> {
    match detect_format(path)? {
        Format::Zip => list_zip(path),
        Format::Tar | Format::TarGz | Format::TarBz2 => list_tar(path, detect_format(path)?),
        Format::GzipSingle => Ok(vec![ArchiveEntry {
            name: path
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("out")
                .to_string(),
            is_dir: false,
            size: None,
        }]),
        Format::Rar => list_rar(path),
        Format::SevenZ => list_7z(path),
        Format::AppBundle => list_app(path),
        Format::Dmg => Ok(vec![ArchiveEntry {
            name: path
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("disk.dmg")
                .to_string(),
            is_dir: true,
            size: None,
        }]),
        Format::Pdf | Format::Exe => Ok(vec![ArchiveEntry {
            name: path
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or("file")
                .to_string(),
            is_dir: false,
            size: path.metadata().ok().map(|m| m.len()),
        }]),
    }
}

pub fn extract_archive(archive: &Path, policy: &ExtractPolicy) -> Result<ExtractResult> {
    let format = detect_format(archive)?;
    let entries = list_archive(archive).unwrap_or_default();

    // Always peel into a dedicated folder (product rule).
    let base = policy
        .destination
        .clone()
        .unwrap_or_else(|| {
            archive
                .parent()
                .unwrap_or_else(|| Path::new("."))
                .to_path_buf()
        });
    fs::create_dir_all(&base)?;

    let dest = match policy.enclosing_directory {
        EnclosingDirectory::Never => base.clone(),
        EnclosingDirectory::Always => default_peel_folder(archive, &base),
        EnclosingDirectory::WhenNeeded => {
            // Multiple tops or non-classic containers → dedicated folder
            let tops: std::collections::BTreeSet<_> = entries
                .iter()
                .filter_map(|e| {
                    let n = e.name.trim_start_matches("./");
                    if n.is_empty() {
                        None
                    } else {
                        Some(n.split('/').next().unwrap_or(n).to_string())
                    }
                })
                .collect();
            if tops.len() != 1
                || matches!(
                    format,
                    Format::AppBundle
                        | Format::Dmg
                        | Format::Pdf
                        | Format::Exe
                        | Format::Rar
                        | Format::SevenZ
                )
            {
                default_peel_folder(archive, &base)
            } else {
                base.clone()
            }
        }
    };
    fs::create_dir_all(&dest)?;

    let mut extracted = Vec::new();
    let mut skipped = Vec::new();

    match format {
        Format::Zip => extract_zip(archive, &dest, policy, &mut extracted, &mut skipped)?,
        Format::Tar | Format::TarGz | Format::TarBz2 => {
            extract_tar(archive, format, &dest, policy, &mut extracted, &mut skipped)?
        }
        Format::GzipSingle => {
            extract_gzip_single(archive, &dest, policy, &mut extracted, &mut skipped)?
        }
        Format::Rar => extract_rar(archive, &dest, policy, &mut extracted, &mut skipped)?,
        Format::SevenZ => extract_7z(archive, &dest, policy, &mut extracted, &mut skipped)?,
        Format::AppBundle => extract_app(archive, &dest, policy, &mut extracted, &mut skipped)?,
        Format::Dmg => extract_dmg(archive, &dest, policy, &mut extracted, &mut skipped)?,
        Format::Pdf => extract_pdf(archive, &dest, policy, &mut extracted, &mut skipped)?,
        Format::Exe => extract_exe(archive, &dest, policy, &mut extracted, &mut skipped)?,
    }

    if policy.delete_source {
        // Prefer deleting only the opened path; multipart volumes deleted best-effort.
        let volumes = if matches!(format, Format::Rar) {
            crate::rar::rar_volume_paths(archive)
        } else {
            vec![archive.to_path_buf()]
        };
        for v in volumes {
            let _ = fs::remove_file(&v);
        }
    }

    Ok(ExtractResult {
        format: format!("{:?}", format),
        destination: dest,
        extracted,
        skipped,
    })
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
        Collision::Overwrite => Ok(Some(path.to_path_buf())),
        Collision::Rename => Ok(Some(unique_path(path))),
        Collision::Skip => Ok(None),
    }
}

fn list_zip(path: &Path) -> Result<Vec<ArchiveEntry>> {
    let f = File::open(path)?;
    let mut zip = ZipArchive::new(f)?;
    let mut out = Vec::with_capacity(zip.len());
    for i in 0..zip.len() {
        let e = zip.by_index(i)?;
        out.push(ArchiveEntry {
            name: e.name().to_string(),
            is_dir: e.is_dir(),
            size: Some(e.size()),
        });
    }
    Ok(out)
}

fn extract_zip(
    path: &Path,
    dest: &Path,
    policy: &ExtractPolicy,
    extracted: &mut Vec<PathBuf>,
    skipped: &mut Vec<PathBuf>,
) -> Result<()> {
    let f = File::open(path)?;
    let mut zip = ZipArchive::new(f)?;
    policy.budget.check_entry_count(zip.len() as u64)?;
    let mut total = 0u64;
    for i in 0..zip.len() {
        let e = zip.by_index(i)?;
        // size check
        policy.budget.check_entry_size(e.size())?;
        total = total.saturating_add(e.size());
        drop(e);
    }
    policy.budget.check_total(total)?;
    // reopen for extraction (by_index consumed state is fine but we already iterated)
    let f = File::open(path)?;
    let mut zip = ZipArchive::new(f)?;
    for i in 0..zip.len() {
        let mut entry = zip.by_index(i)?;
        let name = entry.name().to_string();
        if !policy.wants_entry(&name) {
            continue;
        }
        let out_path = safe_destination(dest, &name, &policy.budget)?;
        if entry.is_dir() {
            fs::create_dir_all(&out_path)?;
            extracted.push(out_path);
            continue;
        }
        if let Some(parent) = out_path.parent() {
            fs::create_dir_all(parent)?;
        }
        match apply_collision(&out_path, policy.collision)? {
            None => skipped.push(out_path),
            Some(target) => {
                let mut outfile = File::create(&target)?;
                io::copy(&mut entry, &mut outfile)?;
                extracted.push(target);
            }
        }
    }
    Ok(())
}

fn open_tar_reader(path: &Path, format: Format) -> Result<Box<dyn Read>> {
    let f = File::open(path)?;
    Ok(match format {
        Format::Tar => Box::new(f),
        Format::TarGz => Box::new(GzDecoder::new(f)),
        Format::TarBz2 => Box::new(bzip2::read::BzDecoder::new(f)),
        _ => return Err(PeelError::Other("not a tar format".into())),
    })
}

fn list_tar(path: &Path, format: Format) -> Result<Vec<ArchiveEntry>> {
    let reader = open_tar_reader(path, format)?;
    let mut archive = TarArchive::new(reader);
    let mut out = Vec::new();
    for entry in archive.entries()? {
        let entry = entry.map_err(|e| PeelError::Other(e.to_string()))?;
        let path = entry.path().map_err(|e| PeelError::Other(e.to_string()))?;
        out.push(ArchiveEntry {
            name: path.to_string_lossy().to_string(),
            is_dir: entry.header().entry_type().is_dir(),
            size: entry.header().size().ok(),
        });
    }
    Ok(out)
}

fn extract_tar(
    path: &Path,
    format: Format,
    dest: &Path,
    policy: &ExtractPolicy,
    extracted: &mut Vec<PathBuf>,
    skipped: &mut Vec<PathBuf>,
) -> Result<()> {
    let reader = open_tar_reader(path, format)?;
    let mut archive = TarArchive::new(reader);
    for entry in archive.entries()? {
        let mut entry = entry.map_err(|e| PeelError::Other(e.to_string()))?;
        let rel = entry
            .path()
            .map_err(|e| PeelError::Other(e.to_string()))?
            .to_string_lossy()
            .to_string();
        let out_path = safe_destination(dest, &rel, &policy.budget)?;
        if entry.header().entry_type().is_dir() {
            fs::create_dir_all(&out_path)?;
            extracted.push(out_path);
            continue;
        }
        if let Some(parent) = out_path.parent() {
            fs::create_dir_all(parent)?;
        }
        match apply_collision(&out_path, policy.collision)? {
            None => skipped.push(out_path),
            Some(target) => {
                let mut outfile = File::create(&target)?;
                io::copy(&mut entry, &mut outfile)?;
                extracted.push(target);
            }
        }
    }
    Ok(())
}

fn extract_gzip_single(
    path: &Path,
    dest: &Path,
    policy: &ExtractPolicy,
    extracted: &mut Vec<PathBuf>,
    skipped: &mut Vec<PathBuf>,
) -> Result<()> {
    let name = path
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("output");
    let out_path = dest.join(name);
    match apply_collision(&out_path, policy.collision)? {
        None => skipped.push(out_path),
        Some(target) => {
            let f = File::open(path)?;
            let mut decoder = GzDecoder::new(f);
            let mut outfile = File::create(&target)?;
            io::copy(&mut decoder, &mut outfile)?;
            outfile.flush()?;
            extracted.push(target);
        }
    }
    Ok(())
}
