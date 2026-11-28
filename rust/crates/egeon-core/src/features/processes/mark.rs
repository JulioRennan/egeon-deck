//! A procedência de um processo: o nó que o lançou e o flavor do app.
//!
//! Vai no ambiente, e não no nome do processo, porque o ambiente é herdado
//! por tudo que o terminal abre — node, python, o Chrome do Playwright — e
//! continua lá quando o pai morre e o processo vira filho do launchd. É
//! justamente o órfão que precisa dizer de onde veio: pela árvore, ele já não
//! diz.

use std::collections::HashMap;

pub const NODE: &str = "EGEON_NODE";
pub const DECK: &str = "EGEON_DECK";
/// O endereço que os ganchos dos agentes usam (`ClaudeHooks.targetVariable`).
pub const TARGET: &str = "EGEON_TARGET";
/// Posto pelo launchd em quem ele abre como app, e herdado dali para baixo.
pub const BUNDLE_VARIABLE: &str = "__CFBundleIdentifier";
/// O do estável, o do dev e o do app novo (`.next`).
pub const BUNDLE_PREFIX: &str = "dev.duckcoder.egeondeck";

/// Saem do ambiente herdado antes de marcar. O app lançado de dentro de um
/// terminal do Egeon herdava o endereço daquele terminal, e todo shell aberto
/// por ele saía com a procedência errada.
pub const INHERITED: [&str; 3] = [NODE, DECK, TARGET];

pub fn stamp(environment: &mut Vec<(String, String)>, address: &str, deck: &str) {
    environment.retain(|(key, _)| key != NODE && key != DECK);
    environment.push((NODE.to_owned(), address.to_owned()));
    environment.push((DECK.to_owned(), deck.to_owned()));
}

/// O nó escrito no ambiente. Processo de antes da marca só tem o
/// `EGEON_TARGET` dos agentes — ainda serve para dizer de quem é.
pub fn node_in(environment: &HashMap<String, String>) -> Option<&str> {
    environment
        .get(NODE)
        .or_else(|| environment.get(TARGET))
        .map(String::as_str)
}

/// `INHERITED` como a lista que o ambiente do filho pede: o que o Swift tira
/// em toda chamada de `forChildProcess`, também no git do usuário.
pub fn inherited() -> Vec<String> {
    INHERITED.iter().map(|v| (*v).to_owned()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn marca_o_no_e_o_deck_sem_repetir() {
        let mut env = vec![
            ("PATH".to_owned(), "/bin".to_owned()),
            (NODE.to_owned(), "velho/x".to_owned()),
        ];
        stamp(&mut env, "deck/claude", "egeon-next");
        assert_eq!(
            env,
            [
                ("PATH".to_owned(), "/bin".to_owned()),
                (NODE.to_owned(), "deck/claude".to_owned()),
                (DECK.to_owned(), "egeon-next".to_owned()),
            ]
        );
    }

    #[test]
    fn no_vem_da_marca_ou_do_alvo_antigo() {
        let env = |pairs: &[(&str, &str)]| -> HashMap<String, String> {
            pairs
                .iter()
                .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
                .collect()
        };
        assert_eq!(
            node_in(&env(&[(NODE, "a/b"), (TARGET, "c/d")])),
            Some("a/b")
        );
        assert_eq!(node_in(&env(&[(TARGET, "c/d")])), Some("c/d"));
        assert_eq!(node_in(&env(&[])), None);
    }
}
