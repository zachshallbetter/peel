//! Peel extraction engine — native multi-format, no Unarchiver/unar dependency.
//!
//! PEL-002: every adapter shares path containment, symlink rejection, and budgets.

mod capabilities;
mod container;
mod detect;
mod extract;
mod pathutil;
mod policy;
mod rar;
mod safety;
mod session;
mod sevenz;

pub use capabilities::{all_format_capabilities, capabilities_for, FormatCapabilities, Support};
pub use detect::{detect_format, Format};
pub use session::{ArchiveSession, SessionState, SourceIdentity};
pub use extract::{extract_archive, list_archive, ArchiveEntry, ExtractResult};
pub use policy::{Collision, EnclosingDirectory, ExtractPolicy};
pub use safety::ResourceBudget;
pub use safety::{assert_tree_contained, sanitize_entry_name, safe_destination};
pub use rar::{is_rar_multipart, rar_volume_paths};

use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum PeelError {
    #[error("unsupported or unrecognized archive: {0}")]
    Unsupported(String),
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("zip error: {0}")]
    Zip(#[from] zip::result::ZipError),
    #[error("path escape blocked: {0}")]
    PathEscape(String),
    #[error("unsafe archive entry: {0}")]
    UnsafeEntry(String),
    #[error("resource budget exceeded: {0}")]
    BudgetExceeded(String),
    #[error("destination collision ({policy:?}): {path}")]
    Collision {
        path: PathBuf,
        policy: Collision,
    },
    #[error("rar error: {0}")]
    Rar(String),
    #[error("7z error: {0}")]
    SevenZ(String),
    #[error("{0}")]
    Other(String),
}

pub type Result<T> = std::result::Result<T, PeelError>;

pub fn peel(archive: &Path, policy: &ExtractPolicy) -> Result<ExtractResult> {
    extract_archive(archive, policy)
}
