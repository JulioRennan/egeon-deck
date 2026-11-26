//! Regras puras do nó de terminal, porte do `TerminalNode` e do `Dispatcher`.

/// O shell que lança todo terminal no macOS, como no Swift: o comando é
/// montado como linha e entregue a `zsh -lc`. No Linux é o do usuário
/// (`shell::LaunchShell`, decisão 53).
pub const LAUNCH_SHELL: &str = "/bin/zsh";

/// O `TERM` de todo filho, por cima do que vier do ambiente do app.
pub const TERM: &str = "xterm-256color";

/// Aspas simples de shell: pasta ou papel com aspas, `$` ou `;` não vira
/// execução.
pub fn shell_quote(text: &str) -> String {
    format!("'{}'", text.replace('\'', r"'\''"))
}

/// Os bytes de uma colagem: embrulhada nos marcadores do bracketed paste
/// quando o programa ligou o modo 2004, crua quando não — como o SwiftTerm faz
/// no app de hoje. O texto vai como veio.
///
/// Divergência conhecida: com o protocolo de teclado do kitty ligado e o 2004
/// desligado, o SwiftTerm manda a colagem como evento de texto do kitty
/// (`MacTerminalView.swift:1625-1659`); aqui ela vai crua. Quem liga o kitty
/// liga o 2004 junto, então hoje não aparece.
pub fn paste_bytes(text: &str, bracketed: bool) -> Vec<u8> {
    if !bracketed {
        return text.as_bytes().to_vec();
    }
    let mut out = Vec::with_capacity(text.len() + 12);
    out.extend_from_slice(b"\x1b[200~");
    out.extend_from_slice(text.as_bytes());
    out.extend_from_slice(b"\x1b[201~");
    out
}

/// O que o `peek` devolve: as linhas visíveis sem as em branco, e só as
/// últimas `count` — ler só as últimas da grade devolveria vazio num terminal
/// que ainda não encheu a tela.
pub fn peek_lines(rows: Vec<String>, count: usize) -> Vec<String> {
    let visible: Vec<String> = rows
        .into_iter()
        .map(|row| row.trim_end().to_owned())
        .filter(|row| !row.is_empty())
        .collect();
    let skip = visible.len().saturating_sub(count);
    visible.into_iter().skip(skip).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    // Porte de AppEnvironmentTests.testShellQuoteNeutralizesMetacharacters.
    #[test]
    fn shell_quote_neutraliza_metacaracteres() {
        assert_eq!(shell_quote("simples"), "'simples'");
        assert_eq!(
            shell_quote("com espaço $HOME; rm"),
            "'com espaço $HOME; rm'"
        );
        assert_eq!(shell_quote("o'brien"), r"'o'\''brien'");
    }

    #[test]
    fn colagem_so_embrulha_com_o_modo_ligado() {
        assert_eq!(paste_bytes("ls\nrm x", false), b"ls\nrm x");
        assert_eq!(paste_bytes("ls\nrm x", true), b"\x1b[200~ls\nrm x\x1b[201~");
        assert_eq!(paste_bytes("", true), b"\x1b[200~\x1b[201~");
    }

    #[test]
    fn peek_descarta_brancos_e_pega_as_ultimas() {
        let rows = ["$ ls", "", "a  b  ", "   ", "$ "]
            .into_iter()
            .map(String::from)
            .collect::<Vec<_>>();
        assert_eq!(peek_lines(rows.clone(), 20), vec!["$ ls", "a  b", "$"]);
        assert_eq!(peek_lines(rows, 2), vec!["a  b", "$"]);
        assert!(peek_lines(vec![String::new(); 24], 5).is_empty());
    }
}
