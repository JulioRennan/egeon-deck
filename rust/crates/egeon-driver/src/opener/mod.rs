//! Abrir arquivo ou URL com o app padrão: implementa `ports::opener::Opener`.

use egeon_core::ports::opener::{OpenTarget, Opener};

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
use macos as platform;

/// O abridor do sistema em que o programa roda.
#[derive(Debug, Clone, Copy, Default)]
pub struct SystemOpener;

impl Opener for SystemOpener {
    fn open(&self, target: &OpenTarget) -> bool {
        platform::open(target)
    }

    fn beep(&self) {
        platform::beep();
    }
}
