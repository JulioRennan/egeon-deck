//! Link simbólico e bit de execução: implementa `ports::links::FileLinks`.

use std::io;
use std::path::Path;

use egeon_core::ports::links::FileLinks;

#[cfg(unix)]
mod unix;
#[cfg(unix)]
use unix as platform;
#[cfg(windows)]
mod windows;
#[cfg(windows)]
use windows as platform;

/// Os links do sistema em que o programa roda.
#[derive(Debug, Default, Clone, Copy)]
pub struct SystemLinks;

/// O link do sistema, para a cópia comum do `file_clone`.
pub(crate) fn symlink(target: &Path, link: &Path) -> io::Result<()> {
    platform::symlink(target, link)
}

impl FileLinks for SystemLinks {
    fn symlink(&self, target: &Path, link: &Path) -> io::Result<()> {
        platform::symlink(target, link)
    }

    fn make_executable(&self, path: &Path) -> io::Result<()> {
        platform::make_executable(path)
    }
}
