use peel_core::{extract_archive, list_archive, ExtractPolicy};
use std::fs;
use std::path::PathBuf;

fn fixture_zip() -> PathBuf {
    // crates/peel-core/tests -> repo root fixtures
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/hello.zip")
}

#[test]
fn lists_and_extracts_hello_zip() {
    let zip = fixture_zip();
    assert!(zip.exists(), "missing fixture {}", zip.display());

    let entries = list_archive(&zip).expect("list");
    assert!(!entries.is_empty());
    assert!(entries.iter().any(|e| e.name.contains("hello")));

    let dir = tempfile::tempdir().unwrap();
    let mut policy = ExtractPolicy::overwrite();
    policy.destination = Some(dir.path().to_path_buf());
    let result = extract_archive(&zip, &policy).expect("extract");
    assert!(!result.extracted.is_empty());

    let out = result.extracted.iter().find(|p| {
        p.file_name()
            .map(|n| n.to_string_lossy().contains("hello"))
            .unwrap_or(false)
    });
    let out = out.expect("hello file extracted");
    let text = fs::read_to_string(out).unwrap();
    assert!(text.contains("hello"), "got {text:?}");
}
