//! C ABI for Peel.
//!
//! Strings returned from `peel_*` functions are heap-allocated UTF-8 C strings;
//! free them with `peel_string_free`.

use peel_core::{extract_archive, list_archive, Collision, EnclosingDirectory, ExtractPolicy};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::ptr;

#[repr(C)]
pub struct PeelPolicy {
    /// Nullable UTF-8 destination directory path.
    pub destination: *const c_char,
    /// 0=error, 1=overwrite, 2=rename, 3=skip
    pub collision: u32,
    /// 0=when_needed, 1=always, 2=never
    pub enclosing: u32,
}

fn cstr_to_path(p: *const c_char) -> Option<PathBuf> {
    if p.is_null() {
        return None;
    }
    let s = unsafe { CStr::from_ptr(p) }.to_string_lossy();
    if s.is_empty() {
        None
    } else {
        Some(PathBuf::from(s.as_ref()))
    }
}

fn policy_from_c(p: &PeelPolicy) -> ExtractPolicy {
    ExtractPolicy {
        destination: cstr_to_path(p.destination),
        collision: match p.collision {
            1 => Collision::Overwrite,
            2 => Collision::Rename,
            3 => Collision::Skip,
            _ => Collision::Error,
        },
        enclosing_directory: match p.enclosing {
            1 => EnclosingDirectory::Always,
            2 => EnclosingDirectory::Never,
            _ => EnclosingDirectory::WhenNeeded,
        },
        password: None,
        budget: peel_core::ResourceBudget::default(),
        selection: None,
        delete_source: false,
    }
}

fn ok_json(v: impl serde::Serialize) -> *mut c_char {
    match serde_json::to_string(&v) {
        Ok(s) => CString::new(s)
            .map(|c| c.into_raw())
            .unwrap_or(ptr::null_mut()),
        Err(e) => err_string(&e.to_string()),
    }
}

fn err_string(msg: &str) -> *mut c_char {
    let payload = serde_json::json!({ "error": msg }).to_string();
    CString::new(payload)
        .map(|c| c.into_raw())
        .unwrap_or(ptr::null_mut())
}

/// Extract archive. Returns JSON object (result or `{ "error": "..." }`).
/// Caller frees with `peel_string_free`.
#[no_mangle]
pub extern "C" fn peel_extract(archive_path: *const c_char, policy: PeelPolicy) -> *mut c_char {
    if archive_path.is_null() {
        return err_string("archive_path is null");
    }
    let path = unsafe { CStr::from_ptr(archive_path) }.to_string_lossy();
    let pol = policy_from_c(&policy);
    match extract_archive(std::path::Path::new(path.as_ref()), &pol) {
        Ok(r) => ok_json(r),
        Err(e) => err_string(&e.to_string()),
    }
}

/// List archive entries as JSON array (or error object).
#[no_mangle]
pub extern "C" fn peel_list(archive_path: *const c_char) -> *mut c_char {
    if archive_path.is_null() {
        return err_string("archive_path is null");
    }
    let path = unsafe { CStr::from_ptr(archive_path) }.to_string_lossy();
    match list_archive(std::path::Path::new(path.as_ref())) {
        Ok(r) => ok_json(r),
        Err(e) => err_string(&e.to_string()),
    }
}

/// Free a string returned by peel_*.
#[no_mangle]
pub extern "C" fn peel_string_free(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(s));
    }
}
