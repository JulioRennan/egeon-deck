//! No Windows não há bit de execução: executa o que tem extensão do `PATHEXT`.

use std::path::Path;

/// O padrão do `PATHEXT` num Windows novo, para quando a variável falta.
const DEFAULT_PATHEXT: &str = ".COM;.EXE;.BAT;.CMD";

pub(super) fn is_executable(path: &Path) -> bool {
    let pathext = std::env::var("PATHEXT").unwrap_or_else(|_| DEFAULT_PATHEXT.to_owned());
    executable_with(path, &pathext)
}

fn executable_with(path: &Path, pathext: &str) -> bool {
    // Segue links, como o `PATH`; link quebrado e caminho que não existe, não.
    let Ok(meta) = std::fs::metadata(path) else {
        return false;
    };
    // Pasta conta, como o `access(X_OK)` de uma pasta com o bit de busca.
    if meta.is_dir() {
        return true;
    }
    let Some(ext) = path.extension().and_then(|e| e.to_str()) else {
        return false;
    };
    pathext
        .split(';')
        .filter_map(|known| known.strip_prefix('.'))
        .any(|known| known.eq_ignore_ascii_case(ext))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vale_a_extensao_do_pathext() -> std::io::Result<()> {
        let dir = tempfile::tempdir()?;
        let file = |name: &str| -> std::io::Result<std::path::PathBuf> {
            let path = dir.path().join(name);
            std::fs::write(&path, "")?;
            Ok(path)
        };
        assert!(executable_with(&file("a.exe")?, DEFAULT_PATHEXT));
        assert!(executable_with(&file("b.CMD")?, DEFAULT_PATHEXT));
        assert!(!executable_with(&file("c.txt")?, DEFAULT_PATHEXT));
        assert!(!executable_with(&file("sem-extensao")?, DEFAULT_PATHEXT));
        assert!(executable_with(dir.path(), DEFAULT_PATHEXT));
        assert!(!executable_with(
            &dir.path().join("nao.exe"),
            DEFAULT_PATHEXT
        ));
        assert!(executable_with(&file("d.ps1")?, ".EXE;.PS1"));
        Ok(())
    }
}
