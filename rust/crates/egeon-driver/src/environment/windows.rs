use std::path::{Path, PathBuf};

/// Diretórios que instaladores usam sem passar pelo `PATH` do sistema, ou
/// que entraram no `PATH` do usuário depois que a sessão abriu (o app aberto
/// pelo Explorer herda o `PATH` do login). A ordem importa, como no unix: o
/// que o usuário instalou ganha.
pub(super) fn candidates(home: &Path) -> Vec<PathBuf> {
    let mut dirs = vec![
        // O instalador nativo do Claude Code põe o `claude.exe` aqui.
        home.join(".local").join("bin"),
        home.join(".bun").join("bin"),
        home.join(".cargo").join("bin"),
        home.join("scoop").join("shims"),
        home.join("fvm").join("default").join("bin"),
    ];
    // O `npm i -g` do Node para Windows.
    if let Some(appdata) = std::env::var_os("APPDATA") {
        dirs.push(PathBuf::from(appdata).join("npm"));
    }
    dirs
}

/// O PowerShell do Windows (5.1), que existe em qualquer Windows (decisão
/// 54): caminho fixo, como o `/bin/zsh` do macOS.
pub(super) fn shell() -> PathBuf {
    system_root()
        .join("System32")
        .join("WindowsPowerShell")
        .join("v1.0")
        .join("powershell.exe")
}

fn system_root() -> PathBuf {
    std::env::var_os("SystemRoot")
        .filter(|root| !root.is_empty())
        .map_or_else(|| PathBuf::from(r"C:\Windows"), PathBuf::from)
}

/// A pasta do usuário: o `%USERPROFILE%`. O `HOME` que o Git Bash define não
/// vale aqui, para a pasta de dados ser a mesma aberto de onde for.
pub(super) fn home() -> Option<PathBuf> {
    std::env::var_os("USERPROFILE")
        .filter(|home| !home.is_empty())
        .map(PathBuf::from)
}
