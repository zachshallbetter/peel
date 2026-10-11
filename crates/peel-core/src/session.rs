//! MAC-001 foundation — ArchiveSession identity for coordinated access.
//! Full NSFileCoordinator wiring lives in the Swift shell; core tracks source fingerprint.
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

#[derive(Debug, Clone, Serialize)]
pub struct SourceIdentity {
    pub path: PathBuf,
    pub len: u64,
    pub modified: Option<u64>,
}

impl SourceIdentity {
    pub fn capture(path: &Path) -> std::io::Result<Self> {
        let meta = fs::metadata(path)?;
        let modified = meta.modified().ok().and_then(|t| {
            t.duration_since(SystemTime::UNIX_EPOCH)
                .ok()
                .map(|d| d.as_secs())
        });
        Ok(Self {
            path: path.to_path_buf(),
            len: meta.len(),
            modified,
        })
    }

    /// True when path still matches captured size/mtime (best-effort stale detection).
    pub fn still_matches(&self) -> bool {
        match Self::capture(&self.path) {
            Ok(now) => now.len == self.len && now.modified == self.modified,
            Err(_) => false,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum SessionState {
    Open,
    Invalidated,
    Closed,
}

#[derive(Debug, Clone, Serialize)]
pub struct ArchiveSession {
    pub id: String,
    pub source: SourceIdentity,
    pub state: SessionState,
}

impl ArchiveSession {
    pub fn open(path: &Path) -> std::io::Result<Self> {
        let source = SourceIdentity::capture(path)?;
        let id = format!(
            "{}:{}:{}",
            path.display(),
            source.len,
            source.modified.unwrap_or(0)
        );
        Ok(Self {
            id,
            source,
            state: SessionState::Open,
        })
    }

    pub fn revalidate(&mut self) {
        if self.state == SessionState::Open && !self.source.still_matches() {
            self.state = SessionState::Invalidated;
        }
    }

    pub fn close(&mut self) {
        self.state = SessionState::Closed;
    }
}
