//! Link simbólico e bit de execução: implementa `ports::links::FileLinks`.

use std::io;
use std::path::Path;

use egeon_core::ports::links::FileLinks;

#[cfg(unix)]
mod unix;
#[cfg(unix)]
use unix as platform;

/// Os links do sistema em que o programa roda.
#[derive(Debug, Default, Clone, Copy)]
pub struct SystemLinks;

impl FileLinks for SystemLinks {
    fn symlink(&self, target: &Path, link: &Path) -> io::Result<()> {
        platform::symlink(target, link)
    }

    fn make_executable(&self, path: &Path) -> io::Result<()> {
        platform::make_executable(path)
    }
}
