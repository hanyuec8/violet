// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

use std::{
    fs::File,
    io::{copy, BufWriter, Read},
    path::PathBuf,
};

use sevenz_rust::{Error, SevenZArchiveEntry};

pub fn to_parent_entry_extract_fn(
    entry: &SevenZArchiveEntry,
    reader: &mut dyn Read,
    dest: &PathBuf,
) -> Result<bool, Error> {
    if entry.is_directory() {
        if !dest.exists() {
            std::fs::create_dir_all(dest).map_err(Error::io)?;
        }
        return Ok(true);
    }

    let path = dest;
    if let Some(p) = path.parent() {
        if !p.exists() {
            let _ = std::fs::create_dir_all(p);
        }
    }

    // extract to parent directory safely without panicking on unwrap()
    let file_name = match path.file_name() {
        Some(name) => name,
        None => return Err(Error::other("Invalid archive entry file name")),
    };

    let target_parent = path
        .parent()
        .and_then(|p| p.parent())
        .or_else(|| path.parent())
        .unwrap_or(path.as_path());

    if !target_parent.exists() {
        std::fs::create_dir_all(target_parent).map_err(Error::io)?;
    }

    let to_path = target_parent.join(file_name);

    let file = File::create(&to_path)
        .map_err(|e| Error::Io(e, to_path.to_string_lossy().to_string().into()))?;
    if entry.size() == 0 {
        return Ok(true);
    }

    let mut writer = BufWriter::with_capacity(64 * 1024, file);
    copy(reader, &mut writer).map_err(Error::io)?;

    Ok(true)
}
