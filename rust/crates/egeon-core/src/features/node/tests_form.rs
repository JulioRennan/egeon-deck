//! O formulário de terminal (`NodeTemplateDialog`): listas, o que ele grava e
//! a regra do "mesmo processo" do `editNode`.

use std::collections::BTreeMap;

use super::form::{
    self, DEFAULT_MODEL_OPTION, FormFields, ScreenRequest, Shown, effort_items, finish,
    model_items, normalized_folder, same_process, stored_folder,
};
use super::model::{NodeConfig, NodeKind, NodeTemplate, Overrides};
use super::service::instantiate;
use crate::features::agent::claude::profile::claude_code;
use crate::features::agent::model::AgentProfile;
use crate::features::agent::model_catalog::{CatalogModel, ModelCatalog};

const HOME: &str = "/Users/voce";

fn catalog() -> ModelCatalog {
    ModelCatalog::new(
        vec![
            CatalogModel::new("claude-opus-5-5", "opus", "Opus 5.5"),
            CatalogModel::new("claude-sonnet-5-5", "sonnet", "Sonnet 5.5"),
        ],
        None,
    )
}

fn profiles() -> BTreeMap<String, AgentProfile> {
    BTreeMap::from([
        ("claude".to_owned(), claude_code()),
        (
            "opencode".to_owned(),
            AgentProfile::new("OpenCode", &["opencode"]),
        ),
    ])
}

fn ids(items: &[form::ModelItem]) -> Vec<Option<&str>> {
    items.iter().map(|i| i.id.as_deref()).collect()
}

#[test]
fn modelo_padrao_primeiro_catalogo_e_depois_os_apelidos() {
    let claude = claude_code();
    let (items, selected) = model_items(Some(&claude), Some(&catalog()), Some("claude-opus-5-5"));
    assert_eq!(items[0].label, DEFAULT_MODEL_OPTION);
    assert_eq!(items[0].id, None);
    assert_eq!(items[1].label, "Opus 5.5");
    assert!(items.iter().any(|i| i.id.as_deref() == Some("opus")));
    assert_eq!(selected.as_deref(), Some("claude-opus-5-5"));
}

#[test]
fn modelo_que_o_cli_nao_conhece_volta_ao_padrao() {
    let claude = claude_code();
    let (_, selected) = model_items(Some(&claude), None, Some("gpt-5"));
    assert_eq!(selected, None, "o CLI declara lista e gpt-5 não está nela");
}

#[test]
fn modelo_escrito_a_mao_vale_quando_o_cli_nao_declara_lista() {
    let solto = AgentProfile::new("Solto", &["solto"]);
    let (items, selected) = model_items(Some(&solto), None, Some("meu-modelo"));
    assert_eq!(ids(&items), [None, Some("meu-modelo")]);
    assert_eq!(selected.as_deref(), Some("meu-modelo"));
}

#[test]
fn esforco_segue_a_mesma_regra() {
    let claude = claude_code();
    let (levels, selected) = effort_items(Some(&claude), Some("high"));
    assert_eq!(levels, ["low", "medium", "high", "xhigh", "max"]);
    assert_eq!(selected.as_deref(), Some("high"));
    assert_eq!(effort_items(Some(&claude), Some("turbo")).1, None);
    let solto = AgentProfile::new("Solto", &["solto"]);
    assert_eq!(
        effort_items(Some(&solto), Some("turbo")),
        (vec!["turbo".to_owned()], Some("turbo".to_owned()))
    );
}

#[test]
fn a_pasta_dentro_da_bancada_grava_relativa_e_fora_absoluta_com_til() {
    let root = "/Users/voce/deck";
    assert_eq!(
        stored_folder("/Users/voce/deck/api", Some(root), HOME),
        "api"
    );
    assert_eq!(stored_folder("/Users/voce/deck", Some(root), HOME), "");
    assert_eq!(
        stored_folder("/Users/voce/vizinho", Some(root), HOME),
        "~/vizinho",
        "nunca `..`: o mesmo texto seria outra pasta em outro checkout"
    );
    assert_eq!(stored_folder("/tmp/x", None, HOME), "/tmp/x");
    assert_eq!(
        stored_folder("/Users/voce/deckzinho", Some(root), HOME),
        "~/deckzinho"
    );
}

#[test]
fn a_pasta_ao_confirmar_mantem_relativo_e_encurta_absoluto() {
    assert_eq!(normalized_folder("api", HOME), "api");
    assert_eq!(normalized_folder("/Users/voce/x", HOME), "~/x");
    assert_eq!(normalized_folder("~/x", HOME), "~/x");
    assert_eq!(normalized_folder("/opt/x", HOME), "/opt/x");
}

fn fields(name: &str, kind: NodeKind, agent: Option<&str>) -> FormFields {
    FormFields {
        name: name.to_owned(),
        kind,
        agent: agent.map(str::to_owned),
        cwd: String::new(),
        cmd: None,
        maestro: false,
    }
}

#[test]
fn nome_em_branco_vira_o_cli_ou_sh() {
    let base = NodeTemplate::new("", NodeKind::Agent);
    let agent = finish(&base, &fields("  ", NodeKind::Agent, Some("codex")), None);
    assert_eq!(agent.name, "codex");
    let shell = finish(&base, &fields("", NodeKind::Shell, None), None);
    assert_eq!(shell.name, "sh");
}

#[test]
fn shell_nao_leva_cli_papel_regras_nem_mapa() {
    let mut base = NodeTemplate::new("x", NodeKind::Agent);
    base.prompt = Some("papel".into());
    base.rules = Some("regras".into());
    base.by_agent = Some(BTreeMap::from([(
        "claude".to_owned(),
        Overrides {
            model: Some("opus".into()),
            ..Overrides::default()
        },
    )]));
    let mut f = fields("x", NodeKind::Shell, Some("claude"));
    f.cmd = Some("  npm run dev ".into());
    f.maestro = true;
    let out = finish(&base, &f, None);
    assert_eq!(out.kind, NodeKind::Shell);
    assert_eq!(out.agent, None);
    assert_eq!(out.command.as_deref(), Some("npm run dev"));
    assert_eq!(out.prompt, None);
    assert_eq!(out.rules, None);
    assert_eq!(out.by_agent, None);
    assert_eq!(out.maestro, None, "maestro é só de agente");
}

#[test]
fn o_que_estava_na_tela_fica_com_o_cli_dele() {
    let base = NodeTemplate::new("rev", NodeKind::Agent);
    let shown = Shown {
        cli: "claude".into(),
        model: Some("opus".into()),
        prompt: Some("  revisa  ".into()),
        ..Shown::default()
    };
    let mut f = fields("rev", NodeKind::Agent, Some("claude"));
    f.cwd = "/Users/voce/x".into();
    let out = finish(&base, &f, Some(&shown));
    assert_eq!(out.resolved(Some("claude")).model.as_deref(), Some("opus"));
    // O primeiro texto vale para todos (ADR-057).
    assert_eq!(out.prompt.as_deref(), Some("revisa"));
    assert_eq!(out.cwd.as_deref(), Some("/Users/voce/x"));
}

#[test]
fn trocar_de_cli_devolve_o_que_o_outro_tinha() {
    let mut template = NodeTemplate::new("rev", NodeKind::Agent);
    template.agent = Some("claude".into());
    let shown = Shown {
        cli: "claude".into(),
        model: Some("opus".into()),
        prompt: Some("revisa".into()),
        ..Shown::default()
    };
    let suggested = BTreeMap::new();
    let to_open = form::screen(
        ScreenRequest {
            template: &template,
            shown: Some(&shown),
            cli: Some("opencode"),
            picked_config: None,
            suggested_configs: &suggested,
        },
        &profiles(),
        &|_| None,
        HOME,
    );
    assert_eq!(to_open.fields.model, None, "opus não diz nada ao OpenCode");
    assert_eq!(to_open.fields.prompt.as_deref(), Some("revisa"));
    assert!(to_open.models.len() == 1, "o OpenCode não oferece modelo");

    let back = form::screen(
        ScreenRequest {
            template: &to_open.template,
            shown: None,
            cli: Some("claude"),
            picked_config: None,
            suggested_configs: &suggested,
        },
        &profiles(),
        &|_| Some(catalog()),
        HOME,
    );
    assert_eq!(back.fields.model.as_deref(), Some("opus"));
    assert_eq!(back.config_env.as_deref(), Some("CLAUDE_CONFIG_DIR"));
}

#[test]
fn terminal_novo_sugere_a_configuracao_do_workspace() {
    let mut template = NodeTemplate::new("", NodeKind::Agent);
    template.agent = Some("claude".into());
    let suggested = BTreeMap::from([("claude".to_owned(), "/x/.claude-agro".to_owned())]);
    let screen = form::screen(
        ScreenRequest {
            template: &template,
            shown: None,
            cli: Some("claude"),
            picked_config: None,
            suggested_configs: &suggested,
        },
        &profiles(),
        &|_| None,
        HOME,
    );
    assert_eq!(screen.fields.config.as_deref(), Some("/x/.claude-agro"));
    assert!(
        screen
            .config_items
            .iter()
            .any(|i| i.value.as_deref() == Some("/x/.claude-agro")),
        "a sugerida entra na lista mesmo sem existir aqui"
    );

    let picked = form::screen(
        ScreenRequest {
            template: &template,
            shown: None,
            cli: Some("claude"),
            picked_config: Some("~/.claude-z"),
            suggested_configs: &suggested,
        },
        &profiles(),
        &|_| None,
        HOME,
    );
    assert_eq!(
        picked.fields.config.as_deref(),
        Some("/Users/voce/.claude-z"),
        "o `~` do seletor vira o caminho que o nó grava"
    );
}

fn agent_node(id: &str) -> NodeConfig {
    let mut node = NodeConfig::new(NodeKind::Agent, id);
    node.agent = Some("claude".into());
    node
}

#[test]
fn mesmo_processo_so_quando_nada_do_arranque_mudou() {
    let current = agent_node("rev");
    assert!(same_process(&current.clone(), &current));
    let mut model = current.clone();
    model.model = Some("opus".into());
    assert!(!same_process(&model, &current));
    let mut maestro = current.clone();
    maestro.maestro = Some(true);
    assert!(!same_process(&maestro, &current));
    let mut role = current.clone();
    role.prompt = Some("outro papel".into());
    assert!(!same_process(&role, &current));
}

#[test]
fn a_configuracao_lembrada_e_a_do_cli_do_componente() {
    let mut component = NodeTemplate::new("rev", NodeKind::Agent);
    component.agent = Some("claude".into());
    component.by_agent = Some(BTreeMap::from([(
        "claude".to_owned(),
        Overrides {
            config: Some("/x/.claude-agro".into()),
            ..Overrides::default()
        },
    )]));
    assert_eq!(
        form::config_to_remember(&component),
        Some(("claude".to_owned(), Some("/x/.claude-agro".to_owned())))
    );
    let shell = NodeTemplate::new("sh", NodeKind::Shell);
    assert_eq!(form::config_to_remember(&shell), None);
    let node = instantiate(&component, "rev");
    assert_eq!(node.config.as_deref(), Some("/x/.claude-agro"));
}

#[test]
fn o_subtitulo_do_card_e_o_nome_do_cli() {
    let mut component = NodeTemplate::new("rev", NodeKind::Agent);
    component.agent = Some("claude".into());
    assert_eq!(form::subtitle(&component, &profiles()), "Claude Code");
    component.agent = Some("sumido".into());
    assert_eq!(form::subtitle(&component, &profiles()), "sumido");
    let shell = NodeTemplate::new("sh", NodeKind::Shell);
    assert_eq!(form::subtitle(&shell, &profiles()), "Shell");
}
