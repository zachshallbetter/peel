//! Peel CLI — unar/lsar + unzip + 7z style ergonomics.
//!
//! Shorthands:
//!   peel ARCHIVE                 extract (default)
//!   peel x|e|extract ARCHIVE     extract
//!   peel l|ls|list ARCHIVE       list
//!   peel t|test ARCHIVE          integrity/list smoke test
//!   peel p|probe ARCHIVE         detect format + capabilities
//!   peel formats                 supported formats
//!
//! Common flags (unar-compatible aliases):
//!   -o/--out DIR   -f overwrite  -r rename  -s skip
//!   -d always dir  -D never dir  -p password  -q quiet  -j JSON
//!   --delete       remove archive after success
//!   -- FILES...    selective extract

use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use peel_core::{
    detect_format, extract_archive, is_rar_multipart, list_archive, rar_volume_paths, Collision,
    EnclosingDirectory, ExtractPolicy, Format, ResourceBudget,
};
use std::path::PathBuf;
use std::process::ExitCode;

#[derive(Parser, Debug)]
#[command(
    name = "peel",
    version,
    about = "Peel — open what's inside (archive extract/list/probe)",
    long_about = "Native multi-format extractor. Compatible spirit with unar/lsar, unzip, and 7z.\n\n\
Examples:\n  \
peel archive.zip\n  \
peel x archive.rar -o ~/Out -r\n  \
peel l archive.7z -j\n  \
peel x thing.zip readme.txt *.md\n  \
peel probe file.bin -j\n  \
peel formats"
)]
#[command(propagate_version = true)]
#[command(args_conflicts_with_subcommands = false)]
struct Cli {
    /// Quiet (suppress non-error human output)
    #[arg(short = 'q', long, global = true)]
    quiet: bool,

    /// JSON output where applicable
    #[arg(short = 'j', long = "json", global = true)]
    json: bool,

    #[command(subcommand)]
    cmd: Option<Cmd>,

    /// Archive path when using default extract form: `peel ARCHIVE [files...]`
    #[arg(global = false)]
    archive: Option<PathBuf>,

    /// Selective members for default extract form
    #[arg(global = false)]
    members: Vec<String>,

    // shared extract-ish flags also work on default form
    #[arg(short = 'o', long = "out", global = true)]
    out: Option<PathBuf>,
    #[arg(short = 'f', long = "force-overwrite", global = true)]
    force_overwrite: bool,
    #[arg(short = 'r', long = "force-rename", global = true)]
    force_rename: bool,
    #[arg(short = 's', long = "force-skip", global = true)]
    force_skip: bool,
    #[arg(short = 'd', long = "force-directory", global = true)]
    force_directory: bool,
    #[arg(short = 'D', long = "no-directory", global = true)]
    no_directory: bool,
    #[arg(short = 'p', long = "password", global = true)]
    password: Option<String>,
    #[arg(long = "delete", global = true)]
    delete: bool,
}

#[derive(Subcommand, Debug)]
enum Cmd {
    /// Extract archive (aliases: x, e)
    #[command(visible_alias = "x", visible_alias = "e", visible_alias = "unar")]
    Extract {
        archive: PathBuf,
        /// Optional member paths / globs
        members: Vec<String>,
    },
    /// List archive members (aliases: l, ls, lsar)
    #[command(visible_alias = "l", visible_alias = "ls", visible_alias = "lsar")]
    List {
        archive: PathBuf,
        /// Filter patterns
        members: Vec<String>,
        /// Long listing
        #[arg(short = 'l', long = "long")]
        long: bool,
    },
    /// Test/list archive readability (alias: t)
    #[command(visible_alias = "t")]
    Test { archive: PathBuf },
    /// Probe format + volumes + entry count (alias: p)
    #[command(visible_alias = "p")]
    Probe { archive: PathBuf },
    /// Show supported formats
    Formats,
}

fn collision_from_flags(cli: &Cli) -> Collision {
    // last-wins priority similar to unar: explicit flags
    if cli.force_overwrite {
        Collision::Overwrite
    } else if cli.force_skip {
        Collision::Skip
    } else if cli.force_rename {
        Collision::Rename
    } else {
        Collision::Rename
    }
}

fn enclosing_from_flags(cli: &Cli) -> EnclosingDirectory {
    if cli.force_directory {
        EnclosingDirectory::Always
    } else if cli.no_directory {
        EnclosingDirectory::Never
    } else {
        EnclosingDirectory::WhenNeeded
    }
}

fn policy(cli: &Cli, members: &[String]) -> ExtractPolicy {
    ExtractPolicy {
        destination: cli.out.clone(),
        collision: collision_from_flags(cli),
        enclosing_directory: enclosing_from_flags(cli),
        password: cli.password.clone(),
        budget: ResourceBudget::default(),
        selection: if members.is_empty() {
            None
        } else {
            Some(members.to_vec())
        },
        delete_source: cli.delete,
    }
}

fn do_extract(cli: &Cli, archive: &PathBuf, members: &[String]) -> Result<()> {
    let pol = policy(cli, members);
    let result = extract_archive(archive, &pol)
        .with_context(|| format!("extract {}", archive.display()))?;
    if cli.json {
        println!("{}", serde_json::to_string_pretty(&result)?);
    } else if !cli.quiet {
        println!(
            "{} → {} ({} files)",
            result.format,
            result.destination.display(),
            result.extracted.len()
        );
        for p in &result.extracted {
            println!("  {}", p.display());
        }
        if !result.skipped.is_empty() {
            println!("skipped:");
            for p in &result.skipped {
                println!("  {}", p.display());
            }
        }
    }
    Ok(())
}

fn do_list(cli: &Cli, archive: &PathBuf, members: &[String], long: bool) -> Result<()> {
    let mut entries = list_archive(archive)
        .with_context(|| format!("list {}", archive.display()))?;
    if !members.is_empty() {
        let pol = policy(cli, members);
        entries.retain(|e| pol.wants_entry(&e.name));
    }
    if cli.json {
        println!("{}", serde_json::to_string_pretty(&entries)?);
    } else if !cli.quiet {
        if long {
            println!("{:>12}  {:5}  name", "size", "type");
            for e in &entries {
                let kind = if e.is_dir { "dir" } else { "file" };
                let sz = e.size.map(|s| s.to_string()).unwrap_or_else(|| "-".into());
                println!("{:>12}  {:5}  {}", sz, kind, e.name);
            }
        } else {
            for e in &entries {
                if e.is_dir {
                    println!("{}/", e.name.trim_end_matches('/'));
                } else {
                    println!("{}", e.name);
                }
            }
        }
        if !cli.quiet {
            eprintln!("{} entries", entries.len());
        }
    }
    Ok(())
}

fn do_test(cli: &Cli, archive: &PathBuf) -> Result<()> {
    let entries = list_archive(archive)
        .with_context(|| format!("test {}", archive.display()))?;
    let fmt = detect_format(archive)?;
    if cli.json {
        let v = serde_json::json!({
            "ok": true,
            "format": format!("{:?}", fmt),
            "entries": entries.len(),
        });
        println!("{}", serde_json::to_string_pretty(&v)?);
    } else if !cli.quiet {
        println!("OK  {:?}  {} entries  {}", fmt, entries.len(), archive.display());
    }
    Ok(())
}

fn do_probe(cli: &Cli, archive: &PathBuf) -> Result<()> {
    let fmt = detect_format(archive)?;
    let entries = list_archive(archive).unwrap_or_default();
    let multipart = matches!(fmt, Format::Rar) && is_rar_multipart(archive);
    let volumes = if matches!(fmt, Format::Rar) {
        rar_volume_paths(archive)
            .into_iter()
            .map(|p| p.display().to_string())
            .collect::<Vec<_>>()
    } else {
        vec![archive.display().to_string()]
    };
    let body = serde_json::json!({
        "path": archive.display().to_string(),
        "format": format!("{:?}", fmt),
        "entries": entries.len(),
        "multipart": multipart,
        "volumes": volumes,
        "password_supported": matches!(fmt, Format::Rar | Format::Zip | Format::SevenZ),
        "operations": ["list", "extract", "test", "probe"],
    });
    if cli.json || cli.quiet {
        println!("{}", serde_json::to_string_pretty(&body)?);
    } else {
        println!("path:       {}", archive.display());
        println!("format:     {:?}", fmt);
        println!("entries:    {}", entries.len());
        println!("multipart:  {}", multipart);
        println!("volumes:    {}", volumes.join(", "));
    }
    Ok(())
}

fn do_formats(cli: &Cli) -> Result<()> {
    let rows = [
        ("zip", "R", "ZIP/ZIP64"),
        ("rar", "R", "RAR4/5, multipart .partN.rar / .rNN"),
        ("7z", "R", "7-Zip"),
        ("tar", "R", "ustar/pax"),
        ("tar.gz/tgz", "R", "gzip + tar"),
        ("tar.bz2/tbz2", "R", "bzip2 + tar"),
        ("gz", "R", "single-stream gzip"),
        ("dmg", "R/C", "hdiutil attach (macOS)"),
        ("app", "R", "macOS bundle copy"),
        ("pdf/exe", "I", "stage/inspect helpers"),
    ];
    if cli.json {
        let v: Vec<_> = rows
            .iter()
            .map(|(f, c, n)| serde_json::json!({"format": f, "caps": c, "notes": n}))
            .collect();
        println!("{}", serde_json::to_string_pretty(&v)?);
    } else {
        println!("{:<14} {:<4} {}", "format", "caps", "notes");
        for (f, c, n) in rows {
            println!("{:<14} {:<4} {}", f, c, n);
        }
    }
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("peel: {e:#}");
            ExitCode::from(1)
        }
    }
}

fn run() -> Result<()> {
    let cli = Cli::parse();

    // Subcommand path
    if let Some(cmd) = &cli.cmd {
        return match cmd {
            Cmd::Extract { archive, members } => do_extract(&cli, archive, members),
            Cmd::List {
                archive,
                members,
                long,
            } => do_list(&cli, archive, members, *long),
            Cmd::Test { archive } => do_test(&cli, archive),
            Cmd::Probe { archive } => do_probe(&cli, archive),
            Cmd::Formats => do_formats(&cli),
        };
    }

    // Default: peel ARCHIVE [members...]
    let Some(archive) = &cli.archive else {
        bail!("usage: peel <archive> | peel x|l|t|p|formats …  (try peel --help)");
    };
    if !archive.exists() {
        bail!("not found: {}", archive.display());
    }
    do_extract(&cli, archive, &cli.members)
}
