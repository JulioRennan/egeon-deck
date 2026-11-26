//! A decisão do sistema sobre pastas protegidas: implementa
//! `ports::folder_access::FolderPermissions`.

use egeon_core::ports::folder_access::FolderPermissions;

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

/// O acesso a pastas do sistema em que o programa roda.
#[derive(Debug, Clone, Copy, Default)]
pub struct SystemFolderPermissions;

impl FolderPermissions for SystemFolderPermissions {
    fn reset(&self, service: &str) -> bool {
        platform::reset(service)
    }

    fn settings_url(&self) -> Option<String> {
        platform::settings_url()
    }
}
