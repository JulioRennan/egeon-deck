//! Pty: lançar um processo atrás de um terminal virtual.

use std::path::{Path, PathBuf};

use egeon_core::ports::pty::{PtyChild, PtyDriver, PtyError, PtySpec};

use crate::environment;

#[cfg(unix)]
mod unix;

/// O driver de pty do sistema em que o app roda.
#[derive(Debug, Default, Clone, Copy)]
pub struct SystemPty;

#[cfg(unix)]
impl PtyDriver for SystemPty {
    fn spawn(&self, spec: PtySpec) -> Result<PtyChild, PtyError> {
        unix::spawn(spec)
    }

    fn path_dirs(&self, home: &Path) -> Vec<PathBuf> {
        environment::path_dirs(home)
    }

    fn user_shell(&self) -> PathBuf {
        environment::user_shell()
    }
}
