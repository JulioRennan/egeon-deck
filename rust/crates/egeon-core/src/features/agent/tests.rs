//! Testes portados de `AgentProfileTests`, `AgentRulesTests`, `ModelCatalogTests`,
//! `ClaudeSkillTests`, `ClaudeTrustTests`, `SlashCommandTests`, `EffortDialTests`
//! e `ContextGaugeTests`.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use serde_json::{Value, json};

use super::claude::command_registry::{CommandRegistry, Entry};
use super::claude::profile::claude_code;
use super::claude::slash_catalog::{self, Frontmatter};
use super::claude::{hooks, model_registry, skill, trust, trust_seeder};
use super::*;
use crate::features::terminal::shell::ShellSyntax;

fn fresh_dir(name: &str) -> tempfile::TempDir {
    tempfile::Builder::new()
        .prefix(name)
        .tempdir()
        .expect("pasta temporária")
}

fn write(path: &Path, text: &str) {
    fs::create_dir_all(path.parent().expect("pai")).expect("cria pasta");
    fs::write(path, text).expect("grava");
}

fn strings(list: &[&str]) -> Vec<String> {
    list.iter().map(|s| (*s).to_owned()).collect()
}

// ---- AgentProfile ----------------------------------------------------------

#[test]
fn perfil_de_fabrica_do_claude_monta_a_linha_de_comando() {
    let profile = claude_code();
    assert_eq!(
        AgentProfile::conversation_arguments(&profile.resume, "ABC"),
        Some(strings(&["--resume", "ABC"]))
    );
    assert_eq!(
        AgentProfile::conversation_arguments(&profile.new_session, "ABC"),
        Some(strings(&["--session-id", "ABC"]))
    );
    assert_eq!(
        profile.report_arguments("/tmp/h.json"),
        Some(strings(&["--settings", "/tmp/h.json"]))
    );
    assert_eq!(
        profile.system_prompt_arguments("seja revisor"),
        Some(strings(&["--append-system-prompt", "seja revisor"]))
    );
    // Sabe retomar E criar com id nosso — é o que faz a conversa sobreviver ao
    // rebuild.
    assert!(profile.keeps_conversation());
    assert!(profile.offers_models());
    assert_eq!(
        profile.model_arguments(Some("opus")),
        Some(strings(&["--model", "opus"]))
    );
    assert_eq!(
        profile.models,
        Some(strings(&["fable", "opus", "sonnet", "haiku", "opusplan"]))
    );
}

#[test]
fn modelo_padrao_e_nao_passar_flag() {
    let profile = claude_code();
    assert_eq!(profile.model_arguments(None), None);
    assert_eq!(profile.model_arguments(Some("")), None);
}

#[test]
fn perfil_sem_declaracoes_devolve_nada() {
    let bare: AgentProfile =
        serde_json::from_str(r#"{"displayName":"X","command":["x"]}"#).expect("lê");
    assert_eq!(
        AgentProfile::conversation_arguments(&bare.resume, "A"),
        None
    );
    assert_eq!(bare.report_arguments("/f"), None);
    assert_eq!(bare.system_prompt_arguments("p"), None);
    assert_eq!(bare.model_arguments(Some("opus")), None);
    assert!(!bare.offers_models());
    assert_eq!(bare.effort_arguments(Some("high")), None);
    assert!(!bare.offers_efforts());
    assert!(!bare.keeps_conversation());
}

#[test]
fn esforco_do_claude() {
    let profile = claude_code();
    assert!(profile.offers_efforts());
    assert_eq!(
        profile.effort_arguments(Some("xhigh")),
        Some(strings(&["--effort", "xhigh"]))
    );
    assert_eq!(
        profile.efforts,
        Some(strings(&["low", "medium", "high", "xhigh", "max"]))
    );
    assert_eq!(
        profile.effort_arguments(None),
        None,
        "padrão é não passar flag"
    );
    assert_eq!(profile.effort_arguments(Some("")), None);
}

/// O seletor do cabeçalho troca UM dos dois; o outro fica como estava.
#[test]
fn escolha_de_esforco_mexe_so_no_esforco() {
    let (mut model, mut effort, mut ultracode) = (Some("opus".to_owned()), None, None);
    ModelChoice::Effort(Some("max".into())).apply(&mut model, &mut effort, &mut ultracode);
    assert_eq!(effort.as_deref(), Some("max"));
    assert_eq!(
        model.as_deref(),
        Some("opus"),
        "trocar esforço não mexe no modelo"
    );
    ModelChoice::Effort(None).apply(&mut model, &mut effort, &mut ultracode);
    assert_eq!(effort, None);
    ModelChoice::Effort(Some("max".into())).apply(&mut model, &mut effort, &mut ultracode);
    ModelChoice::Model(Some("sonnet".into())).apply(&mut model, &mut effort, &mut ultracode);
    assert_eq!(effort.as_deref(), Some("max"));
    ModelChoice::Ultracode(true).apply(&mut model, &mut effort, &mut ultracode);
    assert_eq!(ultracode, Some(true));
    ModelChoice::Ultracode(false).apply(&mut model, &mut effort, &mut ultracode);
    assert_eq!(ultracode, None);
}

#[test]
fn marcador_mais_recente_e_o_de_baixo() {
    let marker = MarkerConfig::default();
    assert_eq!(marker.latest("fim [[ED:ok]]"), Some(Marker::Ok));
    assert_eq!(
        marker.latest("cita [[ED:ok]] e depois [[ED:ask]]"),
        Some(Marker::Ask)
    );
    assert_eq!(
        marker.latest("[[ED:wait]] [[ED:ok]] [[ED:wait]]"),
        Some(Marker::Wait)
    );
    assert_eq!(marker.latest("sem nada"), None);
}

#[test]
fn instrucao_antiga_sem_wait_ganha_a_linha() {
    let marker = MarkerConfig {
        instruction: "{done} e {ask}".to_owned(),
        ..MarkerConfig::default()
    };
    let text = marker.resolved_instruction();
    assert!(text.starts_with("[[ED:ok]] e [[ED:ask]]\n[[ED:wait]] — parei"));
}

/// O texto do protocolo é o que o Swift gera, caractere a caractere.
#[test]
fn instrucao_padrao_e_a_do_swift() {
    let expected = "Protocolo Egeon: termine TODA resposta com um marcador sozinho na última linha, sem nada depois dele.\n\
[[ED:ok]] — terminei e não dependo de você.\n\
[[ED:ask]] — parei e dependo de uma resposta sua: dúvida, escolha, permissão ou informação que falta.\n\
[[ED:wait]] — parei, mas deixei trabalho rodando em segundo plano (comando em background, subagente, vizinho acionado) e volto sozinho quando ele acabar.\n\
Se você fez uma pergunta ao usuário, o marcador é [[ED:ask]]. Um marcador só, sempre por último.";
    assert_eq!(MarkerConfig::default().resolved_instruction(), expected);
}

#[test]
fn chaves_faltando_herdam_o_padrao_e_som_nulo_desliga() {
    let profile: AgentProfile = serde_json::from_str(
        r#"{"displayName":"X","command":["x"],"idle":{"ms":900},"inject":{},"attention":{"volume":0.5}}"#,
    )
    .expect("lê");
    let idle = profile.idle.expect("idle");
    assert_eq!(
        (idle.ms, idle.warmup_ms, idle.strategy.as_str()),
        (900, 4000, "silence")
    );
    assert_eq!(profile.inject.expect("inject").submit_delay_ms, 150);
    let attention = profile.attention.expect("attention");
    assert_eq!(attention.volume, 0.5);
    assert_eq!(
        attention.sound.as_deref(),
        Some("Tink"),
        "ausente herda o padrão"
    );
    assert!(attention.marker.is_some());

    let silent: AttentionConfig = serde_json::from_str(r#"{"sound":null}"#).expect("lê");
    assert_eq!(silent.sound, None, "nulo explícito desliga o som");
}

#[test]
fn ambiente_resolve_til_e_home() {
    let mut profile = claude_code();
    profile.env = Some(BTreeMap::from([
        ("A".to_owned(), "~/.claude-trabalho".to_owned()),
        ("B".to_owned(), "$HOME/x".to_owned()),
        ("C".to_owned(), "~".to_owned()),
        ("D".to_owned(), "/abs".to_owned()),
    ]));
    let env = profile.resolved_environment(Path::new("/Users/eu"));
    assert_eq!(env["A"], "/Users/eu/.claude-trabalho");
    assert_eq!(env["B"], "/Users/eu/x");
    assert_eq!(env["C"], "/Users/eu");
    assert_eq!(env["D"], "/abs");
}

#[test]
fn configuracoes_descobertas_so_diretorios() {
    let home = fresh_dir("home-");
    fs::create_dir(home.path().join(".claude")).expect("pasta");
    fs::create_dir(home.path().join(".claude-agro")).expect("pasta");
    fs::write(home.path().join(".claude.json"), "{}").expect("arquivo");
    fs::create_dir(home.path().join(".outra")).expect("pasta");
    let found = claude_code().discovered_configs(home.path());
    assert_eq!(
        found,
        vec![
            home.path().join(".claude"),
            home.path().join(".claude-agro")
        ]
    );
    assert_eq!(
        claude_code().default_config_path(home.path()),
        Some(home.path().join(".claude"))
    );
}

#[test]
fn modelo_padrao_vem_do_settings_da_pasta() {
    let home = fresh_dir("home-");
    write(
        &home.path().join(".claude/settings.json"),
        r#"{"model":"opus"}"#,
    );
    write(
        &home.path().join(".claude-x/settings.json"),
        r#"{"theme":"dark"}"#,
    );
    let profile = claude_code();
    assert_eq!(
        profile.default_model_name(None, home.path()).as_deref(),
        Some("opus")
    );
    let other = home.path().join(".claude-x");
    assert_eq!(
        profile.default_model_name(other.to_str(), home.path()),
        None,
        "settings sem modelo"
    );
}

#[test]
fn so_e_o_binario_do_perfil() {
    let profile = claude_code();
    assert!(profile.runs_own_binary("claude"));
    assert!(profile.runs_own_binary("claude --resume x"));
    assert!(!profile.runs_own_binary("claudex"));
    assert!(!profile.runs_own_binary("vim"));
}

#[test]
fn faixa_do_cabecalho_so_com_o_que_escolher() {
    let codex: AgentProfile = serde_json::from_str(
        r#"{"displayName":"Codex","command":["codex"],"model":["--model","{model}"],"models":[]}"#,
    )
    .expect("lê");
    assert!(!codex.offers_model_choice(None, None));
    assert!(
        codex.offers_model_choice(None, Some("gpt-5")),
        "modelo à mão aparece"
    );
    assert!(claude_code().offers_model_choice(None, None));
}

/// Ultracode ocupa a flag do esforço; o nível segue pela variável.
#[test]
fn ultracode_leva_o_nivel_para_o_ambiente() {
    let profile = claude_code();
    let plain = profile.effort_launch(Some("high"), false);
    assert_eq!(plain.arguments, strings(&["--effort", "high"]));
    assert!(plain.environment.is_empty());

    let ultra = profile.effort_launch(Some("high"), true);
    assert_eq!(ultra.arguments, strings(&["--effort", "ultracode"]));
    assert_eq!(
        ultra.environment,
        BTreeMap::from([("CLAUDE_CODE_EFFORT_LEVEL".to_owned(), "high".to_owned())])
    );
    assert!(
        profile.effort_launch(None, true).environment.is_empty(),
        "auto: nenhum nível forçado"
    );
}

// ---- agents.json -----------------------------------------------------------

#[test]
fn sem_arquivo_grava_os_padroes() {
    let home = fresh_dir("agents-");
    let profiles = store::load(home.path());
    assert_eq!(
        profiles.keys().collect::<Vec<_>>(),
        ["claude", "codex", "gemini", "opencode"]
    );
    assert!(store::config_path(home.path()).exists());
    assert_eq!(
        store::load(home.path()),
        profiles,
        "o que foi gravado abre igual"
    );
}

/// Arquivo escrito por versão anterior ganha os campos novos — só quando o
/// comando é o que o padrão conhece.
#[test]
fn migracao_preenche_campos_novos_com_a_trava_de_comando() {
    let home = fresh_dir("agents-");
    write(
        &store::config_path(home.path()),
        r#"{
          "claude": {"displayName":"Claude Code","command":["claude"],"models":["opus","sonnet","haiku"],
                     "resume":["--resume","{sessionId}"]},
          "outro": {"displayName":"Meu","command":["claude-fork"]}
        }"#,
    );
    let profiles = store::load(home.path());
    let claude = &profiles["claude"];
    assert_eq!(
        claude.new_session,
        Some(strings(&["--session-id", "{sessionId}"]))
    );
    assert_eq!(claude.system_prompt.as_ref().map(Vec::len), Some(2));
    assert_eq!(claude.clear.as_deref(), Some("/clear"));
    assert_eq!(claude.config_env.as_deref(), Some("CLAUDE_CONFIG_DIR"));
    assert!(claude.attention.is_some());
    // A primeira lista de fábrica é trocada pela atual.
    assert_eq!(
        claude.models,
        Some(strings(&["fable", "opus", "sonnet", "haiku", "opusplan"]))
    );
    // Comando trocado pode ser outro binário: não ganha flag nenhuma.
    let outro = &profiles["outro"];
    assert_eq!(outro.new_session, None);
    assert_eq!(outro.system_prompt, None);
    assert_eq!(outro.clear, None);
    // Mas `attention` vale para qualquer CLI.
    assert!(outro.attention.is_some());
    // E foi gravado.
    let again = store::load(home.path());
    assert_eq!(again, profiles);
}

#[test]
fn lista_editada_a_mao_nao_e_tocada() {
    let home = fresh_dir("agents-");
    write(
        &store::config_path(home.path()),
        r#"{"claude":{"displayName":"C","command":["claude"],"models":["so-o-meu"]}}"#,
    );
    let profiles = store::load(home.path());
    assert_eq!(profiles["claude"].models, Some(strings(&["so-o-meu"])));
}

// ---- AgentRules + ordem do system prompt -----------------------------------

#[test]
fn sem_regras_nada() {
    assert_eq!(agent_rules_block(None, None), None);
    assert_eq!(agent_rules_block(Some(""), Some("   \n  ")), None);
}

/// Com um bloco só, dizer de onde ele veio não informa nada.
#[test]
fn um_bloco_so_nao_carrega_origem() {
    let only_node = agent_rules_block(None, Some("peça antes de commitar")).expect("bloco");
    assert_eq!(
        only_node,
        format!("{}\n\npeça antes de commitar", rules::HEADER)
    );
    assert!(!only_node.contains("Da bancada"));
    let only_bench = agent_rules_block(Some("escreva em português"), Some("")).expect("bloco");
    assert_eq!(
        only_bench,
        format!("{}\n\nescreva em português", rules::HEADER)
    );
}

#[test]
fn dois_blocos_nomeados_e_em_ordem() {
    let block = agent_rules_block(Some("escreva em português"), Some("peça antes de commitar"))
        .expect("bloco");
    let bench = block.find("Da bancada:").expect("bancada");
    let node = block.find("Deste terminal:").expect("terminal");
    assert!(bench < node, "a da bancada vem primeiro");
    assert!(block.contains("escreva em português") && block.contains("peça antes de commitar"));
}

#[test]
fn texto_do_usuario_nao_e_reescrito() {
    let written = "1. rode swift test\n2. não empurre nada sem pedir";
    let block = agent_rules_block(None, Some(&format!("  {written}  "))).expect("bloco");
    assert!(block.ends_with(written), "só o espaço em volta sai");
}

#[test]
fn cabecalho_diz_a_precedencia() {
    assert!(rules::HEADER.contains("valem sobre o papel"));
}

#[test]
fn regras_vem_depois_do_papel() {
    let text = claude_code()
        .system_prompt_text(
            Some("você é o revisor"),
            Some("use `egeon`"),
            Some("peça antes de commitar"),
        )
        .expect("texto");
    let at = |needle: &str| text.find(needle).expect(needle);
    assert!(at("[[ED:ok]]") < at("use `egeon`"));
    assert!(at("use `egeon`") < at("você é o revisor"));
    assert!(
        at("você é o revisor") < at("peça antes de commitar"),
        "regra depois do papel"
    );
    assert!(
        text.contains("AskUserQuestion"),
        "Claude fala por gancho: pergunta por ferramenta"
    );
}

#[test]
fn so_regras_ainda_chegam_ao_agente() {
    let text = claude_code()
        .system_prompt_text(None, None, Some("peça antes de commitar"))
        .expect("texto");
    assert!(text.contains("peça antes de commitar"));
}

#[test]
fn sem_marcador_nem_nada_o_prompt_e_nulo() {
    let mut profile = AgentProfile::new("X", &["x"]);
    profile.attention = Some(AttentionConfig {
        marker: None,
        ..AttentionConfig::default()
    });
    assert_eq!(profile.system_prompt_text(None, None, None), None);
}

// ---- ModelCatalog ----------------------------------------------------------

const OPUS55: &str = r#"{id:"claude-opus-5-5",family:"opus",display_name:"Opus 5.5",knowledge_cutoff:"June 2026",provider_ids:{first_party:"claude-opus-5-5"},capabilities:["effort","max_effort","xhigh_effort","adaptive_thinking"],default_effort:"medium",advisor_rank:4},"#;
const OPUS46: &str = r#"{id:"claude-opus-4-6",family:"opus",display_name:"Opus 4.6",capabilities:["effort","max_effort","adaptive_thinking"],advisor_rank:4},"#;
const HAIKU: &str = r#"{id:"claude-haiku-4-5",family:"haiku",display_name:"Haiku 4.5",capabilities:["context_management"],advisor_rank:1},"#;
const FABLE: &str = r#"{id:"claude-fable-5-1",family:"fable",display_name:"Fable 5.1",capabilities:["effort","max_effort","xhigh_effort"],default_effort:"high"},"#;
/// O mesmo começo aparece em outras tabelas do CLI, sem `family`.
const DECOY: &str = r#"{id:"claude-opus-5-5",pricing:"tier_4_20"},"#;

fn catalog() -> ModelCatalog {
    let blob = format!("lixo{DECOY}{OPUS55}{OPUS46}{HAIKU}{FABLE}{OPUS55}");
    ModelCatalog::new(model_registry::parse_binary(blob.as_bytes()), None)
}

#[test]
fn le_a_tabela_e_pula_iscas_e_repeticoes() {
    let ids: Vec<String> = catalog().models.iter().map(|m| m.id.clone()).collect();
    assert_eq!(
        ids,
        [
            "claude-opus-5-5",
            "claude-opus-4-6",
            "claude-haiku-4-5",
            "claude-fable-5-1"
        ]
    );
}

/// `xhigh` e `max` são capacidades à parte; sem `effort`, nenhum nível.
#[test]
fn niveis_de_esforco_seguem_as_capacidades() {
    let catalog = catalog();
    let by_id = |id: &str| catalog.models.iter().find(|m| m.id == id).expect(id);
    assert_eq!(
        by_id("claude-opus-5-5").efforts,
        ["low", "medium", "high", "xhigh", "max"]
    );
    assert_eq!(
        by_id("claude-opus-5-5").default_effort.as_deref(),
        Some("medium")
    );
    assert_eq!(
        by_id("claude-opus-4-6").efforts,
        ["low", "medium", "high", "max"]
    );
    assert!(by_id("claude-haiku-4-5").efforts.is_empty());
    assert_eq!(by_id("claude-haiku-4-5").default_effort, None);
    assert_eq!(by_id("claude-opus-5-5").label, "Opus 5.5");
}

#[test]
fn destaque_e_o_mais_novo_de_cada_familia_na_ordem_do_menu() {
    let catalog = catalog();
    let labels =
        |list: Vec<&CatalogModel>| list.iter().map(|m| m.label.clone()).collect::<Vec<_>>();
    assert_eq!(
        labels(catalog.featured()),
        ["Fable 5.1", "Opus 5.5", "Haiku 4.5"]
    );
    assert_eq!(labels(catalog.older()), ["Opus 4.6"]);
}

/// Id exato, id com snapshot ou `[1m]`, e apelido de família.
#[test]
fn resolve_o_que_o_no_pediu_ou_o_transcript_gravou() {
    let catalog = catalog();
    let label = |name: Option<&str>| catalog.label_for(name).map(str::to_owned);
    assert_eq!(label(Some("claude-opus-4-6")).as_deref(), Some("Opus 4.6"));
    assert_eq!(
        label(Some("claude-haiku-4-5-20251001")).as_deref(),
        Some("Haiku 4.5")
    );
    assert_eq!(
        label(Some("claude-opus-5-5[1m]")).as_deref(),
        Some("Opus 5.5")
    );
    assert_eq!(label(Some("opus")).as_deref(), Some("Opus 5.5"));
    assert_eq!(label(Some("opusplan")).as_deref(), Some("Opus 5.5"));
    assert_eq!(label(Some("gpt-5")), None);
    assert_eq!(label(None), None);
}

#[test]
fn binario_sem_tabela_nao_da_nada() {
    assert!(model_registry::parse_binary(b"sem tabela").is_empty());
}

#[test]
fn registro_le_a_janela_e_nao_o_maximo() {
    let wide = r#"{id:"claude-opus-5-5",family:"opus",display_name:"Opus 5.5",context:{window:1e6,native_1m:!0},capabilities:["effort"]}"#;
    let narrow = r#"{id:"claude-sonnet-4-6",family:"sonnet",display_name:"Sonnet 4.6",context:{window:200000,maximum_window:1e6},capabilities:["effort"]}"#;
    let late = r#"{id:"claude-x",family:"x",display_name:"X",context:{native_1m:!0,window:300000},capabilities:[]}"#;
    let none = r#"{id:"claude-3-5-haiku",family:"haiku",display_name:"Haiku",capabilities:[]}"#;
    let window = |entry: &str| model_registry::parse_entry(entry).and_then(|m| m.context_window);
    assert_eq!(window(wide), Some(1_000_000));
    assert_eq!(window(narrow), Some(200_000));
    assert_eq!(window(late), Some(300_000));
    assert_eq!(window(none), None);
}

/// Cache gravado antes do campo existir precisa pedir releitura.
#[test]
fn catalogo_sem_schema_e_antigo() {
    let old: ModelCatalog = serde_json::from_str(r#"{"models":[]}"#).expect("lê");
    assert_eq!(old.schema, None);
    assert_eq!(
        ModelCatalog::new(vec![], None).schema,
        Some(ModelCatalog::CURRENT_SCHEMA)
    );
}

#[test]
fn precos_do_catalogo_do_claude_code() {
    let blob = r#"tier_4_20_cache_read_0_20:{input:4,output:20,cache_write_5m:5,cache_write_1h:8,cache_read:0.2,web_search:0.01},haiku_55:{input:0.1,output:0.5,cache_write_5m:0.125,cache_write_1h:0.2,cache_read:0.01,web_search:0.01,long_prompt:{above_prompt_tokens:1e5,input:0.5,output:2.5,cache_write_5m:0.625,cache_write_1h:1,cache_read:0.05}}},models:[{id:"claude-opus-5-5""#;
    let tiers = model_registry::tiers(blob);
    assert_eq!(
        tiers.keys().cloned().collect::<Vec<_>>(),
        ["haiku_55", "tier_4_20_cache_read_0_20"]
    );
    let mut opus = CatalogModel::new("claude-opus-5-5", "opus", "Opus 5.5");
    opus.pricing = Some("tier_4_20_cache_read_0_20".into());
    let mut haiku = CatalogModel::new("claude-haiku-5-5", "haiku", "Haiku 5.5");
    haiku.pricing = Some("haiku_55".into());
    let prices = model_registry::prices(&tiers, &[opus, haiku]);
    let mut expected = crate::features::usage::ModelPrice::new("Opus 5.5", 4.0, 20.0, 0.2);
    expected.cache_write5m = Some(5.0);
    expected.cache_write1h = Some(8.0);
    assert_eq!(prices["claude-opus-5-5"], expected);
    let long = &prices["claude-haiku-5-5#long"];
    assert_eq!(long.input, 0.5);
    assert_eq!(long.long_above, Some(100_000));
    assert_eq!(long.name, "Haiku 5.5 (prompt > 100K)");

    // O pedaço da entrada de modelo que aponta a faixa.
    let entry = r#"{id:"claude-sonnet-5-5",family:"sonnet",display_name:"Sonnet 5.5",pricing:"tier_4_20_cache_read_0_20",capabilities:["effort"],default_effort:"medium"}"#;
    assert_eq!(
        model_registry::parse_entry(entry)
            .and_then(|m| m.pricing)
            .as_deref(),
        Some("tier_4_20_cache_read_0_20")
    );
}

#[test]
fn catalogo_em_cache_vai_e_volta_do_disco() {
    use super::claude::catalog::{Cache, Stamp};
    let dir = fresh_dir("cat-");
    let binary = dir.path().join("claude");
    fs::write(&binary, format!("{OPUS55}{HAIKU}")).expect("binário");
    let stamp = super::claude::catalog::stamp_of(&binary).expect("stamp");
    let cache = super::claude::catalog::read_binary(&binary, stamp).expect("lê");
    assert_eq!(cache.catalog.models.len(), 2);
    assert!(cache.is_fresh(&binary, stamp));
    let file = dir.path().join("claude-models.json");
    super::claude::catalog::save_cache(&file, &cache);
    let back: Cache = super::claude::catalog::load_cache(&file).expect("relê");
    assert_eq!(back.catalog, cache.catalog);
    assert_eq!(back.commands, cache.commands);
    assert!(
        back.is_fresh(&binary, stamp),
        "a data relida ainda casa com o binário"
    );
    let moved = Stamp {
        size: stamp.size + 1,
        ..stamp
    };
    assert!(!back.is_fresh(&binary, moved), "binário mudou: relê");
}

// ---- Leitura do binário em blocos (decisão 40) ----------------------------

const MODELO_COM_PRECO: &str = r#"{id:"claude-sonnet-5-5",family:"sonnet",display_name:"Sonnet 5.5",pricing:"tier_4_20_cache_read_0_20",capabilities:["effort"],default_effort:"medium"},"#;
const FAIXAS: &str = r#"pricing_tiers:{tier_4_20_cache_read_0_20:{input:4,output:20,cache_write_5m:5,cache_write_1h:8,cache_read:0.2}},"#;
const COMANDOS: &str = r#"x={type:"local",name:"compact",description:"Free up context",load:()=>1};Wi({name:"debug",menuDescription:"Turn on debug",description:"x",disableModelInvocation:!0,async getPromptForCommand(){}});"#;

#[test]
fn fonte_em_blocos_acha_o_padrao_em_qualquer_fronteira() {
    use super::claude::binary_source::{Bytes, FileBytes};
    let needle = b"NEEDLE!!";
    let dir = fresh_dir("blocos-");
    let file = dir.path().join("bin");
    for block in [8, 9, 16, 31, 64] {
        for at in 0..=(300 - needle.len()) {
            let mut data = vec![b'a'; 300];
            data[at..at + needle.len()].copy_from_slice(needle);
            fs::write(&file, &data).expect("binário");
            let mut source = FileBytes::open_with_block(&file, block).expect("abre");
            assert_eq!(source.size(), 300);
            assert_eq!(source.find(needle, 0), Some(at), "bloco {block}, em {at}");
            assert_eq!(source.find(needle, at), Some(at));
            assert_eq!(source.find(needle, at + 1), None);
            assert!(!source.failed());
        }
    }
}

#[test]
fn fonte_em_blocos_menor_que_o_padrao_ainda_avanca_e_agulha_vazia_nao_acha() {
    use super::claude::binary_source::{Bytes, FileBytes};
    let needle = b"NEEDLE!!";
    let mut data = vec![b'a'; 40];
    data[13..13 + needle.len()].copy_from_slice(needle);
    let dir = fresh_dir("blocos-");
    let file = dir.path().join("bin");
    fs::write(&file, &data).expect("binário");
    let mut source = FileBytes::open_with_block(&file, 1).expect("abre");
    // O buffer veio de um trecho curto, menor que o padrão.
    assert_eq!(source.slice(0, 1), b"a");
    assert_eq!(source.find(needle, 0), Some(13));
    assert_eq!(source.find(b"", 0), None);
    let mut memory: &[u8] = &data;
    assert_eq!(memory.find(b"", 0), None);
}

#[test]
fn leitura_que_falha_no_meio_acende_failed_e_nao_vira_catalogo() {
    use super::claude::binary_source::{Bytes, FileBytes};
    let dir = fresh_dir("blocos-");
    let file = dir.path().join("claude");
    fs::write(&file, format!("{OPUS55}{HAIKU}{}", "x".repeat(500))).expect("binário");
    let mut source = FileBytes::open_with_block(&file, 64).expect("abre");
    assert!(!source.failed());
    // O binário foi trocado por um menor durante a varredura.
    fs::write(&file, "curto").expect("trunca");
    assert_eq!(source.find(b"{id:\"claude-", 0), None);
    assert!(source.failed());
    assert!(source.slice(0, 10).is_empty());
}

#[test]
fn fonte_em_blocos_corta_trechos_como_a_memoria() {
    use super::claude::binary_source::{Bytes, FileBytes};
    let data: Vec<u8> = (0..=255u8).cycle().take(700).collect();
    let dir = fresh_dir("blocos-");
    let file = dir.path().join("bin");
    fs::write(&file, &data).expect("binário");
    let mut source = FileBytes::open_with_block(&file, 50).expect("abre");
    let mut memory: &[u8] = &data;
    for (start, end) in [
        (0, 10),
        (45, 60),
        (49, 51),
        (100, 400),
        (690, 900),
        (800, 900),
    ] {
        assert_eq!(source.slice(start, end), memory.slice(start, end));
    }
    // Voltar para trás também vale: o comando lê o que vem antes do `type:`.
    assert_eq!(source.slice(3, 9), memory.slice(3, 9));
    assert!(!source.failed());
}

#[test]
fn varredura_em_blocos_da_o_mesmo_catalogo_que_na_memoria() {
    use super::claude::binary_source::FileBytes;
    let dir = fresh_dir("blocos-");
    let file = dir.path().join("bin");
    let mut compared = 0;
    for block in [97, 128, 1000] {
        for pad in (0..60).step_by(7) {
            let filler = "x".repeat(pad);
            let blob = format!(
                "{filler}{OPUS55}{filler}{MODELO_COM_PRECO}{filler}{HAIKU}{filler}{FAIXAS}{filler}{COMANDOS}{filler}"
            );
            fs::write(&file, &blob).expect("binário");
            let mut source = FileBytes::open_with_block(&file, block).expect("abre");
            let models = model_registry::parse_source(&mut source);
            let prices = model_registry::prices_from_source(&mut source, &models);
            let commands = CommandRegistry::parse_source(&mut source);
            assert!(!source.failed());

            let in_memory = model_registry::parse_binary(blob.as_bytes());
            assert_eq!(models.len(), 3, "bloco {block}, margem {pad}");
            assert_eq!(models, in_memory, "bloco {block}, margem {pad}");
            assert_eq!(
                prices,
                model_registry::prices_from_binary(blob.as_bytes(), &in_memory)
            );
            assert_eq!(prices.len(), 1);
            assert_eq!(commands, CommandRegistry::parse_binary(blob.as_bytes()));
            assert_eq!(commands.builtins.len(), 1);
            assert_eq!(commands.skills.len(), 1);
            compared += 1;
        }
    }
    assert!(compared > 20);
}

#[test]
fn binario_grande_le_com_memoria_constante_e_acha_o_que_cruza_o_bloco() {
    use super::claude::binary_source::{BLOCK, FileBytes};
    use std::io::{Seek, SeekFrom, Write};
    let dir = fresh_dir("grande-");
    let binary = dir.path().join("claude");
    let mut out = fs::File::create(&binary).expect("cria");
    // Esparso: 24 blocos de zeros custam o tempo da leitura, não o disco.
    out.set_len((24 * BLOCK) as u64).expect("tamanho");
    // Cada trecho cruza uma fronteira de bloco ou cai colado nela.
    let places = [
        (BLOCK - 20, OPUS55),
        (3 * BLOCK - 1, HAIKU),
        (7 * BLOCK - 40, MODELO_COM_PRECO),
        (11 * BLOCK - 5, FAIXAS),
        (15 * BLOCK - 30, COMANDOS),
    ];
    for (at, text) in places {
        out.seek(SeekFrom::Start(at as u64)).expect("posição");
        out.write_all(text.as_bytes()).expect("trecho");
    }
    drop(out);

    let stamp = super::claude::catalog::stamp_of(&binary).expect("stamp");
    let cache = super::claude::catalog::read_binary(&binary, stamp).expect("lê");
    let ids: Vec<_> = cache.catalog.models.iter().map(|m| m.id.as_str()).collect();
    assert_eq!(
        ids,
        ["claude-opus-5-5", "claude-haiku-4-5", "claude-sonnet-5-5"]
    );
    assert_eq!(cache.catalog.prices.as_ref().map(|p| p.len()), Some(1));
    let commands = cache.commands.expect("comandos");
    assert_eq!(commands.builtins.len(), 1);
    assert_eq!(commands.skills.len(), 1);

    // O buffer nunca passa de um bloco, por maior que seja o binário.
    let mut source = FileBytes::open(&binary).expect("abre");
    let models = model_registry::parse_source(&mut source);
    model_registry::prices_from_source(&mut source, &models);
    CommandRegistry::parse_source(&mut source);
    assert!(
        source.capacity() <= BLOCK,
        "buffer de {}",
        source.capacity()
    );
}

// ---- ContextGauge ----------------------------------------------------------

fn model_with(window: Option<i64>) -> CatalogModel {
    let mut m = CatalogModel::new("claude-x", "x", "X");
    m.context_window = window;
    m
}

#[test]
fn medidor_mostra_a_fatia_arredondada_para_cima() {
    let gauge =
        ContextGauge::new(170_500, None, Some(&model_with(Some(1_000_000)))).expect("gauge");
    assert_eq!(gauge.used_percent(), 18);
    assert_eq!(gauge.text(), "18%");
    assert_eq!(gauge.detail(), "170K de 1M em uso");
    let one = ContextGauge::new(1, None, Some(&model_with(Some(1_000_000)))).expect("gauge");
    assert_eq!(one.text(), "1%");
}

#[test]
fn matiz_vai_do_verde_ao_vermelho() {
    let model = model_with(Some(100_000));
    let hue = |tokens| {
        ContextGauge::new(tokens, None, Some(&model))
            .expect("gauge")
            .hue()
    };
    assert_eq!(hue(0), 120.0);
    assert_eq!(hue(50_000), 60.0);
    assert_eq!(hue(100_000), 0.0);
    assert!(hue(80_000) > hue(90_000));
}

/// `[1m]` não aparece no transcript: só o pedido diz que a janela é a grande.
#[test]
fn janela_grande_pedida_vence_o_catalogo() {
    let gauge = ContextGauge::new(100_000, Some("opus[1m]"), Some(&model_with(Some(200_000))));
    assert_eq!(gauge.map(|g| g.window), Some(1_000_000));
}

#[test]
fn uso_acima_da_janela_do_catalogo_e_a_grande() {
    let gauge = ContextGauge::new(300_000, None, Some(&model_with(Some(200_000))));
    assert_eq!(gauge.map(|g| g.window), Some(1_000_000));
}

#[test]
fn janela_cheia_para_em_cem() {
    let gauge =
        ContextGauge::new(1_200_000, None, Some(&model_with(Some(1_000_000)))).expect("gauge");
    assert_eq!(gauge.used_percent(), 100);
    assert_eq!(gauge.hue(), 0.0);
}

#[test]
fn janela_desconhecida_nao_tem_medidor() {
    assert_eq!(ContextGauge::new(10, None, Some(&model_with(None))), None);
    assert_eq!(ContextGauge::new(10, None, None), None);
}

#[test]
fn numeros_curtos() {
    assert_eq!(ContextGauge::short(900), "900");
    assert_eq!(ContextGauge::short(200_000), "200K");
    assert_eq!(ContextGauge::short(1_000_000), "1M");
    assert_eq!(ContextGauge::short(1_500_000), "1.5M");
}

// ---- EffortDial ------------------------------------------------------------

fn levels() -> Vec<String> {
    strings(&["low", "medium", "high", "xhigh", "max"])
}

#[test]
fn dial_comeca_no_nivel_atual() {
    assert_eq!(
        EffortDialState::new(&levels(), Some("high"), None).value(),
        Some("high")
    );
    assert_eq!(
        EffortDialState::new(&levels(), None, None).value(),
        None,
        "None é o padrão"
    );
}

/// Nível escrito à mão no JSON e fora da lista continua valendo.
#[test]
fn dial_guarda_nivel_desconhecido() {
    assert_eq!(
        EffortDialState::new(&levels(), Some("ultra"), None).value(),
        Some("ultra")
    );
}

/// Em auto a barra mostra, apagada, o nível do modelo — não fica vazia.
#[test]
fn auto_mostra_o_nivel_do_modelo() {
    let auto = EffortDialState::new(&levels(), None, Some("high"));
    assert!(auto.is_auto());
    assert_eq!(auto.slider_index(), 2);
    assert_eq!(auto.label(), "high");

    let fixed = EffortDialState::new(&levels(), Some("high"), Some("high"));
    assert!(!fixed.is_auto());
    assert_eq!(fixed.slider_index(), 2);
}

#[test]
fn desligar_o_auto_mantem_o_nivel_que_o_modelo_usava() {
    let mut dial = EffortDialState::new(&levels(), None, Some("high"));
    dial.toggle_auto();
    assert_eq!(dial.value(), Some("high"));
    assert_eq!(dial.label(), "high…", "só vale quando assenta");
    dial.toggle_auto();
    assert_eq!(dial.value(), None);
    assert_eq!(
        dial.label(),
        "high",
        "voltou ao que estava: nada a assentar"
    );
}

/// Sem saber o nível do auto (antes do primeiro turno, ou CLI sem catálogo).
#[test]
fn desligar_o_auto_sem_nivel_conhecido_pega_o_meio() {
    let mut dial = EffortDialState::new(&levels(), None, None);
    assert_eq!(dial.label(), "");
    dial.toggle_auto();
    assert_eq!(dial.value(), Some("high"), "o do meio de cinco");
}

#[test]
fn ligar_o_auto_a_partir_de_um_nivel() {
    let mut dial = EffortDialState::new(&levels(), Some("max"), Some("medium"));
    dial.toggle_auto();
    assert!(dial.is_auto());
    assert_eq!(dial.slider_index(), 1);
    assert_eq!(dial.label(), "medium…");
}

/// Mexer na barra em auto escolhe o nível e desliga o auto, mesmo sem sair do
/// lugar.
#[test]
fn tocar_na_barra_sai_do_auto() {
    let mut dial = EffortDialState::new(&levels(), None, Some("high"));
    dial.move_to(dial.slider_index() as i64);
    assert!(!dial.is_auto());
    assert_eq!(dial.value(), Some("high"));
}

#[test]
fn modelo_sem_esforco_nao_tem_o_que_ligar() {
    let mut dial = EffortDialState::new(&[], None, None);
    assert_eq!(dial.label(), "sem esforço");
    assert!(!dial.is_usable());
    dial.move_to(2);
    assert_eq!(dial.value(), None);
}

#[test]
fn escolha_assenta_uma_vez() {
    let mut dial = EffortDialState::new(&levels(), Some("low"), None);
    dial.move_to(4);
    dial.move_to(99);
    assert_eq!(dial.value(), Some("max"), "fora da lista fica na ponta");
    assert!(dial.is_pending());
    assert_eq!(dial.settle(), Some(Some("max".to_owned())));
    assert_eq!(dial.settle(), None, "nada pendente");
}

// ---- SlashCommand ----------------------------------------------------------

fn slash(name: &str, detail: &str, source: SlashSource) -> SlashCommand {
    SlashCommand::new(name, detail, source)
}

fn names(list: &[SlashCommand]) -> Vec<&str> {
    list.iter().map(|c| c.name.as_str()).collect()
}

#[test]
fn matching_prefere_prefixo_e_nome_curto_do_plugin() {
    let all = vec![
        slash("compact", "", SlashSource::Builtin),
        slash("figma:figma-use", "", SlashSource::Plugin("figma".into())),
        slash("clear", "", SlashSource::Builtin),
        slash(
            "ralph-loop:cancel-ralph",
            "",
            SlashSource::Plugin("ralph-loop".into()),
        ),
    ];
    assert_eq!(names(&SlashCommand::matching(&all, "")), names(&all));
    assert_eq!(
        names(&SlashCommand::matching(&all, "c")),
        ["compact", "clear", "ralph-loop:cancel-ralph"]
    );
    // Contém, mas não começa: vem depois de quem começa.
    let mut with_config = vec![slash("config", "", SlashSource::Builtin)];
    with_config.extend(all.clone());
    assert_eq!(
        names(&SlashCommand::matching(&with_config, "fig")),
        ["figma:figma-use", "config"]
    );
    assert_eq!(
        names(&SlashCommand::matching(&all, "figma-u")),
        ["figma:figma-use"]
    );
    assert_eq!(
        names(&SlashCommand::matching(&all, "RALPH")),
        ["ralph-loop:cancel-ralph"]
    );
    let mut usage = slash("usage", "", SlashSource::Builtin);
    usage.aliases = strings(&["cost", "stats"]);
    let mut with_usage = all;
    with_usage.push(usage);
    assert_eq!(
        names(&SlashCommand::matching(&with_usage, "cos")),
        ["usage"]
    );
}

#[test]
fn busca_casa_cada_palavra_no_nome_apelido_ou_descricao() {
    let mut usage = slash("usage", "Custo da sessão", SlashSource::Builtin);
    usage.aliases = strings(&["cost"]);
    let all = vec![
        slash(
            "anthropic-skills:pdf",
            "Lê e cria arquivos PDF",
            SlashSource::Plugin("anthropic-skills".into()),
        ),
        slash("debug", "Turn on debug logging", SlashSource::Bundled),
        slash(
            "export",
            "Exporta a conversa para PDF",
            SlashSource::Builtin,
        ),
        usage,
    ];
    assert_eq!(names(&SlashCommand::searching(&all, "")), names(&all));
    // Pelo nome antes de pela descrição.
    assert_eq!(
        names(&SlashCommand::searching(&all, "pdf")),
        ["anthropic-skills:pdf", "export"]
    );
    assert_eq!(
        names(&SlashCommand::searching(&all, "LOGGING turn")),
        ["debug"]
    );
    assert_eq!(
        names(&SlashCommand::searching(&all, "le arquivos")),
        ["anthropic-skills:pdf"]
    );
    assert_eq!(names(&SlashCommand::searching(&all, "cost")), ["usage"]);
    assert!(SlashCommand::searching(&all, "pdf debug").is_empty());
}

#[test]
fn frontmatter_dobrado_aspas_e_oculto() {
    let folded = Frontmatter::parse(
        "---\nname: aws-cdk\ndescription: >-\n  Authors and deploys\n  CDK stacks.\n---\ncorpo",
    );
    assert_eq!(folded.name.as_deref(), Some("aws-cdk"));
    assert_eq!(
        folded.description.as_deref(),
        Some("Authors and deploys CDK stacks.")
    );
    assert!(folded.invocable);

    let quoted =
        Frontmatter::parse("---\ndescription: \"Start Ralph Loop\"\nuser-invocable: false\n---\n");
    assert_eq!(quoted.description.as_deref(), Some("Start Ralph Loop"));
    assert!(!quoted.invocable);

    let bare = Frontmatter::parse("# Cria uma worktree\n\nPara: $ARGUMENTS");
    assert_eq!(bare.description, None);
    assert_eq!(bare.first_line.as_deref(), Some("Cria uma worktree"));
}

#[test]
fn catalogo_le_usuario_projeto_e_plugins_ligados() {
    let root = fresh_dir("slash-");
    let root = root.path();
    let config = root.join("config");
    let project = root.join("repo");
    let plugin = root.join("cache/figma");
    let off = root.join("cache/off");

    write(
        &config.join("commands/new-worktree.md"),
        "Cria uma worktree",
    );
    write(
        &config.join("skills/egeon/SKILL.md"),
        "---\nname: egeon\ndescription: Falar com os vizinhos\n---\n",
    );
    write(&config.join("skills/README.md"), "não é skill");
    write(
        &config.join("skills/oculta/SKILL.md"),
        "---\nname: oculta\nuser-invocable: false\n---\n",
    );
    write(
        &project.join(".claude/commands/clear.md"),
        "---\ndescription: clear do projeto\n---\n",
    );
    write(
        &plugin.join("skills/figma-use/SKILL.md"),
        "---\nname: figma-use\ndescription: Usa o Figma\n---\n",
    );
    write(&off.join("commands/nada.md"), "desligado");
    write(
        &config.join("settings.json"),
        r#"{"enabledPlugins": {"figma@oficial": true, "off@oficial": false}}"#,
    );
    write(
        &config.join("plugins/installed_plugins.json"),
        &json!({"version": 2, "plugins": {
            "figma@oficial": [{"installPath": plugin}],
            "off@oficial": [{"installPath": off}]
        }})
        .to_string(),
    );

    let found = slash_catalog::commands(&config, Some(&project), None, None);
    let by_name: BTreeMap<&str, &SlashCommand> =
        found.iter().rev().map(|c| (c.name.as_str(), c)).collect();
    assert_eq!(by_name["new-worktree"].detail, "Cria uma worktree");
    assert_eq!(by_name["egeon"].source, SlashSource::User);
    assert_eq!(
        by_name["figma:figma-use"].source,
        SlashSource::Plugin("figma".into())
    );
    assert!(!by_name.contains_key("oculta"));
    assert!(!by_name.contains_key("off:nada"));
    // O do projeto vence o embutido de mesmo nome.
    assert_eq!(by_name["clear"].source, SlashSource::Project);
    assert_eq!(found.iter().filter(|c| c.name == "clear").count(), 1);
    assert!(by_name.contains_key("compact"));
}

#[test]
fn registro_le_embutidos_e_skills_do_binario() {
    let js = r#"
x={type:"local",name:"compact",description:"Free up context",load:()=>1};
y={type:"local-jsx",name:"plugin",aliases:["plugins"],description:'Manage plugins',load:()=>2};
z={type:"local",name:"agents",description:"(removed)",isHidden:!0,load:()=>3};
b={type:"local-jsx",name:"btw",description:"Side {question}",requires:{ink:!0}},E=I;var R={isHidden:!0,name:"stub"};
w={type:"prompt",name:"init",get description(){return a},load:()=>4};
var R={description:"Restore a previous point",name:"rewind",aliases:["checkpoint","undo"],type:"local",load:()=>5};
var S={type:"local",name:"stub2",isEnabled:()=>!1,load:()=>6};
Wi({name:"debug",menuDescription:"Turn on debug — logs",description:"x",disableModelInvocation:!0,async getPromptForCommand(){}});
Wi({name:"batch",menuDescription:"Plan a large change",description:"y",async getPromptForCommand(){}});
Wi({name:"keybindings-help",description:'Rebind keys',userInvocable:!1,async getPromptForCommand(){}});
f({name:"nada",value:1});
"#;
    let found = CommandRegistry::parse_binary(js.as_bytes());
    let name_of = |list: &[Entry]| list.iter().map(|e| e.name.clone()).collect::<Vec<_>>();
    assert_eq!(
        name_of(&found.builtins),
        ["btw", "compact", "init", "plugin", "rewind"]
    );
    let builtin = |name: &str| found.builtins.iter().find(|e| e.name == name).expect(name);
    // Campos em outra ordem: o objeto é achado pelo `type:`.
    assert_eq!(builtin("rewind").detail, "Restore a previous point");
    assert_eq!(
        builtin("rewind").aliases,
        Some(strings(&["checkpoint", "undo"]))
    );
    assert_eq!(builtin("btw").detail, "Side {question}");
    assert_eq!(builtin("plugin").detail, "Manage plugins");
    // Getter não é literal: fica sem legenda, mas fica na lista.
    assert_eq!(builtin("init").detail, "");
    assert_eq!(name_of(&found.skills), ["batch", "debug"]);
    let skill_of = |name: &str| found.skills.iter().find(|e| e.name == name).expect(name);
    assert_eq!(skill_of("debug").detail, "Turn on debug — logs");
    assert!(skill_of("debug").user_only);
    assert!(!skill_of("batch").user_only);
    assert_eq!(found.hidden, ["agents", "keybindings-help", "stub2"]);
}

#[test]
fn listagem_da_sessao_mantem_a_ordem_e_recomeca_no_inicial() {
    fn line(names: &[&str], content: &str, initial: bool) -> String {
        json!({"type": "attachment", "attachment": {
            "type": "skill_listing", "names": names, "content": content, "isInitial": initial}})
        .to_string()
    }
    let jsonl = [
        line(&["velha"], "- velha: some", true),
        r#"{"type":"user","message":{"content":"fala do \"skill_listing\" no texto"}}"#.to_owned(),
        line(
            &["simplify", "figma:figma-use"],
            "- simplify: Limpa o código\n- figma:figma-use: Usa o Figma",
            true,
        ),
        line(&["loop"], "- loop: Repete", false),
    ]
    .join("\n");
    let found = slash_catalog::skill_listing(jsonl.as_bytes());
    assert_eq!(
        found.iter().map(|(n, _)| n.as_str()).collect::<Vec<_>>(),
        ["simplify", "figma:figma-use", "loop"]
    );
    assert_eq!(
        found.iter().map(|(_, d)| d.as_str()).collect::<Vec<_>>(),
        ["Limpa o código", "Usa o Figma", "Repete"]
    );
}

#[test]
fn catalogo_junta_sincronizado_sessao_e_binario() {
    let root = fresh_dir("slash-");
    let root = root.path();
    let config = root.join("config");
    let repo = root.join("repo");
    let sub = repo.join("app/web");

    write(&repo.join(".git/HEAD"), "ref: main");
    write(
        &repo.join(".claude/skills/raiz/SKILL.md"),
        "---\ndescription: Da raiz\n---\n",
    );
    write(
        &sub.join(".claude/commands/frontend/component.md"),
        "Cria um componente",
    );
    // Acima da raiz do repositório não se procura.
    write(
        &root.join(".claude/skills/fora/SKILL.md"),
        "---\nname: fora\n---\n",
    );

    let skills = config.join("skills/synced/conta");
    write(
        &skills.join("manifest.json"),
        r#"{"skills": [{"name": "pdf"}]}"#,
    );
    write(
        &skills.join("pdf/SKILL.md"),
        "---\nname: pdf\ndescription: PDFs\n---\n",
    );
    write(
        &skills.join("removida/SKILL.md"),
        "---\nname: removida\n---\n",
    );
    let plugins = config.join("plugins/synced/conta");
    write(
        &plugins.join("manifest.json"),
        r#"{"plugins": [{"name": "cowork", "generation": 3}]}"#,
    );
    write(
        &plugins.join("cowork/skills/velha/SKILL.md"),
        "---\nname: velha\n---\n",
    );
    write(
        &plugins.join("cowork~g3/skills/nova/SKILL.md"),
        "---\nname: nova\n---\n",
    );

    let mut binary = CommandRegistry::default();
    let entry = |name: &str, detail: &str, user_only: bool| Entry {
        name: name.to_owned(),
        detail: detail.to_owned(),
        user_only,
        aliases: None,
    };
    binary.builtins = vec![
        entry("compact", "Free up context", false),
        entry("radio", "Lo-fi", false),
    ];
    binary.skills = vec![
        entry("debug", "Debug", true),
        entry("design-sync", "Desligada nesta sessão", false),
    ];
    binary.hidden = strings(&["keybindings-help"]);
    write(
        &config.join("skills/egeon/SKILL.md"),
        "---\nname: egeon\nuser-invocable: false\n---\n",
    );
    let loaded = vec![
        ("simplify".to_owned(), "Limpa".to_owned()),
        ("keybindings-help".to_owned(), "Teclas".to_owned()),
        ("egeon".to_owned(), "Só do modelo".to_owned()),
        ("anthropic-skills:pdf".to_owned(), "Repetida".to_owned()),
    ];

    let found = slash_catalog::commands(&config, Some(&sub), Some(&loaded), Some(&binary));
    let by_name: BTreeMap<&str, &SlashCommand> =
        found.iter().rev().map(|c| (c.name.as_str(), c)).collect();
    assert_eq!(by_name["frontend:component"].source, SlashSource::Project);
    assert_eq!(by_name["raiz"].detail, "Da raiz");
    assert!(!by_name.contains_key("fora"));
    assert_eq!(by_name["anthropic-skills:pdf"].detail, "PDFs");
    assert!(!by_name.contains_key("anthropic-skills:removida"));
    assert_eq!(
        by_name["cowork:nova"].source,
        SlashSource::Plugin("cowork".into())
    );
    assert!(!by_name.contains_key("cowork:velha"));
    assert_eq!(by_name["simplify"].source, SlashSource::Bundled);
    assert!(!by_name.contains_key("keybindings-help"));
    // Oculta no disco, mesmo que a sessão a liste.
    assert!(!by_name.contains_key("egeon"));
    assert_eq!(by_name["debug"].source, SlashSource::Bundled);
    assert!(!by_name.contains_key("design-sync"));
    // A legenda nossa vence a do binário; o que só o binário tem entra com a dele.
    assert_eq!(
        by_name["compact"].detail,
        "Resume a conversa para liberar contexto"
    );
    assert_eq!(by_name["radio"].detail, "Lo-fi");
    assert!(!by_name.contains_key("memory"));

    let entries: Vec<Value> = vec![
        json!({"scope": "project", "projectPath": root, "installPath": "/velha"}),
        json!({"scope": "user", "installPath": "/nova"}),
        json!({"scope": "project", "projectPath": repo, "installPath": "/deste"}),
    ];
    let projects = slash_catalog::project_roots(&sub);
    assert_eq!(
        slash_catalog::install_path(&entries, &projects).as_deref(),
        Some("/deste")
    );
    assert_eq!(
        slash_catalog::install_path(&entries[..2], &projects).as_deref(),
        Some("/nova")
    );

    // Sem a lista da sessão, as skills do binário entram todas.
    let fresh = slash_catalog::commands(&config, Some(&sub), None, Some(&binary));
    assert!(fresh.iter().any(|c| c.name == "design-sync"));
}

// ---- ClaudeSkill -----------------------------------------------------------

/// O frontmatter, sem os `---`. Vazio se o arquivo não abrir com um.
fn frontmatter_of(body: &str) -> String {
    let lines: Vec<&str> = body.split('\n').collect();
    if lines.first() != Some(&"---") {
        return String::new();
    }
    match lines[1..].iter().position(|l| *l == "---") {
        Some(close) => lines[1..=close].join("\n"),
        None => String::new(),
    }
}

#[test]
fn frontmatter_da_skill_e_legivel_pelo_cli() {
    // O CLI só lê o frontmatter quando o `---` é a PRIMEIRA linha; senão o
    // arquivo inteiro vira conteúdo e a skill nunca dispara sozinha.
    let front = frontmatter_of(skill::body());
    assert!(!front.is_empty(), "o frontmatter tem de abrir o arquivo");
    assert!(front.contains("name: egeon"));
    assert!(front.contains("description:"));
    assert!(front.contains("when_to_use:"), "os gatilhos moram aqui");
    assert!(front.contains("user-invocable: false"));
}

/// Um `: ` solto num escalar YAML derruba o frontmatter INTEIRO, sem erro
/// visível; por isso todo valor de texto vai em bloco (`>-`).
#[test]
fn valores_de_texto_usam_bloco_para_a_pontuacao_nao_quebrar_o_yaml() {
    let front = frontmatter_of(skill::body());
    assert!(front.contains("description: >-"), "descrição em bloco");
    assert!(front.contains("when_to_use: >-"), "gatilhos em bloco");
    for line in front.split('\n').filter(|l| !l.starts_with(' ')) {
        let Some(colon) = line.find(':') else {
            continue;
        };
        let value = line[colon + 1..].trim();
        if value.is_empty() || value == ">-" || value == ">" || value == "|" {
            continue;
        }
        assert!(!value.contains(": "), "`{line}` quebra o YAML");
        assert!(!value.contains(" #"), "`{line}` vira comentário no meio");
    }
}

#[test]
fn frases_de_gatilho_estao_no_frontmatter() {
    let front = frontmatter_of(skill::body());
    for phrase in [
        "pede pro",
        "delega isso",
        "monta um time",
        "em paralelo",
        "usa outro agente",
    ] {
        assert!(front.contains(phrase), "falta o gatilho '{phrase}'");
    }
}

#[test]
fn corpo_ensina_vizinhos_antes_de_subagente() {
    let body = skill::body();
    for command in ["egeon peers", "egeon peek", "egeon send", "egeon status"] {
        assert!(body.contains(command), "o corpo tem de ensinar `{command}`");
    }
    assert!(body.contains("Task/Agent"));
    assert!(body.contains("aresta"));
}

#[test]
fn corpo_ensina_a_responder_a_quem_acionou() {
    let body = skill::body();
    assert!(body.contains("[ED] mensagem de"));
    assert!(body.contains("egeon send <quem mandou>"));
    assert!(body.contains("Termine respondendo a ele"));
    assert!(body.contains("avise o remetente"));
    assert!(body.contains("fecha o ciclo, não abre outro"));
}

/// No ROOT do base path, que é onde o CLI procura skill pessoal.
#[test]
fn skill_mora_na_raiz_de_cada_config() {
    assert_eq!(
        skill::skill_file(Path::new("/tmp/.claude-agro"), "egeon"),
        PathBuf::from("/tmp/.claude-agro/skills/egeon/SKILL.md")
    );
}

/// A skill vai em TODAS as configurações: escrever numa só deixa sem ela
/// justamente o agente que aponta para a outra. Só dentro de pasta de teste.
#[test]
fn install_escreve_em_toda_config_e_reescreve() {
    let root = fresh_dir("skill-");
    let configs = vec![
        root.path().join(".claude"),
        root.path().join(".claude-agro"),
    ];
    let maestro = skill::PublishedSkill {
        name: "egeon-maestro".into(),
        body: "---\nname: egeon-maestro\n---\nmanual".into(),
    };
    let published = skill::published(&maestro, ShellSyntax::Posix);

    let written = skill::install(&configs, &published, None);
    let expected: Vec<PathBuf> = configs
        .iter()
        .flat_map(|c| {
            [
                skill::skill_file(c, "egeon"),
                skill::skill_file(c, "egeon-maestro"),
            ]
        })
        .collect();
    assert_eq!(written, expected);
    for file in written
        .iter()
        .filter(|f| f.to_string_lossy().contains("/skills/egeon/"))
    {
        assert_eq!(fs::read_to_string(file).expect("lê"), skill::body());
    }
    for file in written
        .iter()
        .filter(|f| f.to_string_lossy().contains("/skills/egeon-maestro/"))
    {
        assert_eq!(fs::read_to_string(file).expect("lê"), maestro.body);
    }

    // Reescrita a cada arranque: o texto acompanha a versão que subiu.
    fs::write(&written[0], "velho").expect("grava");
    skill::install(&configs, &published, None);
    assert_eq!(fs::read_to_string(&written[0]).expect("lê"), skill::body());
    assert!(
        skill::body().contains("Escrito pelo Egeon Deck"),
        "o arquivo mora na config do usuário: tem de dizer que é gerado"
    );
}

/// Decisão 54: no PowerShell a skill dos vizinhos manda o UTF-8 sem BOM e o
/// here-string; no macOS e no Linux o texto é o de antes.
#[test]
fn no_powershell_a_skill_traz_os_exemplos_em_powershell() {
    assert_eq!(skill::text(ShellSyntax::Posix), skill::body());
    let powershell = skill::text(ShellSyntax::PowerShell);
    assert!(!powershell.contains("<<"), "{powershell}");
    let lines: Vec<&str> = powershell.lines().collect();
    let count = |wanted: &str| lines.iter().filter(|l| **l == wanted).count();
    assert_eq!(
        (
            count("$OutputEncoding = [Text.UTF8Encoding]::new($false)"),
            count("@'"),
            count("'@ | egeon send <endereço>"),
            count("'@ | egeon trace"),
            count("'@ | egeon task ask <id>"),
        ),
        (2, 3, 1, 1, 1),
        "{powershell}"
    );
    assert!(powershell.contains("    egeon task done <id> [nota]     marca a tarefa como feita"));
    assert!(powershell.ends_with(skill::body().lines().last().unwrap()));
}

#[test]
fn install_apaga_a_pasta_da_primeira_tentativa() {
    let root = fresh_dir("skill-");
    let legacy = root.path().join("claude");
    write(&legacy.join("skills/egeon/SKILL.md"), "velha cópia");
    let configs = vec![root.path().join(".claude")];
    skill::install(
        &configs,
        &skill::published(
            &skill::PublishedSkill {
                name: "m".into(),
                body: "m".into(),
            },
            ShellSyntax::Posix,
        ),
        Some(&legacy),
    );
    assert!(!legacy.exists());
}

/// As configurações vêm do mesmo `config_glob` que o formulário do nó oferece,
/// mais a do ambiente — que pode estar fora do padrão `~/.claude*`.
#[test]
fn configuracoes_incluem_a_do_ambiente_sem_repetir() {
    let home = fresh_dir("home-");
    fs::create_dir(home.path().join(".claude")).expect("pasta");
    let profile = claude_code();
    assert_eq!(profile.config_env.as_deref(), Some("CLAUDE_CONFIG_DIR"));
    assert_eq!(profile.config_glob.as_deref(), Some("~/.claude*"));

    let outside = home.path().join("fora");
    let outside_text = outside.to_string_lossy().into_owned();
    let found = skill::config_directories(&profile, home.path(), |_| Some(outside_text.clone()));
    assert_eq!(found, vec![home.path().join(".claude"), outside]);

    let inside = home.path().join(".claude").to_string_lossy().into_owned();
    let found = skill::config_directories(&profile, home.path(), |_| Some(inside.clone()));
    assert_eq!(
        found,
        vec![home.path().join(".claude")],
        "o do ambiente já está no glob"
    );
}

// ---- ganchos ---------------------------------------------------------------

#[test]
fn ganchos_gravam_settings_que_chamam_o_egeon() {
    let dir = fresh_dir("hooks-");
    write(&dir.path().join("agent-hook.sh"), "velho");
    write(&dir.path().join("report-session.sh"), "velho");
    let egeon = Path::new("/Users/eu com espaço/bin/egeon");
    hooks::install(dir.path(), egeon).expect("instala");

    assert!(
        !dir.path().join("agent-hook.sh").exists(),
        "o egeon hook o substituiu"
    );
    assert!(!dir.path().join("report-session.sh").exists());
    let settings: Value = serde_json::from_str(
        &fs::read_to_string(hooks::settings_file(dir.path())).expect("settings"),
    )
    .expect("json");
    let hooks_map = settings["hooks"].as_object().expect("hooks");
    assert_eq!(
        hooks_map.keys().cloned().collect::<Vec<_>>(),
        [
            "Notification",
            "PermissionRequest",
            "SessionStart",
            "Stop",
            "StopFailure",
            "UserPromptSubmit"
        ]
    );
    let command = |event: &str, key: &str| {
        settings["hooks"][key][0]["hooks"][0]["command"]
            .as_str()
            .expect(event)
            .to_owned()
    };
    // Aspas: home com espaço no nome.
    assert_eq!(
        command("stop", "Stop"),
        "\"/Users/eu com espaço/bin/egeon\" hook stop"
    );
    assert_eq!(
        command("start", "SessionStart"),
        "\"/Users/eu com espaço/bin/egeon\" hook start"
    );
    assert_eq!(
        command("prompt", "UserPromptSubmit"),
        "\"/Users/eu com espaço/bin/egeon\" hook prompt"
    );
    assert_eq!(
        command("failure", "StopFailure"),
        "\"/Users/eu com espaço/bin/egeon\" hook failure"
    );
    assert_eq!(
        command("permission", "PermissionRequest"),
        "\"/Users/eu com espaço/bin/egeon\" hook permission"
    );
    assert_eq!(
        command("ask", "Notification"),
        "\"/Users/eu com espaço/bin/egeon\" hook ask"
    );
    // Mesmos tempos do Swift: 5 s, e o de permissão 600 s.
    assert_eq!(settings["hooks"]["Stop"][0]["hooks"][0]["timeout"], 5);
    assert_eq!(
        settings["hooks"]["PermissionRequest"][0]["hooks"][0]["timeout"],
        600
    );
    assert_eq!(
        settings["hooks"]["Notification"][0]["matcher"],
        "permission_prompt"
    );
}

#[test]
fn o_ambiente_dos_filhos_leva_as_tres_variaveis() {
    assert_eq!(
        hooks::CHILD_ENVIRONMENT,
        ["EGEON_TARGET", "EGEON_HOME", "EGEON_FLAVOR"]
    );
}

// ---- ClaudeTrust -----------------------------------------------------------

fn root_with(projects: Value) -> Value {
    json!({"numStartups": 3, "projects": projects})
}

#[test]
fn worktree_herda_o_que_o_repositorio_aceitou() {
    let config = root_with(json!({"/r/app": {
        "hasTrustDialogAccepted": true,
        "hasClaudeMdExternalIncludesApproved": true,
        "hasClaudeMdExternalIncludesWarningShown": true,
        "lastCost": 1.5}}));
    let updated =
        trust::inheriting(&config, "/r/worktrees/app/b1", &["/r/app".to_owned()]).expect("herda");
    let entry = &updated["projects"]["/r/worktrees/app/b1"];
    assert_eq!(entry["hasTrustDialogAccepted"], true);
    assert_eq!(entry["hasClaudeMdExternalIncludesApproved"], true);
    // Entrada nova com o esqueleto que o CLI espera, e nada da conversa da origem.
    assert!(entry.get("allowedTools").is_some());
    assert!(entry.get("lastCost").is_none());
    assert_eq!(updated["numStartups"], 3);
}

#[test]
fn nada_quando_origem_nao_aceitou_ou_alvo_ja_aceito() {
    let untrusted = root_with(json!({"/r/app": {"hasTrustDialogAccepted": false}}));
    assert!(trust::inheriting(&untrusted, "/r/wt", &["/r/app".to_owned()]).is_none());
    let done = root_with(json!({
        "/r/app": {"hasTrustDialogAccepted": true}, "/r/wt": {"hasTrustDialogAccepted": true}}));
    assert!(trust::inheriting(&done, "/r/wt", &["/r/app".to_owned()]).is_none());
    assert!(trust::inheriting(&done, "/r/x", &[]).is_none());
}

/// A pasta do multi-projeto junta repositórios: confia só se todos confiam.
#[test]
fn multiprojeto_precisa_de_todos_os_repositorios() {
    let half = root_with(json!({
        "/r/back": {"hasTrustDialogAccepted": true}, "/r/web": {"hasTrustDialogAccepted": false}}));
    let origins = ["/r/back".to_owned(), "/r/web".to_owned()];
    assert!(trust::inheriting(&half, "/r/worktrees/multi/b", &origins).is_none());
}

/// A chave é o realpath: `/private/tmp/...` não pode virar `/tmp/...`.
#[test]
fn prefixo_private_e_mantido() {
    let projects = json!({"/private/tmp/x/app": {"hasTrustDialogAccepted": true}});
    let projects = projects.as_object().expect("objeto");
    assert!(trust::granted(
        "hasTrustDialogAccepted",
        projects,
        "/private/tmp/x/app"
    ));
    assert!(!trust::granted(
        "hasTrustDialogAccepted",
        projects,
        "/tmp/x/app"
    ));
}

/// Aceito num pai também vale, como o Claude lê.
#[test]
fn pai_aceito_conta() {
    let config = root_with(json!({"/r": {"hasTrustDialogAccepted": true}}));
    let projects = config["projects"].as_object().expect("objeto");
    assert!(trust::granted(
        "hasTrustDialogAccepted",
        projects,
        "/r/app/sub"
    ));
    assert!(trust::granted(
        "hasTrustDialogAccepted",
        projects,
        "/r/app/sub/"
    ));
    assert!(!trust::granted(
        "hasTrustDialogAccepted",
        projects,
        "/outro"
    ));
}

fn git(args: &[&str], dir: &Path) -> bool {
    std::process::Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(args)
        .output()
        .is_ok_and(|o| o.status.success())
}

/// Repositório de verdade: worktree ligada herda do principal; pasta de
/// multi-projeto, dos repositórios de dentro; o principal não herda.
#[test]
fn fontes_com_git_de_verdade() {
    let base = fresh_dir("trust-");
    let repo = base.path().join("app");
    fs::create_dir_all(&repo).expect("pasta");
    if !git(&["init", "-q"], &repo) {
        return; // sem git na máquina não há o que provar
    }
    assert!(git(
        &[
            "-c",
            "user.email=a@b",
            "-c",
            "user.name=a",
            "commit",
            "-q",
            "--allow-empty",
            "-m",
            "x"
        ],
        &repo
    ));
    let multi = base.path().join("multi/b1");
    fs::create_dir_all(&multi).expect("pasta");
    assert!(git(
        &[
            "worktree",
            "add",
            "-q",
            "-b",
            "b1",
            multi.join("app").to_str().expect("utf8")
        ],
        &repo
    ));

    let real = |p: &Path| trust_seeder::real(p);
    assert_eq!(trust_seeder::sources(&repo, &trust_seeder::GitCli), None);
    let linked = trust_seeder::sources(&multi.join("app"), &trust_seeder::GitCli).expect("ligada");
    assert_eq!(linked.0, real(&multi.join("app")));
    assert_eq!(linked.1, vec![real(&repo)]);
    let folder = trust_seeder::sources(&multi, &trust_seeder::GitCli).expect("pasta");
    assert_eq!(folder.0, real(&multi));
    assert_eq!(folder.1, vec![real(&repo)]);
}

/// O caminho do lançamento: worktree ligada com a origem aceita herda no
/// `.claude.json` da config do nó, esteja ela onde estiver — como o Swift; a
/// decisão 36 vale só para as skills.
#[test]
fn lancamento_herda_no_config_do_no_mesmo_fora_da_pasta_de_dados() {
    let base = fresh_dir("launch-");
    let repo = base.path().join("app");
    fs::create_dir_all(&repo).expect("pasta");
    if !git(&["init", "-q"], &repo) {
        return; // sem git na máquina não há o que provar
    }
    assert!(git(
        &[
            "-c",
            "user.email=a@b",
            "-c",
            "user.name=a",
            "commit",
            "-q",
            "--allow-empty",
            "-m",
            "x"
        ],
        &repo
    ));
    let wt = base.path().join("wt");
    assert!(git(
        &[
            "worktree",
            "add",
            "-q",
            "-b",
            "b1",
            wt.to_str().expect("utf8")
        ],
        &repo
    ));
    let origin = trust_seeder::real(&repo);
    let target = trust_seeder::real(&wt);
    let accepted = root_with(json!({origin.clone(): {"hasTrustDialogAccepted": true}})).to_string();

    // A config "real" do nó, fora de qualquer pasta de dados — numa pasta
    // temporária, nunca a do usuário.
    let config = base.path().join("claude-personal");
    fs::create_dir_all(&config).expect("pasta");
    write(&config.join(".claude.json"), &accepted);
    let read = |dir: &Path| -> Value {
        serde_json::from_str(&fs::read_to_string(dir.join(".claude.json")).expect("lê"))
            .expect("json")
    };
    let launch = |cwd: &Path, config: Option<&str>| {
        trust_seeder::prepare_for_launch(cwd, config, base.path(), &trust_seeder::GitCli)
    };

    assert!(launch(&wt, config.to_str()), "herda na config do nó");
    assert_eq!(
        read(&config)["projects"][&target]["hasTrustDialogAccepted"],
        true
    );
    assert_eq!(
        read(&config)["projects"][&origin]["hasTrustDialogAccepted"],
        true,
        "o resto do arquivo fica"
    );
    assert!(!launch(&wt, config.to_str()), "já herdou");
    // O checkout principal não herda de ninguém, mas fica aceito de vez: a
    // confiança ele já tinha; ganha os dois avisos dos imports.
    assert!(launch(&repo, config.to_str()));
    assert_eq!(
        read(&config)["projects"][&origin]["hasClaudeMdExternalIncludesApproved"],
        true
    );
    assert!(!launch(&repo, config.to_str()), "já aceito");
    // Sem CLAUDE_CONFIG_DIR o alvo é o `~/.claude.json` da home dada (aqui,
    // temporária); sem arquivo, não cria um.
    assert!(!launch(&wt, None));
    assert!(!base.path().join(".claude.json").exists());
    write(&base.path().join(".claude.json"), &accepted);
    assert!(launch(&wt, None), "a config padrão também herda");
    assert_eq!(
        read(base.path())["projects"][&target]["hasTrustDialogAccepted"],
        true
    );
}

/// Além do Swift (decisão do Julio): a pasta do nó fica sempre aceita, mesmo
/// sem origem de onde herdar — entrada nova com o `blankProject`, a confiança e
/// os dois avisos dos imports, e o resto do arquivo intacto.
#[test]
fn lancamento_aceita_a_pasta_sem_origem_nenhuma() {
    let base = fresh_dir("accept-");
    let folder = base.path().join("solta");
    fs::create_dir_all(&folder).expect("pasta");
    let config = base.path().join("cfg");
    fs::create_dir_all(&config).expect("pasta");
    write(
        &config.join(".claude.json"),
        &json!({"numStartups": 3, "projects": {}}).to_string(),
    );
    let launch = || {
        trust_seeder::prepare_for_launch(
            &folder,
            config.to_str(),
            base.path(),
            &trust_seeder::GitCli,
        )
    };
    assert!(launch(), "sem origem, aceita assim mesmo");
    let read: Value =
        serde_json::from_str(&fs::read_to_string(config.join(".claude.json")).expect("lê"))
            .expect("json");
    let entry = &read["projects"][&trust_seeder::real(&folder)];
    assert_eq!(entry["hasTrustDialogAccepted"], true);
    assert_eq!(entry["hasClaudeMdExternalIncludesApproved"], true);
    assert_eq!(entry["hasClaudeMdExternalIncludesWarningShown"], true);
    assert_eq!(
        entry["allowedTools"],
        json!([]),
        "entrada nova do blankProject"
    );
    assert_eq!(read["numStartups"], 3, "o resto do arquivo fica");
    assert!(!launch(), "já aceita");
}

#[test]
fn seeder_grava_a_heranca_no_arquivo_do_cli() {
    let dir = fresh_dir("seed-");
    let file = trust_seeder::config_file(Some(dir.path().to_str().expect("utf8")), Path::new("/h"));
    assert_eq!(file, dir.path().join(".claude.json"));
    assert_eq!(
        trust_seeder::config_file(None, Path::new("/h")),
        PathBuf::from("/h/.claude.json")
    );
    write(
        &file,
        &root_with(json!({"/r/app": {"hasTrustDialogAccepted": true}})).to_string(),
    );
    assert!(trust_seeder::prepare(
        "/r/wt",
        &["/r/app".to_owned()],
        &file
    ));
    let after: Value = serde_json::from_str(&fs::read_to_string(&file).expect("lê")).expect("json");
    assert_eq!(after["projects"]["/r/wt"]["hasTrustDialogAccepted"], true);
    assert!(
        !trust_seeder::prepare("/r/wt", &["/r/app".to_owned()], &file),
        "já herdou"
    );
    assert!(!trust_seeder::prepare("/r/wt", &[], &file));
    assert!(!trust_seeder::prepare(
        "/r/wt",
        &["/r/app".to_owned()],
        &dir.path().join("nao-existe.json")
    ));
}

// ---- revisão: o que o `Int` do Swift aceita, o arquivo que o usuário editou ----

#[test]
fn inteiro_negativo_editado_a_mao_abre_o_arquivo() {
    let home = fresh_dir("agents-");
    write(
        &store::config_path(home.path()),
        r#"{"c":{"displayName":"C","command":["c"],"idle":{"ms":-1,"warmupMs":-5},"inject":{"submitDelayMs":-1},"attention":{"minWorkMs":-9}}}"#,
    );
    let profiles = store::load(home.path());
    assert_eq!(
        profiles.keys().collect::<Vec<_>>(),
        ["c"],
        "o arquivo do usuário não foi trocado pelos padrões"
    );
    let c = &profiles["c"];
    assert_eq!(c.idle.as_ref().map(|i| i.ms), Some(-1));
    // Negativo vira zero ao virar `Duration`.
    assert_eq!(c.idle_interval(), std::time::Duration::ZERO);
    assert_eq!(c.warmup_interval(), std::time::Duration::ZERO);
    assert_eq!(c.inject_config().submit_delay(), std::time::Duration::ZERO);
    assert_eq!(c.attention_config().min_work(), std::time::Duration::ZERO);
}

/// Sem `displayName` o Swift descarta o arquivo e grava os padrões de fábrica.
#[test]
fn perfil_sem_nome_ou_comando_descarta_o_arquivo_como_no_swift() {
    let home = fresh_dir("agents-");
    write(
        &store::config_path(home.path()),
        r#"{"c":{"command":["c"]}}"#,
    );
    let profiles = store::load(home.path());
    assert_eq!(
        profiles.keys().collect::<Vec<_>>(),
        ["claude", "codex", "gemini", "opencode"]
    );
}

#[test]
fn modelo_padrao_com_glob_sem_asterisco_tira_o_ultimo_caractere() {
    let home = fresh_dir("home-");
    write(
        &home.path().join(".claud/settings.json"),
        r#"{"model":"opus"}"#,
    );
    let mut profile = claude_code();
    profile.config_glob = Some("~/.claude".to_owned());
    assert_eq!(
        profile.default_model_name(None, home.path()).as_deref(),
        Some("opus")
    );
}

#[test]
fn prefixo_de_plugin_na_listagem_da_sessao() {
    let config = fresh_dir("slash-");
    let loaded: Vec<(String, String)> = [":x", "a:", "a:b", "plain"]
        .iter()
        .map(|n| ((*n).to_owned(), String::new()))
        .collect();
    let found = slash_catalog::commands(config.path(), None, Some(&loaded), None);
    let source = |name: &str| {
        found
            .iter()
            .find(|c| c.name == name)
            .map(|c| c.source.clone())
    };
    assert_eq!(source(":x"), Some(SlashSource::Bundled));
    assert_eq!(source("a:"), Some(SlashSource::Bundled));
    assert_eq!(source("a:b"), Some(SlashSource::Plugin("a".into())));
    assert_eq!(source("plain"), Some(SlashSource::Bundled));
}

#[test]
fn gravacao_atomica_nao_deixa_arquivo_temporario() {
    let dir = fresh_dir("atomic-");
    let egeon = Path::new("/bin/egeon");
    hooks::install(dir.path(), egeon).expect("instala");
    hooks::install(dir.path(), egeon).expect("reinstala");
    let names: Vec<String> = fs::read_dir(dir.path())
        .expect("lista")
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .collect();
    assert_eq!(names, ["claude-hooks.json"]);
    let configs = vec![dir.path().join(".claude")];
    let maestro = skill::PublishedSkill {
        name: "m".into(),
        body: "m".into(),
    };
    let written = skill::install(
        &configs,
        &skill::published(&maestro, ShellSyntax::Posix),
        None,
    );
    for file in written {
        let tmp = format!("{}.tmp", file.display());
        assert!(!Path::new(&tmp).exists(), "{tmp}");
    }
}

/// Só no unix: no Windows o atributo só-leitura proíbe trocar o arquivo, e o
/// cuidado que o teste guarda (o 0600 das credenciais) não existe lá.
#[cfg(unix)]
#[test]
fn seeder_mantem_a_permissao_do_original() {
    let dir = fresh_dir("seed-");
    let file = dir.path().join(".claude.json");
    write(
        &file,
        &root_with(json!({"/r/app": {"hasTrustDialogAccepted": true}})).to_string(),
    );
    // API portátil: só-leitura é a permissão que o `std` expressa em qualquer
    // sistema, e o arquivo novo tem de nascer com ela (o umask daria leitura e
    // escrita).
    let mut readonly = fs::metadata(&file).expect("meta").permissions();
    readonly.set_readonly(true);
    fs::set_permissions(&file, readonly).expect("permissão");
    assert!(trust_seeder::prepare(
        "/r/wt",
        &["/r/app".to_owned()],
        &file
    ));
    assert!(fs::metadata(&file).expect("meta").permissions().readonly());
}

#[test]
fn resolve_usa_a_checagem_de_executavel_do_driver() {
    let dir = fresh_dir("bin-");
    write(&dir.path().join("claude"), "x");
    let path = std::env::join_paths([Path::new("/nao/existe"), dir.path()])
        .expect("PATH")
        .to_string_lossy()
        .into_owned();
    let any_file: super::claude::catalog::Executable = |p| p.is_file();
    let never: super::claude::catalog::Executable = |_| false;
    assert!(super::claude::catalog::resolve("claude", &path, any_file).is_some());
    assert!(super::claude::catalog::resolve("claude", &path, never).is_none());
}

/// O instalador nativo do Windows deixa o `claude.exe`, e lá só executa o que
/// tem extensão: o nome com o sufixo do sistema também é procurado.
#[test]
fn resolve_acha_o_binario_com_o_sufixo_de_executavel_do_sistema() {
    let dir = fresh_dir("exe-");
    let exe = format!("claude{}", std::env::consts::EXE_SUFFIX);
    write(&dir.path().join(&exe), "x");
    let path = dir.path().to_string_lossy().into_owned();
    let with_suffix: super::claude::catalog::Executable = |p| {
        p.is_file()
            && p.file_name()
                .is_some_and(|n| n.to_string_lossy().ends_with(std::env::consts::EXE_SUFFIX))
    };
    let found = super::claude::catalog::resolve("claude", &path, with_suffix);
    assert_eq!(
        found.as_deref().and_then(Path::file_name),
        Some(std::ffi::OsStr::new(&exe))
    );
}

/// O manual do maestro passa pela mesma régua de YAML da skill dos vizinhos, e diz
/// logo de cara que só vale para quem é maestro (ADR-066). O texto é do dono do
/// maestro (`maestro::guide`); aqui só a régua que a publicação exige.
#[test]
fn skill_do_maestro_tem_frontmatter_legivel_e_com_porteiro() {
    let skill_text = crate::features::maestro::guide::skill(
        crate::features::terminal::shell::ShellSyntax::Posix,
    );
    let front = frontmatter_of(&skill_text);
    assert!(front.contains("name: egeon-maestro"));
    assert!(front.contains("description: >-"));
    assert!(front.contains("when_to_use: >-"));
    assert!(front.contains("monta a bancada"));
    assert!(
        front.contains("maestro true"),
        "a skill vai para toda config — diz quem pode"
    );
    for line in front.split('\n').filter(|l| !l.starts_with(' ')) {
        let Some(colon) = line.find(':') else {
            continue;
        };
        let value = line[colon + 1..].trim();
        if value.is_empty() || value == ">-" {
            continue;
        }
        assert!(!value.contains(": "), "`{line}` quebra o YAML");
    }
}

/// Só o CLI que fala por gancho ganha a linha da pergunta por ferramenta: é pelo
/// gancho que a pergunta chega ao chat (ADR-068).
#[test]
fn linha_da_pergunta_so_para_perfil_com_gancho() {
    let claude = claude_code()
        .system_prompt_text(Some("papel"), None, None)
        .expect("texto");
    assert!(claude.contains("AskUserQuestion"));
    let mut other = claude_code();
    other.report_session = None;
    let text = other
        .system_prompt_text(Some("papel"), None, None)
        .expect("texto");
    assert!(!text.contains("AskUserQuestion"));
}
