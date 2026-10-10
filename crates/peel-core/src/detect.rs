use crate::{PeelError, Result};
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    Zip,
    Tar,
    TarGz,
    TarBz2,
    GzipSingle,
    Rar,
    SevenZ,
    Dmg,
    AppBundle,
    Pdf,
    Exe,
}

pub fn detect_format(path: &Path) -> Result<Format> {
    let name = path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_ascii_lowercase();

    // Directory / package heuristics first
    if path.is_dir() {
        if name.ends_with(".app") || path.join("Contents/Info.plist").exists() {
            return Ok(Format::AppBundle);
        }
        return Err(PeelError::Unsupported(format!(
            "directory is not a peelable package: {}",
            path.display()
        )));
    }

    let mut f = File::open(path)?;
    let mut magic = [0u8; 16];
    let n = f.read(&mut magic)?;

    // ZIP (also used by some APK/JAR/XLSX — still zip peel)
    if n >= 4 && magic[0] == 0x50 && magic[1] == 0x4B && matches!(magic[2], 0x03 | 0x05 | 0x07) {
        return Ok(Format::Zip);
    }
    // RAR4 / RAR5
    if n >= 7 && &magic[0..4] == b"Rar!" && magic[4] == 0x1A && magic[5] == 0x07 {
        return Ok(Format::Rar);
    }
    // 7z
    if n >= 6 && magic[0] == 0x37 && magic[1] == 0x7A && magic[2] == 0xBC && magic[3] == 0xAF {
        return Ok(Format::SevenZ);
    }
    // PDF
    if n >= 5 && &magic[0..5] == b"%PDF-" {
        return Ok(Format::Pdf);
    }
    // gzip
    if n >= 2 && magic[0] == 0x1F && magic[1] == 0x8B {
        if name.ends_with(".tar.gz") || name.ends_with(".tgz") {
            return Ok(Format::TarGz);
        }
        return Ok(Format::GzipSingle);
    }
    // bzip2
    if n >= 3 && magic[0] == b'B' && magic[1] == b'Z' && magic[2] == b'h' {
        if name.contains(".tar.") || name.ends_with(".tbz") || name.ends_with(".tbz2") {
            return Ok(Format::TarBz2);
        }
        return Err(PeelError::Unsupported(
            "bare bzip2 (use tar.bz2 or 7z)".into(),
        ));
    }
    // DMG — often starts with koly trailer; UDIF magic varies. Prefer extension + 'koly' scan.
    if name.ends_with(".dmg") {
        return Ok(Format::Dmg);
    }
    // PE executable
    if n >= 2 && magic[0] == b'M' && magic[1] == b'Z' {
        return Ok(Format::Exe);
    }
    // Mach-O (single binary) — treat like "app peel" of a binary file into folder with copy
    if n >= 4
        && matches!(
            u32::from_le_bytes([magic[0], magic[1], magic[2], magic[3]]),
            0xFEED_FACE | 0xFEED_FACF | 0xCEFA_EDFE | 0xCFFA_EDFE | 0xCAFE_BABE | 0xBEBA_FECA
        )
    {
        // Not a container; still allow peel-as-copy
        return Ok(Format::Exe);
    }

    // tar ustar
    let mut f = File::open(path)?;
    f.seek(SeekFrom::Start(257))?;
    let mut ustar = [0u8; 5];
    if f.read(&mut ustar)? == 5 && &ustar == b"ustar" {
        return Ok(Format::Tar);
    }
    if name.ends_with(".tar") {
        return Ok(Format::Tar);
    }
    if name.ends_with(".zip") {
        return Ok(Format::Zip);
    }
    if name.ends_with(".rar") {
        return Ok(Format::Rar);
    }
    if name.ends_with(".7z") {
        return Ok(Format::SevenZ);
    }
    if name.ends_with(".pdf") {
        return Ok(Format::Pdf);
    }
    if name.ends_with(".app") {
        return Ok(Format::AppBundle);
    }

    Err(PeelError::Unsupported(format!(
        "{} (magic {:02x?})",
        path.display(),
        &magic[..n.min(8)]
    )))
}
