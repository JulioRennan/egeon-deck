//! Se um arquivo é executável: o bit de execução é coisa do sistema de arquivos
//! de cada plataforma (no Windows vale a extensão).

use std::path::Path;

#[cfg(unix)]
mod unix;
#[cfg(unix)]
use unix as platform;
#[cfg(windows)]
mod windows;
#[cfg(windows)]
use windows as platform;

/// O que o sistema deixa executar a quem roda (`access(X_OK)` no unix). Como no
/// Swift, pasta com o bit de busca conta; link quebrado, arquivo sem o bit e
/// caminho que não existe, não.
pub fn is_executable(path: &Path) -> bool {
    platform::is_executable(path)
}

#[cfg(all(test, unix))]
mod tests {
    use std::fs;
    use std::os::unix::fs::{PermissionsExt, symlink};

    use super::*;

    #[test]
    fn vale_o_bit_de_execucao_de_quem_roda() -> std::io::Result<()> {
        let dir = tempfile::tempdir()?;
        let file = |name: &str, mode: u32| -> std::io::Result<std::path::PathBuf> {
            let path = dir.path().join(name);
            fs::write(&path, "#!/bin/sh\n")?;
            fs::set_permissions(&path, fs::Permissions::from_mode(mode))?;
            Ok(path)
        };
        assert!(is_executable(&file("x", 0o755)?));
        assert!(is_executable(&file("so-dono", 0o700)?));
        assert!(!is_executable(&file("sem-x", 0o644)?));
        assert!(
            is_executable(dir.path()),
            "pasta com x: access(X_OK) é true, como no Swift"
        );
        symlink(dir.path().join("x"), dir.path().join("atalho"))?;
        assert!(
            is_executable(&dir.path().join("atalho")),
            "link para executável"
        );
        symlink(dir.path().join("nada"), dir.path().join("quebrado"))?;
        assert!(!is_executable(&dir.path().join("quebrado")));
        assert!(!is_executable(&dir.path().join("nao-existe")));
        assert!(!is_executable(Path::new("com\0nul")));
        Ok(())
    }
}
