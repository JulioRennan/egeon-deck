//! A primeira versão do Windows sai em zip, sem instalador nem troca
//! automática (decisão 54): o app não se troca sozinho, e o core trata o
//! `can_install` falso como no `.deb` do Linux.

use std::io;
use std::path::Path;

use egeon_core::ports::installer::{InstallError, Swap, UnpackedApp};

pub(super) fn can_install(_destination: &Path) -> bool {
    false
}

pub(super) fn unpack(_zip: &Path, _into: &Path) -> Result<UnpackedApp, InstallError> {
    Err(not_installable())
}

pub(super) fn stage(_app: &UnpackedApp, _staged: &Path) -> Result<(), InstallError> {
    Err(not_installable())
}

pub(super) fn launch_swap(_swap: Swap<'_>) -> io::Result<()> {
    Err(io::Error::from(io::ErrorKind::Unsupported))
}

fn not_installable() -> InstallError {
    InstallError::NotInstallable("o Windows não se atualiza sozinho nesta versão".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nada_se_troca_no_windows() {
        let here = Path::new(r"C:\Egeon\EgeonDeck.exe");
        assert!(!can_install(here));
        assert!(unpack(here, here).is_err());
    }
}
