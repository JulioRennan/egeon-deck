use std::io;
use std::path::Path;

/// O Windows separa link de pasta e de arquivo: o tipo vem do alvo, resolvido
/// a partir da pasta do link quando é relativo. Alvo que não existe vira link
/// de arquivo. Criar link pede o modo de desenvolvedor ou administrador.
pub fn symlink(target: &Path, link: &Path) -> io::Result<()> {
    let resolved = match link.parent() {
        Some(parent) if target.is_relative() => parent.join(target),
        _ => target.to_path_buf(),
    };
    if resolved.is_dir() {
        std::os::windows::fs::symlink_dir(target, link)
    } else {
        std::os::windows::fs::symlink_file(target, link)
    }
}

/// Sem bit de execução no Windows: basta o arquivo existir.
pub fn make_executable(path: &Path) -> io::Result<()> {
    std::fs::metadata(path).map(|_| ())
}
