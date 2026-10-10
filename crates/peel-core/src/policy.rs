use crate::safety::ResourceBudget;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Collision {
    Error,
    Overwrite,
    Rename,
    Skip,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EnclosingDirectory {
    WhenNeeded,
    Always,
    Never,
}

#[derive(Debug, Clone)]
pub struct ExtractPolicy {
    pub destination: Option<PathBuf>,
    pub collision: Collision,
    pub enclosing_directory: EnclosingDirectory,
    pub password: Option<String>,
    pub budget: ResourceBudget,
    /// When set, only extract entries whose path matches one of these globs/prefixes/names.
    pub selection: Option<Vec<String>>,
    /// Delete the source archive after a successful extract.
    pub delete_source: bool,
}

impl Default for ExtractPolicy {
    fn default() -> Self {
        Self {
            destination: None,
            collision: Collision::Rename,
            enclosing_directory: EnclosingDirectory::WhenNeeded,
            password: None,
            budget: ResourceBudget::default(),
            selection: None,
            delete_source: false,
        }
    }
}

impl ExtractPolicy {
    pub fn overwrite() -> Self {
        Self {
            collision: Collision::Overwrite,
            ..Self::default()
        }
    }

    pub fn wants_entry(&self, name: &str) -> bool {
        let Some(sel) = &self.selection else {
            return true;
        };
        if sel.is_empty() {
            return true;
        }
        let n = name.trim_start_matches("./").replace('\\', "/");
        sel.iter().any(|pat| entry_matches(&n, pat))
    }
}

fn entry_matches(name: &str, pat: &str) -> bool {
    let p = pat.trim_start_matches("./").replace('\\', "/");
    if p.is_empty() {
        return true;
    }
    if name == p || name.starts_with(&(p.trim_end_matches('/').to_string() + "/")) {
        return true;
    }
    // simple * glob on full path or basename
    if p.contains('*') {
        return wildcard_match(name, &p) || wildcard_match(name.rsplit('/').next().unwrap_or(name), &p);
    }
    name.ends_with(&p) || name.contains(&p)
}

fn wildcard_match(text: &str, pattern: &str) -> bool {
    // very small glob: * only
    let parts: Vec<&str> = pattern.split('*').collect();
    if parts.len() == 1 {
        return text == pattern;
    }
    let mut rest = text;
    if !parts[0].is_empty() {
        if !rest.starts_with(parts[0]) {
            return false;
        }
        rest = &rest[parts[0].len()..];
    }
    for (i, part) in parts.iter().enumerate().skip(1) {
        if part.is_empty() {
            if i == parts.len() - 1 {
                return true;
            }
            continue;
        }
        if i == parts.len() - 1 {
            return rest.ends_with(part);
        }
        if let Some(idx) = rest.find(part) {
            rest = &rest[idx + part.len()..];
        } else {
            return false;
        }
    }
    true
}
