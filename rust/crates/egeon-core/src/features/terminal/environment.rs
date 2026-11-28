//! Ambiente entregue aos processos filhos: terminais e agentes.
//!
//! Existe porque um app aberto pelo Finder não herda o shell de ninguém — recebe
//! o `PATH` mínimo do launchd — e `zsh -lc` não resolve: o `.zshrc`, onde a
//! maioria dos instaladores põe seus diretórios, só é lido em shell interativo.
//! O sintoma é sempre o mesmo e confuso: um binário que funciona no Terminal
//! vira "command not found" aqui. A regra é do app; quais diretórios de
//! instalador existem no sistema é do driver (`PtyDriver::path_dirs`).

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use crate::ports::pty::PtyDriver;

/// O ambiente-base de um filho: o do app, composto com os diretórios de
/// instalador que o driver conhece para este sistema.
pub fn for_child(pty: &dyn PtyDriver, cli_dir: &Path, strip: &[String]) -> Vec<(String, String)> {
    // Sem pasta pessoal não há diretórios de instalador: um `home` vazio os
    // viraria caminhos relativos no `PATH`.
    let dirs = std::env::var_os("HOME")
        .map(PathBuf::from)
        .or_else(std::env::home_dir)
        .map(|home| pty.path_dirs(&home))
        .unwrap_or_default();
    from_process(cli_dir, strip, &dirs)
}

/// O ambiente do próprio processo, composto para um filho. Variáveis que não são
/// UTF-8 ficam de fora: não há como entregá-las ao `PtySpec` e não fazem falta.
pub fn from_process(
    cli_dir: &Path,
    strip: &[String],
    path_dirs: &[PathBuf],
) -> Vec<(String, String)> {
    let parent = std::env::vars_os()
        .filter_map(|(key, value)| Some((key.into_string().ok()?, value.into_string().ok()?)))
        .filter(|(key, _)| !in_test_from_real_config(key));
    compose(parent, cli_dir, strip, path_dirs, |path| path.exists())
}

/// O `cargo test` costuma rodar dentro de um terminal de agente, com o
/// `CLAUDE_CONFIG_DIR` real no ambiente: herdado, um nó de teste gravaria a
/// confiança no `.claude.json` de verdade.
fn in_test_from_real_config(key: &str) -> bool {
    cfg!(test) && key == "CLAUDE_CONFIG_DIR"
}

/// Ambiente completo para um processo filho, a partir de `parent`.
///
/// As `CLAUDE_CODE*` saem porque, herdadas, fazem um agente aberto aqui se julgar
/// bancada filha de outro — e desligar transcript, entre outras esquisitices. A
/// procedência herdada (`strip`) sai pelo mesmo motivo: quem marca é o
/// terminal que vai lançar.
pub fn compose(
    parent: impl IntoIterator<Item = (String, String)>,
    cli_dir: &Path,
    strip: &[String],
    path_dirs: &[PathBuf],
    exists: impl Fn(&Path) -> bool,
) -> Vec<(String, String)> {
    let mut environment: BTreeMap<String, String> = parent
        .into_iter()
        .filter(|(key, _)| !key.starts_with("CLAUDE_CODE") && key != "CLAUDECODE")
        .filter(|(key, _)| !strip.contains(key))
        .collect();

    // Na frente de tudo: o `egeon` é do flavor que lançou este processo, e um
    // homônimo em /usr/local/bin faria o agente do dev falar com o socket do
    // estável.
    let key = path_key(&environment);
    let current = environment.get(&key).map(String::as_str);
    let mut parts = vec![cli_dir.to_string_lossy().into_owned()];
    parts.extend(enriched_parts(current, path_dirs, exists));
    environment.insert(key, join(&parts));
    environment.into_iter().collect()
}

/// A chave do `PATH`. No Windows ela costuma ser `Path` e não tem caixa: um
/// `PATH` novo ao lado do `Path` herdado deixaria o filho com dois, e qual
/// vale fica ao acaso. `PATH` exato ganha, como sempre no unix.
fn path_key(environment: &BTreeMap<String, String>) -> String {
    if environment.contains_key("PATH") {
        return "PATH".to_owned();
    }
    environment
        .keys()
        .find(|key| key.eq_ignore_ascii_case("PATH"))
        .cloned()
        .unwrap_or_else(|| "PATH".to_owned())
}

/// As entradas do `PATH`, com o separador do sistema (`:` no unix, `;` no
/// Windows).
fn split(path: &str) -> Vec<String> {
    std::env::split_paths(path)
        .map(|part| part.to_string_lossy().into_owned())
        .filter(|part| !part.is_empty())
        .collect()
}

/// O `PATH` de volta, com o separador do sistema. A entrada que contém o
/// próprio separador não cabe num `PATH` e fica de fora.
fn join(parts: &[String]) -> String {
    let valid = parts
        .iter()
        .filter(|part| std::env::join_paths([part.as_str()]).is_ok());
    std::env::join_paths(valid)
        .map(|joined| joined.to_string_lossy().into_owned())
        .unwrap_or_default()
}

/// Os diretórios de instalador que existem e ainda não estão no `PATH` entram na
/// frente, na ordem da lista: o que o usuário instalou ganha da versão que vem
/// com o sistema.
fn enriched_parts(
    current: Option<&str>,
    path_dirs: &[PathBuf],
    exists: impl Fn(&Path) -> bool,
) -> Vec<String> {
    let mut parts = split(current.unwrap_or(""));
    for candidate in path_dirs.iter().rev() {
        let text = candidate.to_string_lossy().into_owned();
        if !parts.contains(&text) && exists(candidate) {
            parts.insert(0, text);
        }
    }
    parts
}

#[cfg(test)]
fn enriched_path(
    current: Option<&str>,
    path_dirs: &[PathBuf],
    exists: impl Fn(&Path) -> bool,
) -> String {
    join(&enriched_parts(current, path_dirs, exists))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Os diretórios de instalador que o driver do macOS entrega, como exemplo.
    fn dirs() -> Vec<PathBuf> {
        [
            "/Users/x/.local/bin",
            "/Users/x/bin",
            "/Users/x/.cargo/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
        .map(PathBuf::from)
        .to_vec()
    }

    fn pairs(items: &[(&str, &str)]) -> Vec<(String, String)> {
        items
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    fn build(
        parent: &[(&str, &str)],
        strip: &[&str],
        exists: impl Fn(&Path) -> bool,
    ) -> Vec<(String, String)> {
        let strip: Vec<String> = strip.iter().map(|s| s.to_string()).collect();
        compose(
            pairs(parent),
            Path::new("/egeon/bin"),
            &strip,
            &dirs(),
            exists,
        )
    }

    fn get<'a>(environment: &'a [(String, String)], key: &str) -> Option<&'a str> {
        environment
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.as_str())
    }

    #[test]
    fn filho_nao_herda_variaveis_claude_code() {
        let result = build(
            &[
                ("CLAUDE_CODE_ENTRYPOINT", "cli"),
                ("CLAUDE_CODE_SSE_PORT", "1234"),
                ("CLAUDECODE", "1"),
                ("CLAUDE_CONFIG_DIR", "/perfil"),
                ("HOME", "/Users/x"),
                ("PATH", "/usr/bin"),
            ],
            &[],
            |_| false,
        );

        assert_eq!(get(&result, "CLAUDE_CODE_ENTRYPOINT"), None);
        assert_eq!(get(&result, "CLAUDE_CODE_SSE_PORT"), None);
        assert_eq!(get(&result, "CLAUDECODE"), None);
        // O que não começa com CLAUDE_CODE fica: é o perfil do usuário.
        assert_eq!(get(&result, "CLAUDE_CONFIG_DIR"), Some("/perfil"));
        assert_eq!(get(&result, "HOME"), Some("/Users/x"));
    }

    #[test]
    fn procedencia_herdada_sai_pela_lista_da_montagem() {
        let result = build(
            &[
                ("EGEON_NODE", "deck/claude-1"),
                ("EGEON_DECK", "dev.duckcoder.egeondeck"),
                ("EGEON_TARGET", "deck/claude-1"),
                ("EGEON_OUTRA", "fica"),
            ],
            &["EGEON_NODE", "EGEON_DECK", "EGEON_TARGET"],
            |_| false,
        );

        assert_eq!(get(&result, "EGEON_NODE"), None);
        assert_eq!(get(&result, "EGEON_DECK"), None);
        assert_eq!(get(&result, "EGEON_TARGET"), None);
        assert_eq!(get(&result, "EGEON_OUTRA"), Some("fica"));
    }

    /// Um `PATH` com o separador do sistema em que o teste roda.
    fn path(parts: &[&str]) -> String {
        join(&parts.iter().map(|p| p.to_string()).collect::<Vec<_>>())
    }

    #[test]
    fn cli_vai_na_frente_de_tudo_no_path() {
        let result = build(&[("PATH", &path(&["/usr/bin", "/bin"]))], &[], |_| false);

        assert_eq!(
            get(&result, "PATH"),
            Some(path(&["/egeon/bin", "/usr/bin", "/bin"]).as_str())
        );
    }

    /// No Windows a variável herdada é `Path`: o filho fica com ela, e não com
    /// duas.
    #[test]
    fn a_chave_do_path_herdado_e_mantida_sem_caixa() {
        let result = build(&[("Path", "/usr/bin")], &[], |_| false);

        assert_eq!(
            get(&result, "Path"),
            Some(path(&["/egeon/bin", "/usr/bin"]).as_str())
        );
        assert_eq!(get(&result, "PATH"), None);
        let both = build(&[("PATH", "/a"), ("Path", "/b")], &[], |_| false);
        assert_eq!(
            get(&both, "PATH"),
            Some(path(&["/egeon/bin", "/a"]).as_str())
        );
        assert_eq!(get(&both, "Path"), Some("/b"));
    }

    #[test]
    fn diretorios_existentes_entram_na_frente_na_ordem_da_lista() {
        let existentes = [
            PathBuf::from("/Users/x/.local/bin"),
            PathBuf::from("/opt/homebrew/bin"),
        ];
        let result = build(&[("PATH", "/usr/bin")], &[], |p| {
            existentes.iter().any(|e| e == p)
        });

        assert_eq!(
            get(&result, "PATH"),
            Some(
                path(&[
                    "/egeon/bin",
                    "/Users/x/.local/bin",
                    "/opt/homebrew/bin",
                    "/usr/bin"
                ])
                .as_str()
            )
        );
    }

    #[test]
    fn diretorio_que_ja_esta_no_path_nao_muda_de_lugar() {
        let current = path(&["/usr/bin", "/opt/homebrew/bin"]);
        let result = build(&[("PATH", &current)], &[], |p| {
            p == Path::new("/opt/homebrew/bin")
        });

        assert_eq!(
            get(&result, "PATH"),
            Some(path(&["/egeon/bin", "/usr/bin", "/opt/homebrew/bin"]).as_str())
        );
    }

    /// `testEnrichedPathKeepsCurrentAndDoesNotDuplicate`: enriquecer o que já
    /// foi enriquecido não muda nada.
    #[test]
    fn enriquecer_o_path_ja_enriquecido_nao_muda_nada() {
        let dirs = dirs();
        let current = path(&["/usr/bin", "/bin"]);
        let once = enriched_path(Some(&current), &dirs, |_| true);
        assert_ne!(once, current, "o teste precisa enriquecer de fato");
        assert_eq!(enriched_path(Some(&once), &dirs, |_| true), once);
    }

    #[test]
    fn sem_path_herdado_o_filho_ainda_recebe_o_cli() {
        let result = build(&[], &[], |p| p == Path::new("/usr/local/bin"));

        assert_eq!(
            get(&result, "PATH"),
            Some(path(&["/egeon/bin", "/usr/local/bin"]).as_str())
        );
    }
}
