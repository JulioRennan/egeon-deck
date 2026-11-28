//! Escuta local: o socket de controle e o pid de quem conecta.

use std::path::Path;

use egeon_core::ports::local_conn::{LocalConnDriver, LocalConnError, LocalListener, Probe};

#[cfg(unix)]
mod unix;
#[cfg(unix)]
use unix as platform;
#[cfg(windows)]
mod windows;
#[cfg(windows)]
use windows as platform;

/// O driver de conexão local do sistema em que o app roda.
#[derive(Debug, Default, Clone, Copy)]
pub struct SystemLocalConn;

impl LocalConnDriver for SystemLocalConn {
    fn listen(&self, path: &Path) -> Result<Box<dyn LocalListener>, LocalConnError> {
        platform::listen(path)
    }

    fn probe(&self, path: &Path) -> Probe {
        platform::probe(path)
    }
}
