//! Troca do app instalado: implementa `ports::installer::AppInstaller`.

use std::io;
use std::path::Path;

use egeon_core::ports::installer::{AppInstaller, InstallError, Swap, UnpackedApp};

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
use macos as platform;
#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "linux")]
use linux as platform;
#[cfg(windows)]
mod windows;
#[cfg(windows)]
use windows as platform;

/// O instalador do sistema em que o programa roda.
#[derive(Debug, Clone, Copy, Default)]
pub struct SystemInstaller;

impl AppInstaller for SystemInstaller {
    fn can_install(&self, destination: &Path) -> bool {
        platform::can_install(destination)
    }

    fn unpack(&self, zip: &Path, into: &Path) -> Result<UnpackedApp, InstallError> {
        platform::unpack(zip, into)
    }

    fn stage(&self, app: &UnpackedApp, staged: &Path) -> Result<(), InstallError> {
        platform::stage(app, staged)
    }

    fn launch_swap(&self, swap: Swap<'_>) -> io::Result<()> {
        platform::launch_swap(swap)
    }
}
