//! Os diretórios de binários que um app aberto pelo Finder não enxerga.
//!
//! No macOS o app recebe o `PATH` mínimo do launchd, e `zsh -lc` não resolve: o `.zshrc`,
//! onde a maioria dos instaladores põe seus diretórios, só é lido em shell
//! interativo. Quais diretórios são esses depende do sistema, e é só isso que
//! fica aqui; compor o ambiente do filho é do core
//! (`features::terminal::environment`).

use std::path::{Path, PathBuf};

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
use macos::{candidates, shell};
#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "linux")]
use linux::{candidates, shell};
#[cfg(windows)]
mod windows;
#[cfg(windows)]
use windows::{candidates, shell};

// Sem lista de instaladores conhecida, o `PATH` herdado segue como está.
#[cfg(not(any(target_os = "macos", target_os = "linux", windows)))]
fn candidates(_home: &Path) -> Vec<PathBuf> {
    Vec::new()
}

#[cfg(not(any(target_os = "macos", target_os = "linux", windows)))]
fn shell() -> PathBuf {
    PathBuf::from("/bin/sh")
}

/// O shell em que os terminais sobem (decisão 53).
pub fn user_shell() -> PathBuf {
    shell()
}

/// A pasta do usuário: o `HOME` no unix, o `%USERPROFILE%` no Windows. É a
/// base da pasta de dados (`~/.egeon-next`) e a pasta padrão dos terminais.
pub fn home_dir() -> Option<PathBuf> {
    #[cfg(windows)]
    let home = windows::home();
    #[cfg(not(windows))]
    let home = std::env::var_os("HOME")
        .filter(|home| !home.is_empty())
        .map(PathBuf::from);
    home
}

/// Os diretórios de instalador deste sistema, na ordem em que entram na frente
/// do `PATH`.
pub fn path_dirs(home: &Path) -> Vec<PathBuf> {
    candidates(home)
}

#[cfg(all(test, target_os = "macos"))]
mod tests {
    use super::*;

    #[test]
    fn o_que_o_usuario_instalou_vem_antes_do_que_veio_com_o_sistema() {
        let dirs = path_dirs(Path::new("/Users/x"));
        let at = |wanted: &str| dirs.iter().position(|d| d == Path::new(wanted));
        assert!(at("/Users/x/.local/bin") < at("/opt/homebrew/bin"));
        assert!(at("/opt/homebrew/bin") < at("/usr/local/bin"));
        assert!(at("/Users/x/.cargo/bin").is_some());
    }
}

#[cfg(all(test, target_os = "linux"))]
mod linux_tests {
    use super::*;

    #[test]
    fn o_que_o_usuario_instalou_vem_antes_do_que_veio_com_o_sistema() {
        let dirs = path_dirs(Path::new("/home/x"));
        let at = |wanted: &str| dirs.iter().position(|d| d == Path::new(wanted));
        assert!(at("/home/x/.local/bin") < at("/home/linuxbrew/.linuxbrew/bin"));
        assert!(at("/home/linuxbrew/.linuxbrew/bin") < at("/usr/local/bin"));
        assert!(at("/home/x/.cargo/bin").is_some());
    }
}
