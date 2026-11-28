//! O que um arrasto de arquivo sobre o terminal escreve nele: os caminhos,
//! como se digitam. Porte de `TerminalDrop` (a leitura do arrasto é da UI).

use std::io;
use std::path::{Path, PathBuf};

/// O texto a injetar, ou `None` se o arrasto não trouxe caminho. Espaço no
/// fim: o cursor fica pronto para a frase que acompanha o arquivo, que é o
/// motivo de você tê-lo arrastado até ali.
pub fn text(paths: &[&str]) -> Option<String> {
    if paths.is_empty() {
        return None;
    }
    let quoted: Vec<String> = paths.iter().map(|p| quoted(p)).collect();
    Some(quoted.join(" ") + " ")
}

/// Caminho como se digita: só ganha aspas quando precisa delas. Do outro lado
/// nem sempre há shell — num terminal com IA quem lê é um modelo, e `'…'` em
/// volta é ruído que não protege nada.
fn quoted(path: &str) -> String {
    let safe = |c: char| c.is_ascii_alphanumeric() || "_-./@%+=:,".contains(c);
    if !path.is_empty() && path.chars().all(safe) {
        return path.to_owned();
    }
    format!("'{}'", path.replace('\'', r"'\''"))
}

/// Grava a imagem que veio sem arquivo (arrastada do navegador) e devolve o
/// caminho dela. Em rascunho, e não em `~/.egeon`, que é feito para ser lido
/// à mão. Milissegundos no nome: duas imagens em seguida não se sobrescrevem.
pub fn save_image(png: &[u8], temp: &Path, flavor: &str, now_ms: u128) -> io::Result<PathBuf> {
    let dir = temp.join(format!("{flavor}-drop"));
    std::fs::create_dir_all(&dir)?;
    let file = dir.join(format!("drop-{now_ms}.png"));
    std::fs::write(&file, png)?;
    Ok(file)
}

#[cfg(test)]
mod tests {
    use super::*;

    // TerminalDropTests.testFileDropBecomesQuotedPathsWithTrailingSpace
    #[test]
    fn caminhos_citados_so_quando_precisa_e_espaco_no_fim() {
        assert_eq!(
            text(&["/tmp/um arquivo.pdf", "/tmp/outro.swift"]).as_deref(),
            Some("'/tmp/um arquivo.pdf' /tmp/outro.swift ")
        );
    }

    // TerminalDropTests.testEmptyPasteboardIsNothing
    #[test]
    fn arrasto_sem_caminho_nao_escreve_nada() {
        assert_eq!(text(&[]), None);
    }

    #[test]
    fn aspa_simples_no_caminho_e_escapada() {
        assert_eq!(quoted("/tmp/o'brien"), r"'/tmp/o'\''brien'");
        assert_eq!(quoted(""), "''");
        assert_eq!(
            quoted("/tmp/a-b_c.d@e%f+g=h:i,j"),
            "/tmp/a-b_c.d@e%f+g=h:i,j"
        );
    }

    #[test]
    fn imagem_sem_arquivo_vai_para_o_rascunho() -> io::Result<()> {
        let temp = tempfile::tempdir()?;
        let path = save_image(b"png", temp.path(), "egeon-next", 1234)?;
        assert_eq!(path, temp.path().join("egeon-next-drop/drop-1234.png"));
        assert_eq!(std::fs::read(&path)?, b"png");
        Ok(())
    }
}
