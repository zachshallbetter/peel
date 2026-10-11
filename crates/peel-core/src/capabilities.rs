//! PEL-003 — capability registry (honest per-format operations).
use crate::detect::Format;
use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Support {
    Supported,
    Conditional,
    Unsupported,
    Experimental,
}

#[derive(Debug, Clone, Serialize)]
pub struct FormatCapabilities {
    pub format: String,
    pub family: String,
    pub probe: Support,
    pub list: Support,
    pub extract_all: Support,
    pub extract_selected: Support,
    pub create: Support,
    pub password: Support,
    pub multipart: Support,
    pub notes: &'static str,
}

pub fn capabilities_for(format: Format) -> FormatCapabilities {
    match format {
        Format::Zip => FormatCapabilities {
            format: "zip".into(),
            family: "archive".into(),
            probe: Support::Supported,
            list: Support::Supported,
            extract_all: Support::Supported,
            extract_selected: Support::Supported,
            create: Support::Unsupported,
            password: Support::Conditional,
            multipart: Support::Unsupported,
            notes: "ZIP/ZIP64 path-safe extract; password variants conditional",
        },
        Format::Tar | Format::TarGz | Format::TarBz2 => FormatCapabilities {
            format: format!("{:?}", format).to_ascii_lowercase(),
            family: "archive".into(),
            probe: Support::Supported,
            list: Support::Supported,
            extract_all: Support::Supported,
            extract_selected: Support::Conditional,
            create: Support::Unsupported,
            password: Support::Unsupported,
            multipart: Support::Unsupported,
            notes: "ustar/pax via peel-core",
        },
        Format::GzipSingle => FormatCapabilities {
            format: "gzip".into(),
            family: "stream".into(),
            probe: Support::Supported,
            list: Support::Supported,
            extract_all: Support::Supported,
            extract_selected: Support::Unsupported,
            create: Support::Unsupported,
            password: Support::Unsupported,
            multipart: Support::Unsupported,
            notes: "single-stream inflate",
        },
        Format::Rar => FormatCapabilities {
            format: "rar".into(),
            family: "archive".into(),
            probe: Support::Supported,
            list: Support::Supported,
            extract_all: Support::Supported,
            extract_selected: Support::Conditional,
            create: Support::Unsupported,
            password: Support::Conditional,
            multipart: Support::Supported,
            notes: "RAR via unrar-ng; multipart volumes resolved to first part",
        },
        Format::SevenZ => FormatCapabilities {
            format: "7z".into(),
            family: "archive".into(),
            probe: Support::Supported,
            list: Support::Supported,
            extract_all: Support::Supported,
            extract_selected: Support::Conditional,
            create: Support::Unsupported,
            password: Support::Conditional,
            multipart: Support::Unsupported,
            notes: "sevenz-rust2; solid archives may need full decode",
        },
        Format::Dmg => FormatCapabilities {
            format: "dmg".into(),
            family: "disk_image".into(),
            probe: Support::Supported,
            list: Support::Conditional,
            extract_all: Support::Conditional,
            extract_selected: Support::Unsupported,
            create: Support::Unsupported,
            password: Support::Unsupported,
            multipart: Support::Unsupported,
            notes: "macOS hdiutil path; consentful mount is future MAC-007",
        },
        Format::AppBundle => FormatCapabilities {
            format: "app".into(),
            family: "package".into(),
            probe: Support::Supported,
            list: Support::Supported,
            extract_all: Support::Supported,
            extract_selected: Support::Unsupported,
            create: Support::Unsupported,
            password: Support::Unsupported,
            multipart: Support::Unsupported,
            notes: "directory bundle copy",
        },
        Format::Pdf | Format::Exe => FormatCapabilities {
            format: format!("{:?}", format).to_ascii_lowercase(),
            family: "document".into(),
            probe: Support::Supported,
            list: Support::Experimental,
            extract_all: Support::Experimental,
            extract_selected: Support::Unsupported,
            create: Support::Unsupported,
            password: Support::Unsupported,
            multipart: Support::Unsupported,
            notes: "staged copy / inspect-only; not full internal extract",
        },
    }
}

pub fn all_format_capabilities() -> Vec<FormatCapabilities> {
    use Format::*;
    [
        Zip, Tar, TarGz, TarBz2, GzipSingle, Rar, SevenZ, Dmg, AppBundle, Pdf, Exe,
    ]
    .into_iter()
    .map(capabilities_for)
    .collect()
}
