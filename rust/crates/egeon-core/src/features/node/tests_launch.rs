//! A linha de comando, o catálogo, o ambiente e o gancho do shell, contra o
//! código REAL do Swift: `fixtures/org/oraculo/gerar.sh` extrai `launchPlan`,
//! `catalog` e `conversationCommand` do `main.swift` sem alterar, compila com o
//! `AgentProfile`, o `AgentRules` e o `ShellHook` de `legado/`, e grava o que eles
//! produzem em `fixtures/org/esperado/{launch,zsh,perfis}`.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::Deserialize;
use serde_json::Value;

use super::launch::*;
use super::model::{NodeConfig, NodeKind};
use crate::features::agent::model::AgentProfile;
use crate::features::json_file::parse;
use crate::features::terminal::shell::ShellSyntax;

/// O mesmo caminho que o `stub` do oráculo usa para o `claude-hooks.json`.
const HOOK_FILE: &str = "/oraculo/claude-hooks.json";

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("fixtures/org")
}

fn read(path: &Path) -> Vec<u8> {
    std::fs::read(path).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
}

fn profiles() -> BTreeMap<String, AgentProfile> {
    // Os perfis padrão que o Swift grava no `agents.json` de quem não tem um.
    parse(&read(&root().join("esperado/perfis/agents.json"))).unwrap()
}

#[derive(Deserialize)]
struct Case {
    node: NodeConfig,
    profile: Option<String>,
    rules: Option<String>,
}

fn cases() -> Vec<(String, Case)> {
    let dir = root().join("entrada/launch");
    let mut found: Vec<_> = std::fs::read_dir(&dir)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|e| e == "json"))
        .map(|p| {
            (
                p.file_name().unwrap().to_string_lossy().into_owned(),
                parse(&read(&p)).unwrap(),
            )
        })
        .collect();
    found.sort_by(|a, b| a.0.cmp(&b.0));
    assert!(found.len() >= 10);
    found
}

#[test]
fn a_linha_de_comando_o_catalogo_e_as_regras_saem_como_no_swift() {
    let agents = profiles();
    for (name, case) in cases() {
        let profile = case.profile.as_deref().and_then(|k| agents.get(k));
        let catalog = catalog(&case.node, ShellSyntax::Posix);
        let rules = rules_for(&case.node, case.rules.as_deref());
        let plan = launch_plan(
            &case.node,
            profile,
            catalog.as_deref(),
            rules.as_deref(),
            HOOK_FILE,
            DEFAULT_SHELL,
            ShellSyntax::Posix,
        );

        let expected: Value = parse(&read(&root().join("esperado/launch").join(&name))).unwrap();
        let text = |key: &str| expected[key].as_str().map(str::to_owned);
        assert_eq!(
            Some(plan.command.clone()),
            text("command"),
            "{name}: command"
        );
        assert_eq!(plan.prompt_to_inject, text("prompt"), "{name}: prompt");
        assert_eq!(
            plan.hooked,
            expected["hooked"].as_bool().unwrap(),
            "{name}: hooked"
        );
        assert_eq!(catalog, text("catalog"), "{name}: catalog");
        assert_eq!(rules, text("rules"), "{name}: rules");
    }
}

#[test]
fn os_arquivos_do_gancho_do_shell_sao_os_do_swift() {
    let files = shell_hook_files();
    assert_eq!(
        files.iter().map(|(n, _)| *n).collect::<Vec<_>>(),
        [".zshenv", ".zprofile", ".zlogin", ".zshrc"]
    );
    for (name, body) in files {
        let expected = String::from_utf8(read(&root().join("esperado/zsh").join(name))).unwrap();
        assert_eq!(body, expected, "{name}");
    }
}

#[test]
fn o_gancho_e_escrito_a_cada_arranque() {
    let dir = tempfile::tempdir().unwrap();
    let target = dir.path().join("zsh");
    assert!(install_shell_hook(&target).is_empty());
    let zshrc = std::fs::read_to_string(target.join(".zshrc")).unwrap();
    assert!(zshrc.contains("add-zsh-hook preexec _egeon_trace_preexec"));
    // Reescreve por cima: "Gerado a cada arranque; não edite".
    std::fs::write(target.join(".zshrc"), "meu").unwrap();
    install_shell_hook(&target);
    assert_ne!(
        std::fs::read_to_string(target.join(".zshrc")).unwrap(),
        "meu"
    );
    // Pasta que não dá para criar vira aviso, não erro.
    let blocked = dir.path().join("arquivo");
    std::fs::write(&blocked, "").unwrap();
    assert_eq!(install_shell_hook(&blocked.join("zsh")).len(), 1);
}

// ── O ambiente do processo ─────────────────────────────────────────────────

fn ctx<'a>(base: Vec<(String, String)>, zsh: &'a Path, home: &'a Path) -> ChildContext<'a> {
    ChildContext {
        base,
        address: "deck/dev",
        deck: "egeon-next",
        egeon_home: "/Users/eu/.egeon-next",
        flavor: "dev",
        zsh_dir: zsh,
        home,
    }
}

fn get<'a>(env: &'a [(String, String)], key: &str) -> Option<&'a str> {
    env.iter().find(|(k, _)| k == key).map(|(_, v)| v.as_str())
}

fn claude() -> AgentProfile {
    profiles().remove("claude").unwrap()
}

#[test]
fn ambiente_de_agente_leva_o_alvo_a_procedencia_e_a_configuracao() {
    let base = vec![("PATH".to_owned(), "/egeon:/usr/bin".to_owned())];
    let zsh = Path::new("/d/zsh");
    let home = Path::new("/Users/eu");
    let mut node = NodeConfig::new(NodeKind::Agent, "dev");
    node.agent = Some("claude".into());
    node.config = Some("/Users/eu/.claude-agro".into());
    node.effort = Some("max".into());
    node.ultracode = Some(true);
    let profile = claude();

    let (env, notes) = node_environment(&node, Some(&profile), &ctx(base, zsh, home));
    assert_eq!(get(&env, "PATH"), Some("/egeon:/usr/bin"));
    assert_eq!(get(&env, "TERM"), Some("xterm-256color"));
    assert_eq!(get(&env, "EGEON_TARGET"), Some("deck/dev"));
    assert_eq!(get(&env, "EGEON_NODE"), Some("deck/dev"));
    assert_eq!(get(&env, "EGEON_DECK"), Some("egeon-next"));
    assert_eq!(get(&env, "EGEON_HOME"), Some("/Users/eu/.egeon-next"));
    assert_eq!(get(&env, "EGEON_FLAVOR"), Some("dev"));
    assert_eq!(
        get(&env, "CLAUDE_CONFIG_DIR"),
        Some("/Users/eu/.claude-agro")
    );
    assert_eq!(
        notes,
        ["terminal[deck/dev]: CLAUDE_CONFIG_DIR=/Users/eu/.claude-agro"]
    );
    // Agente não leva o `ZDOTDIR` do shell.
    assert_eq!(get(&env, "ZDOTDIR"), None);
    // Ultracode ocupa a flag do esforço, e o nível vai pelo ambiente.
    let level = profile.effort_env.clone().unwrap();
    assert_eq!(get(&env, &level), Some("max"));
    // Chave que o app põe aparece uma vez só.
    assert_eq!(env.iter().filter(|(k, _)| k == "EGEON_NODE").count(), 1);
}

#[test]
fn ambiente_de_shell_leva_o_zdotdir_e_nao_o_alvo() {
    let node = NodeConfig::new(NodeKind::Shell, "sh");
    let base = vec![
        ("ZDOTDIR".to_owned(), "/herdado".to_owned()),
        ("A".to_owned(), "1".to_owned()),
    ];
    let zsh = Path::new("/d/zsh");
    let (env, notes) = node_environment(&node, None, &ctx(base, zsh, Path::new("/h")));
    assert_eq!(get(&env, "ZDOTDIR"), Some("/d/zsh"));
    assert_eq!(env.iter().filter(|(k, _)| k == "ZDOTDIR").count(), 1);
    assert_eq!(
        get(&env, "EGEON_TARGET"),
        None,
        "shell não tem conversa para rastrear"
    );
    assert_eq!(
        get(&env, "EGEON_NODE"),
        Some("deck/dev"),
        "a procedência vai em todo nó"
    );
    assert_eq!(get(&env, "A"), Some("1"));
    assert_eq!(get(&env, "EGEON_HOME"), Some("/Users/eu/.egeon-next"));
    assert!(notes.is_empty());
}

#[test]
fn o_ambiente_do_perfil_e_resolvido_e_o_do_no_vence() {
    let mut profile = claude();
    profile.env = Some(BTreeMap::from([
        (
            "CLAUDE_CONFIG_DIR".to_owned(),
            "~/.claude-padrao".to_owned(),
        ),
        ("OUTRA".to_owned(), "$HOME/x".to_owned()),
    ]));
    let mut node = NodeConfig::new(NodeKind::Agent, "dev");
    let home = Path::new("/Users/eu");
    let (env, _) = node_environment(&node, Some(&profile), &ctx(vec![], Path::new("/z"), home));
    assert_eq!(
        get(&env, "CLAUDE_CONFIG_DIR"),
        Some("/Users/eu/.claude-padrao")
    );
    assert_eq!(get(&env, "OUTRA"), Some("/Users/eu/x"));
    node.config = Some("/escolhida".into());
    let (env, _) = node_environment(&node, Some(&profile), &ctx(vec![], Path::new("/z"), home));
    assert_eq!(get(&env, "CLAUDE_CONFIG_DIR"), Some("/escolhida"));
}

// ── Casos que o oráculo não cobre por serem do app novo ────────────────────

#[test]
fn nota_de_log_quando_o_marcador_nao_sobe() {
    let agents = profiles();
    let case = cases()
        .into_iter()
        .find(|(n, _)| n == "codex-sem-papel.json")
        .unwrap()
        .1;
    let plan = launch_plan(
        &case.node,
        agents.get("codex"),
        catalog(&case.node, ShellSyntax::Posix).as_deref(),
        None,
        HOOK_FILE,
        DEFAULT_SHELL,
        ShellSyntax::Posix,
    );
    assert_eq!(plan.command, "codex '--model' 'gpt-5'");
    assert_eq!(plan.prompt_to_inject, None);
    assert_eq!(plan.notes.len(), 1);
    assert!(
        plan.notes[0].starts_with("agente Codex CLI: sem flag de system prompt"),
        "{:?}",
        plan.notes
    );
}

#[test]
fn so_agente_tem_catalogo_e_o_maestro_e_o_aprovador_somam_secoes() {
    let mut node = NodeConfig::new(NodeKind::Agent, "a");
    let plain = catalog(&node, ShellSyntax::Posix).unwrap();
    assert!(plain.starts_with("Este terminal é um nó do Egeon Deck"));
    assert!(!plain.contains("MAESTRO"));
    node.maestro = Some(true);
    let maestro = catalog(&node, ShellSyntax::Posix).unwrap();
    assert!(maestro.contains("Você é o MAESTRO desta bancada"));
    assert!(
        maestro.contains("O usuário também te deu o poder de responder os pedidos de permissão")
    );
    assert_eq!(
        catalog(&NodeConfig::new(NodeKind::Shell, "s"), ShellSyntax::Posix),
        None
    );
    assert_eq!(
        catalog(
            &NodeConfig::new(NodeKind::Web, "w"),
            ShellSyntax::PowerShell
        ),
        None
    );
}

#[test]
fn flavor_estavel_nao_exporta_a_variavel() {
    let zsh = Path::new("/z");
    let home = Path::new("/Users/eu");
    // Nem vazia, nem herdada: o `egeon` sem ela já acha o app estável.
    let base = vec![("EGEON_FLAVOR".to_owned(), "dev".to_owned())];
    let mut stable = ctx(base, zsh, home);
    stable.flavor = "";
    let shell = NodeConfig::new(NodeKind::Shell, "sh");
    let (env, _) = node_environment(&shell, None, &stable);
    assert_eq!(get(&env, "EGEON_FLAVOR"), None);
    assert_eq!(get(&env, "EGEON_HOME"), Some("/Users/eu/.egeon-next"));

    let (env, _) = node_environment(&shell, None, &ctx(vec![], zsh, home));
    assert_eq!(get(&env, "EGEON_FLAVOR"), Some("dev"));
}

// Decisão 54: no PowerShell o catálogo manda o UTF-8 sem BOM e o
// here-string; o resto do texto é o mesmo do macOS.
#[test]
fn no_powershell_o_catalogo_manda_o_utf8_e_o_here_string() {
    let mut node = NodeConfig::new(NodeKind::Agent, "a");
    node.maestro = Some(true);
    let posix = catalog(&node, ShellSyntax::Posix).unwrap();
    let powershell = catalog(&node, ShellSyntax::PowerShell).unwrap();
    assert!(posix.contains("egeon send <endereço> <<'MB'"));
    assert!(!posix.contains("$OutputEncoding"));
    assert!(!powershell.contains("<<'"), "{powershell}");
    assert!(
        powershell.contains(
            "\n$OutputEncoding = [Text.UTF8Encoding]::new($false)\n@'\n(o que você quer dizer)\n'@ | egeon send <endereço>\n@'\npedido: … — entrega: …\n'@ | egeon trace\n"
        ),
        "{powershell}"
    );
    let tail = |text: &str| text[text.find("Mensagem que chega").unwrap()..].to_owned();
    assert_eq!(tail(&powershell), tail(&posix));
    assert!(powershell.starts_with("Este terminal é um nó do Egeon Deck"));
}

/// No PowerShell (Windows, decisão 54) a mesma linha sai na sintaxe dele: sem
/// `||`, que o 5.1 não tem, e com a aspa simples dobrada em vez de `'\''`.
#[test]
fn no_powershell_a_retomada_e_as_aspas_saem_no_jeito_dele() {
    let agents = profiles();
    for name in [
        "claude-retomando.json",
        "a04-conversa-hostil.json",
        "a18-aspa-isolada.json",
    ] {
        let case = cases().into_iter().find(|(n, _)| n == name).unwrap().1;
        let profile = case.profile.as_deref().and_then(|k| agents.get(k));
        let plan = |syntax| {
            launch_plan(
                &case.node,
                profile,
                catalog(&case.node, syntax).as_deref(),
                rules_for(&case.node, case.rules.as_deref()).as_deref(),
                HOOK_FILE,
                DEFAULT_SHELL,
                syntax,
            )
            .command
        };
        let (posix, powershell) = (plan(ShellSyntax::Posix), plan(ShellSyntax::PowerShell));
        assert!(!powershell.contains(" || "), "{name}: {powershell}");
        assert!(!powershell.contains(r"'\''"), "{name}: {powershell}");
        if posix.contains(" || ") {
            assert!(
                powershell.contains("; if ($LASTEXITCODE) { "),
                "{name}: {powershell}"
            );
        }
    }
}
