//! Porte de NodeConfigTests, NodeTemplateTests, NodeTemplateCrossCLITests e
//! da parte de nó de RetiredNodeTests.

use std::collections::BTreeMap;

use serde_json::json;

use super::model::*;
use super::{service, store};
use crate::commons::ids::NodeId;

fn node(json: &str) -> NodeConfig {
    serde_json::from_str(json).unwrap()
}

fn component(json: &str) -> NodeTemplate {
    serde_json::from_str(json).unwrap()
}

fn over(f: impl FnOnce(&mut Overrides)) -> Overrides {
    let mut o = Overrides::default();
    f(&mut o);
    o
}

fn some(text: &str) -> Option<String> {
    Some(text.to_owned())
}

// ── NodeConfigTests ────────────────────────────────────────────────────────

// Arquivo gravado antes da ADR-030 traz `sessionId`/`sessionStarted`. A carga
// absorve para os nomes novos e os antigos nunca voltam ao disco.
#[test]
fn nome_antigo_da_sessao_e_absorvido_na_carga() {
    let n = node(r#"{"type":"agent","id":"a","sessionId":"S123","sessionStarted":true}"#)
        .migrating_legacy_names();
    assert_eq!(n.conversation_id.as_deref(), Some("S123"));
    assert_eq!(n.conversation_started, Some(true));
    assert_eq!(n.session_id, None);
    assert_eq!(n.session_started, None);
}

#[test]
fn nomes_antigos_nunca_voltam_ao_disco() {
    let n = node(r#"{"type":"agent","id":"a","sessionId":"S123","sessionStarted":true}"#)
        .migrating_legacy_names();
    let text = serde_json::to_string(&n).unwrap();
    assert!(!text.contains("sessionId"));
    assert!(!text.contains("sessionStarted"));
    assert!(text.contains("conversationId"));
}

// Nome novo presente ganha do antigo: a migração não pode regredir uma
// conversa já migrada.
#[test]
fn migracao_nao_sobrescreve_o_nome_novo() {
    let n = node(r#"{"type":"agent","id":"a","conversationId":"NOVA","sessionId":"VELHA"}"#)
        .migrating_legacy_names();
    assert_eq!(n.conversation_id.as_deref(), Some("NOVA"));
}

// Copiar um nó é copiar a montagem, nunca a conversa.
#[test]
fn sem_conversa_limpa_a_conversa_e_guarda_a_montagem() {
    let n = node(
        r#"{"type":"agent","id":"revisor","agent":"claude","cwd":"src",
            "prompt":"revise","conversationId":"C1","conversationStarted":true,
            "transcript":"/tmp/t.jsonl"}"#,
    )
    .without_conversation();
    assert_eq!(n.conversation_id, None);
    assert_eq!(n.conversation_started, None);
    // O transcript é da conversa: mantido, o clone apontaria para a do original.
    assert_eq!(n.transcript, None);
    assert_eq!(n.id, "revisor");
    assert_eq!(n.agent.as_deref(), Some("claude"));
    assert_eq!(n.cwd.as_deref(), Some("src"));
    assert_eq!(n.prompt.as_deref(), Some("revise"));
}

// Renomear ou marcar maestro pelo formulário remonta o nó pelo componente, que
// não tem conversa: sem devolvê-la, o agente subia numa conversa nova.
#[test]
fn edicao_do_formulario_guarda_a_conversa_com_mesmo_cli_e_pasta() {
    let previous = node(
        r#"{"type":"agent","id":"dev","agent":"claude","cwd":"src","ultracode":true,
            "conversationId":"C1","conversationStarted":true,"transcript":"/tmp/t.jsonl"}"#,
    );
    let mut edited = NodeConfig::new(NodeKind::Agent, "dev-novo");
    edited.agent = some("claude");
    edited.cwd = some("src");
    edited.maestro = Some(true);

    let kept = edited.keeping_state(&previous);
    assert_eq!(kept.id, "dev-novo");
    assert_eq!(kept.maestro, Some(true));
    assert_eq!(kept.conversation_id.as_deref(), Some("C1"));
    assert_eq!(kept.conversation_started, Some(true));
    assert_eq!(kept.transcript.as_deref(), Some("/tmp/t.jsonl"));
    assert_eq!(kept.ultracode, Some(true));
}

// A conversa é do CLI e da pasta: em outra pasta ou outro CLI ela não abre.
#[test]
fn edicao_largua_a_conversa_se_a_pasta_ou_o_cli_mudam() {
    let previous = node(
        r#"{"type":"agent","id":"dev","agent":"claude","cwd":"src","conversationId":"C1",
            "conversationStarted":true}"#,
    );
    let mut moved = NodeConfig::new(NodeKind::Agent, "dev");
    moved.agent = some("claude");
    moved.cwd = some("outra");
    assert_eq!(moved.keeping_state(&previous).conversation_id, None);

    let mut other = NodeConfig::new(NodeKind::Agent, "dev");
    other.agent = some("codex");
    other.cwd = some("src");
    assert_eq!(other.keeping_state(&previous).conversation_id, None);
}

#[test]
fn edicao_do_formulario_guarda_o_endereco_web() {
    let previous = node(r#"{"type":"web","id":"docs","url":"https://x.dev","profile":"p"}"#);
    let kept = NodeConfig::new(NodeKind::Web, "docs").keeping_state(&previous);
    assert_eq!(kept.url.as_deref(), Some("https://x.dev"));
    assert_eq!(kept.profile.as_deref(), Some("p"));
}

#[test]
fn quadro_exige_os_quatro_valores_e_tamanho_positivo() {
    let mut n = NodeConfig::new(NodeKind::Shell, "t");
    assert_eq!(n.frame(), None);
    n.set_frame(Frame {
        x: 10.4,
        y: 20.5,
        w: 300.6,
        h: 200.0,
    });
    assert_eq!(
        n.frame(),
        Some(Frame {
            x: 10.0,
            y: 21.0,
            w: 301.0,
            h: 200.0
        })
    );
    n.w = Some(0.0);
    assert_eq!(n.frame(), None);
}

#[test]
fn maestro_so_vale_em_agente() {
    let mut n = NodeConfig::new(NodeKind::Shell, "t");
    n.maestro = Some(true);
    assert!(!n.is_maestro());
    n.kind = NodeKind::Agent;
    assert!(n.is_maestro() && n.approves_team_permissions());
    n.maestro = None;
    assert!(!n.is_maestro());
}

#[test]
fn papel_e_regras_efetivos_preferem_o_do_cli_em_uso() {
    let mut n = NodeConfig::new(NodeKind::Agent, "a");
    n.agent = some("codex");
    n.prompt = some("geral");
    n.rules = some("regras gerais");
    n.by_agent = Some(BTreeMap::from([(
        "codex".to_owned(),
        over(|o| o.prompt = some("do codex")),
    )]));
    assert_eq!(n.effective_prompt(), Some("do codex"));
    // O mapa existe, mas sem regra própria: vale a geral.
    assert_eq!(n.effective_rules(), Some("regras gerais"));
    n.agent = some("claude");
    assert_eq!(n.effective_prompt(), Some("geral"));
}

#[test]
fn leitura_tolerante_de_nos() {
    // Opcional ausente e `null` são nulos; chave desconhecida é ignorada.
    let n = node(r#"{"type":"queue","id":"q","cwd":null,"futuro":{"x":1}}"#);
    assert_eq!(n.kind, NodeKind::Queue);
    assert_eq!(n.cwd, None);
    // Tipo errado e tipo de nó desconhecido continuam sendo erro.
    assert!(serde_json::from_str::<NodeConfig>(r#"{"type":"robo","id":"x"}"#).is_err());
    assert!(
        serde_json::from_str::<NodeConfig>(r#"{"type":"shell","id":"x","maestro":1}"#).is_err()
    );
    assert!(serde_json::from_str::<NodeConfig>(r#"{"type":"shell"}"#).is_err());
}

#[test]
fn no_grava_so_o_que_tem_e_volta_igual() {
    let mut n = NodeConfig::new(NodeKind::Agent, "rev");
    n.agent = some("claude");
    n.set_frame(Frame {
        x: 1.0,
        y: 2.0,
        w: 3.0,
        h: 4.0,
    });
    n.by_agent = Some(BTreeMap::from([(
        "codex".to_owned(),
        over(|o| o.rules = some("r")),
    )]));
    let value = serde_json::to_value(&n).unwrap();
    assert_eq!(
        value,
        json!({"type":"agent","id":"rev","agent":"claude","byAgent":{"codex":{"rules":"r"}},
               "x":1.0,"y":2.0,"w":3.0,"h":4.0})
    );
    assert_eq!(serde_json::from_value::<NodeConfig>(value).unwrap(), n);
}

// ── RetiredNodeTests (componente) ──────────────────────────────────────────

#[test]
fn componente_do_tipo_editor_e_pulado() {
    let json =
        r#"{"vscode":{"name":"vscode","kind":"editor"},"zsh":{"name":"zsh","kind":"shell"}}"#;
    let map = decode_components(json.as_bytes()).unwrap();
    assert_eq!(map.keys().collect::<Vec<_>>(), ["zsh"]);
}

#[test]
fn outro_componente_ruim_derruba_o_mapa() {
    let json = r#"{"a":{"name":"a","kind":"robo"},"zsh":{"name":"zsh","kind":"shell"}}"#;
    assert!(decode_components(json.as_bytes()).is_none());
}

// ── NodeTemplateTests ──────────────────────────────────────────────────────

#[test]
fn captura_copia_so_a_montagem() {
    let n = node(
        r#"{"type":"agent","id":"rev","agent":"claude","cmd":"claude --foo",
            "config":"/Users/x/.claude-trabalho","cwd":"packages/api",
            "model":"opus","prompt":"revise","conversationId":"C1","transcript":"/t.jsonl"}"#,
    );
    let template = service::capture(&n, "Revisor");
    assert_eq!(template.kind, NodeKind::Agent);
    assert_eq!(template.agent.as_deref(), Some("claude"));
    assert_eq!(template.cwd.as_deref(), Some("packages/api"));
    assert_eq!(template.prompt.as_deref(), Some("revise"));
    // O que é do CLI mora no mapa dele desde a ADR-057.
    assert_eq!(
        template.resolved(Some("claude")).cmd.as_deref(),
        Some("claude --foo")
    );
    assert_eq!(
        template.resolved(Some("claude")).model.as_deref(),
        Some("opus")
    );
}

#[test]
fn instanciar_monta_o_no_sem_conversa() {
    let mut template = NodeTemplate::new("Revisor", NodeKind::Agent);
    template.agent = some("claude");
    template.cwd = some("src");
    template.prompt = some("revise");
    template.by_agent = Some(BTreeMap::from([(
        "claude".to_owned(),
        over(|o| o.model = some("sonnet")),
    )]));
    let n = service::instantiate(&template, "revisor-2");

    assert_eq!(n.kind, NodeKind::Agent);
    assert_eq!(n.id, "revisor-2");
    assert_eq!(n.agent.as_deref(), Some("claude"));
    assert_eq!(n.prompt.as_deref(), Some("revise"));
    assert_eq!(n.model.as_deref(), Some("sonnet"));
    assert_eq!(n.conversation_id, None);
    // O registro de origem: só informativo.
    assert_eq!(n.component.as_deref(), Some("Revisor"));
}

// O id sai do nome e entra no endereço de dispatch (`NodeId::slug`).
#[test]
fn identificador_e_previsivel() {
    assert_eq!(NodeId::slug("Revisor").as_str(), "revisor");
    assert_eq!(NodeId::slug("front / end").as_str(), "front-end");
    assert_eq!(NodeId::slug("  QA Ágil  ").as_str(), "qa-gil");
    assert_eq!(NodeId::slug("???").as_str(), "sh");
}

// ── NodeTemplateCrossCLITests ──────────────────────────────────────────────

fn revisor() -> NodeTemplate {
    let mut t = NodeTemplate::new("revisor", NodeKind::Agent);
    t.agent = some("claude");
    t.cwd = some("app");
    t.prompt = some("você revisa o diff");
    t.rules = some("escreva em português");
    t.by_agent = Some(BTreeMap::from([
        (
            "claude".to_owned(),
            over(|o| {
                o.config = some("~/.claude-agro");
                o.model = some("opus");
            }),
        ),
        (
            "opencode".to_owned(),
            over(|o| o.rules = some("aqui, comente em inglês")),
        ),
    ]));
    t
}

fn screen(
    config: Option<&str>,
    model: Option<&str>,
    effort: Option<&str>,
    prompt: Option<&str>,
    rules: Option<&str>,
) -> Resolved {
    let own = |s: Option<&str>| s.map(str::to_owned);
    Resolved {
        cmd: None,
        config: own(config),
        model: own(model),
        effort: own(effort),
        prompt: own(prompt),
        rules: own(rules),
    }
}

/// `opus` não existe no OpenCode e `~/.claude-agro` não diz nada ao Codex:
/// nada disso pode vazar de um CLI para outro.
#[test]
fn valor_de_um_cli_nao_vaza_para_outro() {
    let c = revisor();
    assert_eq!(c.resolved(Some("claude")).model.as_deref(), Some("opus"));
    assert_eq!(
        c.resolved(Some("claude")).config.as_deref(),
        Some("~/.claude-agro")
    );
    assert_eq!(c.resolved(Some("opencode")).model, None);
    assert_eq!(c.resolved(Some("opencode")).config, None);
    assert_eq!(
        c.resolved(Some("codex")).model,
        None,
        "CLI sem mapa não herda nada"
    );
}

#[test]
fn o_papel_atravessa_todo_cli() {
    let c = revisor();
    for cli in [Some("claude"), Some("opencode"), Some("codex"), None] {
        assert_eq!(
            c.resolved(cli).prompt.as_deref(),
            Some("você revisa o diff")
        );
        assert_eq!(c.cwd.as_deref(), Some("app"));
    }
}

/// O caminho que o usuário descreveu: escreve com o Claude Code na tela,
/// reabre no Codex, edita ali — e o do Claude continua lá.
#[test]
fn editar_sob_outro_cli_guarda_o_que_o_primeiro_tinha() {
    let mut novo = NodeTemplate::new("cleber", NodeKind::Agent);
    novo.agent = some("claude");
    let com_claude = novo.remembering(
        Some("claude"),
        screen(
            Some("~/.claude"),
            Some("opus"),
            None,
            Some("teste claude"),
            None,
        ),
    );
    assert_eq!(
        com_claude.prompt.as_deref(),
        Some("teste claude"),
        "o primeiro texto é geral"
    );
    assert_eq!(com_claude.overrides(Some("claude")).prompt, None);

    let com_codex = com_claude.remembering(
        Some("codex"),
        screen(None, None, None, Some("teste codex"), None),
    );
    assert_eq!(
        com_codex.resolved(Some("codex")).prompt.as_deref(),
        Some("teste codex")
    );
    assert_eq!(
        com_codex.resolved(Some("claude")).prompt.as_deref(),
        Some("teste claude"),
        "o do Claude Code não foi tocado"
    );
    assert_eq!(
        com_codex.resolved(Some("claude")).model.as_deref(),
        Some("opus")
    );
    assert_eq!(
        com_codex.resolved(Some("codex")).model,
        None,
        "modelo não atravessa"
    );

    // Voltar ao texto geral desfaz a exceção.
    let devolta = com_codex.remembering(
        Some("codex"),
        screen(None, None, None, Some("teste claude"), None),
    );
    assert_eq!(devolta.overrides(Some("codex")).prompt, None);
    assert_eq!(
        devolta.resolved(Some("codex")).prompt.as_deref(),
        Some("teste claude")
    );
}

#[test]
fn lembrar_um_cli_guarda_os_outros() {
    let base = revisor().remembering(
        Some("codex"),
        screen(Some("~/.codex"), None, None, None, Some("regra do codex")),
    );
    assert_eq!(base.resolved(Some("claude")).model.as_deref(), Some("opus"));
    assert_eq!(
        base.resolved(Some("opencode")).rules.as_deref(),
        Some("aqui, comente em inglês")
    );
    assert_eq!(
        base.resolved(Some("codex")).rules.as_deref(),
        Some("regra do codex")
    );
    assert_eq!(
        base.rules.as_deref(),
        Some("escreva em português"),
        "o geral fica de pé"
    );
}

/// O caminho inteiro pela UI, onde o vazamento apareceu: o texto escrito com um
/// CLI na tela não pode virar o GERAL ao reabrir o formulário.
#[test]
fn reabrir_nao_promove_o_texto_de_um_cli_a_geral() {
    let mut novo = NodeTemplate::new("cleber", NodeKind::Agent);
    novo.agent = some("claude");
    let claude = novo.remembering(
        Some("claude"),
        screen(None, None, None, Some("teste claude"), None),
    );
    let mut com_gemini = claude.remembering(
        Some("gemini"),
        screen(None, None, None, Some("teste gemini"), None),
    );
    com_gemini.agent = some("gemini");

    let n = service::instantiate(&com_gemini, "cleber");
    assert_eq!(
        n.effective_prompt(),
        Some("teste gemini"),
        "é o que sobe no Gemini"
    );
    assert_eq!(
        n.prompt.as_deref(),
        Some("teste claude"),
        "mas o geral continua o geral"
    );

    let reaberto = service::capture(&n, "cleber");
    assert_eq!(
        reaberto.resolved(Some("claude")).prompt.as_deref(),
        Some("teste claude"),
        "abrir com o Claude Code na tela não pode mostrar o do Gemini"
    );
    assert_eq!(
        reaberto.resolved(Some("gemini")).prompt.as_deref(),
        Some("teste gemini")
    );
    assert_eq!(
        reaberto.resolved(Some("codex")).prompt.as_deref(),
        Some("teste claude"),
        "um CLI sem exceção vê o geral"
    );
}

/// A memória viaja com o nó e sobrevive a gravar e reler.
#[test]
fn o_mapa_de_cli_sobrevive_no_no() {
    let component = revisor();
    let n = service::instantiate(&component, "rev");
    assert_eq!(
        n.by_agent
            .as_ref()
            .and_then(|m| m.get("opencode"))
            .and_then(|o| o.rules.as_deref()),
        Some("aqui, comente em inglês")
    );

    let decoded: NodeConfig = serde_json::from_str(&serde_json::to_string(&n).unwrap()).unwrap();
    assert_eq!(
        decoded
            .by_agent
            .as_ref()
            .and_then(|m| m.get("opencode"))
            .and_then(|o| o.rules.as_deref()),
        Some("aqui, comente em inglês"),
        "gravar e reler o workbenches.json não pode perder a memória"
    );

    let again = service::capture(&decoded, "revisor");
    assert_eq!(
        again.resolved(Some("opencode")).rules.as_deref(),
        Some("aqui, comente em inglês")
    );
    assert_eq!(
        again.resolved(Some("claude")).model.as_deref(),
        Some("opus")
    );
}

/// Regra por CLI SUBSTITUI a geral — override, não soma.
#[test]
fn regra_por_cli_substitui_em_vez_de_somar() {
    let c = revisor();
    assert_eq!(
        c.resolved(Some("claude")).rules.as_deref(),
        Some("escreva em português")
    );
    assert_eq!(
        c.resolved(Some("opencode")).rules.as_deref(),
        Some("aqui, comente em inglês")
    );
    assert_eq!(
        c.resolved(Some("codex")).rules.as_deref(),
        Some("escreva em português")
    );
}

#[test]
fn instanciar_usa_o_cli_escolhido() {
    let mut c = revisor();
    c.agent = some("opencode");
    let n = service::instantiate(&c, "rev");
    assert_eq!(n.agent.as_deref(), Some("opencode"));
    assert_eq!(n.model, None, "o modelo do Claude não sobe num OpenCode");
    assert_eq!(n.config, None);
    assert_eq!(n.effective_rules(), Some("aqui, comente em inglês"));
    assert_eq!(
        n.rules.as_deref(),
        Some("escreva em português"),
        "o geral fica no geral"
    );
    assert_eq!(n.prompt.as_deref(), Some("você revisa o diff"));
    assert_eq!(n.component.as_deref(), Some("revisor"));
}

/// Componente escrito antes da ADR-057 tem `cmd`/`config`/`model` na raiz — eles
/// eram do CLI o tempo todo e viram o mapa daquele CLI.
#[test]
fn campos_da_raiz_antigos_viram_o_mapa_do_cli() {
    let c = component(
        r#"{"name":"revisor","kind":"agent","agent":"claude","model":"opus",
            "config":"~/.claude-agro","cmd":"claude --foo","prompt":"revise","rules":"em português"}"#,
    );
    let claude = c.resolved(Some("claude"));
    assert_eq!(claude.model.as_deref(), Some("opus"));
    assert_eq!(claude.config.as_deref(), Some("~/.claude-agro"));
    assert_eq!(claude.cmd.as_deref(), Some("claude --foo"));
    assert_eq!(claude.rules.as_deref(), Some("em português"));
    assert_eq!(
        c.resolved(Some("opencode")).model,
        None,
        "não vaza para o outro CLI"
    );

    // E é reescrito na forma nova, sem as chaves da raiz.
    let written = serde_json::to_value(&c).unwrap();
    assert!(written.get("model").is_none());
    assert!(written.get("config").is_none());
    assert!(
        written.get("cmd").is_none(),
        "cmd na raiz só existe em shell"
    );
    assert!(written.get("byAgent").is_some());
    let again: NodeTemplate = serde_json::from_value(written).unwrap();
    assert_eq!(
        again.resolved(Some("claude")).model.as_deref(),
        Some("opus")
    );
}

#[test]
fn comando_de_shell_fica_na_raiz_e_o_mapa_ja_escrito_ganha() {
    let shell = component(r#"{"name":"build","kind":"shell","cmd":"make -j8"}"#);
    assert_eq!(shell.command.as_deref(), Some("make -j8"));
    assert_eq!(
        shell.by_agent, None,
        "shell sem agente não tem para onde migrar"
    );
    assert_eq!(serde_json::to_value(&shell).unwrap()["cmd"], "make -j8");

    // O mapa que já existe para o CLI ganha da raiz antiga.
    let c = component(
        r#"{"name":"r","kind":"agent","agent":"claude","model":"velho",
            "byAgent":{"claude":{"model":"novo"}}}"#,
    );
    assert_eq!(c.resolved(Some("claude")).model.as_deref(), Some("novo"));
}

/// Capturar um terminal guarda o que é dele no mapa do CLI em que ele roda.
#[test]
fn captura_separa_o_papel_do_cli() {
    let mut n = NodeConfig::new(NodeKind::Agent, "rev");
    n.agent = some("claude");
    n.model = some("opus");
    n.config = some("~/.claude-agro");
    n.prompt = some("revise");
    n.rules = some("em português");

    let c = service::capture(&n, "revisor");
    assert_eq!(
        c.rules.as_deref(),
        Some("em português"),
        "regra do nó vira a geral"
    );
    assert_eq!(c.resolved(Some("claude")).model.as_deref(), Some("opus"));
    assert_eq!(c.resolved(Some("opencode")).model, None);
}

/// Esforço é do CLI, como o modelo.
#[test]
fn esforco_viaja_com_o_cli() {
    let mut base = NodeTemplate::new("rev", NodeKind::Agent);
    base.agent = some("claude");
    let base = base.remembering(
        Some("claude"),
        screen(None, Some("opus"), Some("high"), Some("revise"), None),
    );
    assert_eq!(
        base.resolved(Some("claude")).effort.as_deref(),
        Some("high")
    );
    assert_eq!(
        base.resolved(Some("codex")).effort,
        None,
        "esforço não atravessa"
    );

    let n = service::instantiate(&base, "rev");
    assert_eq!(n.effort.as_deref(), Some("high"));

    let mut edited = n;
    edited.effort = some("max");
    let captured = service::capture(&edited, "rev");
    assert_eq!(
        captured.resolved(Some("claude")).effort.as_deref(),
        Some("max")
    );
    assert_eq!(
        captured.resolved(Some("claude")).model.as_deref(),
        Some("opus")
    );
}

#[test]
fn maestro_so_nasce_em_agente() {
    let mut c = NodeTemplate::new("m", NodeKind::Shell);
    c.maestro = Some(true);
    assert_eq!(service::instantiate(&c, "m").maestro, None);
    c.kind = NodeKind::Agent;
    assert_eq!(service::instantiate(&c, "m").maestro, Some(true));
    assert_eq!(
        service::capture(&service::instantiate(&c, "m"), "m").maestro,
        Some(true)
    );
}

// ── components.json ────────────────────────────────────────────────────────

#[test]
fn arquivo_de_componentes_grava_le_poe_e_tira() {
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join("components.json");
    assert!(store::load(&file).is_empty(), "sem arquivo é vazio");

    store::put(&file, revisor()).unwrap();
    store::put(&file, NodeTemplate::new("build", NodeKind::Shell)).unwrap();
    assert_eq!(store::names(&file), ["build", "revisor"]);
    assert_eq!(store::component(&file, "revisor"), Some(revisor()));

    store::remove(&file, "build").unwrap();
    assert_eq!(store::names(&file), ["revisor"]);

    // Arquivo quebrado é mapa vazio, não pânico.
    std::fs::write(&file, "{quebrado").unwrap();
    assert!(store::load(&file).is_empty());
}

// ── ConfigItemsTests (o popup de configuração do CLI) ──────────────────────

/// O padrão da configuração é o caminho que o CLI usa sem a variável.
#[test]
fn o_padrao_aparece_pelo_caminho_e_nao_se_repete() {
    let home = "/Users/eu";
    let discovered = vec![format!("{home}/.claude"), format!("{home}/.claude-agro")];
    let items = service::config_items(Some(&format!("{home}/.claude")), &discovered, None, home);
    let titles: Vec<_> = items.iter().map(|i| i.title.as_str()).collect();
    assert_eq!(titles, ["~/.claude", "~/.claude-agro"]);
    assert_eq!(items[0].value, None, "o padrão grava vazio");
    assert_eq!(items[1].value.as_deref(), Some("/Users/eu/.claude-agro"));
}

#[test]
fn a_atual_que_sumiu_da_lista_fica() {
    let items = service::config_items(Some("/h/.claude"), &[], Some("/outra/.claude-x"), "/h");
    let values: Vec<_> = items.iter().map(|i| i.value.as_deref()).collect();
    assert_eq!(values, [None, Some("/outra/.claude-x")]);
    // A atual que é o padrão, ou que já está descoberta, não duplica.
    assert_eq!(
        service::config_items(Some("/h/.claude"), &[], Some("/h/.claude"), "/h").len(),
        1
    );
    let found = vec!["/h/.a".to_owned()];
    assert_eq!(
        service::config_items(None, &found, Some("/h/.a"), "/h").len(),
        2
    );
}

#[test]
fn sem_perfil_o_padrao_tem_nome_proprio() {
    let items = service::config_items(None, &[], None, "/h");
    assert_eq!(
        items,
        [service::ConfigItem {
            title: "padrão da CLI".into(),
            value: None
        }]
    );
}

// ── ShellCommandTests: shell guarda o comando dele no componente; agente não ──

#[test]
fn o_comando_do_shell_vai_e_volta_e_instancia() {
    let mut shell = NodeTemplate::new("dev", NodeKind::Shell);
    shell.command = some("npm run dev");
    let decoded: NodeTemplate =
        serde_json::from_str(&serde_json::to_string(&shell).unwrap()).unwrap();
    assert_eq!(decoded.command.as_deref(), Some("npm run dev"));
    assert_eq!(
        service::instantiate(&decoded, "dev").cmd.as_deref(),
        Some("npm run dev")
    );
}

#[test]
fn capturar_guarda_o_comando_do_shell() {
    let mut n = NodeConfig::new(NodeKind::Shell, "dev");
    n.cmd = some("npm run dev");
    assert_eq!(
        service::capture(&n, "dev").command.as_deref(),
        Some("npm run dev")
    );
    // Agente não tem `command`: o `cmd` dele é do CLI e mora no mapa.
    let mut agent = NodeConfig::new(NodeKind::Agent, "a");
    agent.agent = some("claude");
    agent.cmd = some("claude --x");
    let captured = service::capture(&agent, "a");
    assert_eq!(captured.command, None);
    assert_eq!(
        captured.resolved(Some("claude")).cmd.as_deref(),
        Some("claude --x")
    );
}

#[test]
fn cmd_legado_de_agente_na_raiz_migra_e_nao_vira_command() {
    let c = component(r#"{"name":"a","kind":"agent","agent":"claude","cmd":"claude --x"}"#);
    assert_eq!(c.command, None);
    assert_eq!(
        c.overrides(Some("claude")).cmd.as_deref(),
        Some("claude --x")
    );
}

// ── Criar, editar e remover nó (main.swift: addNode, place, editNode, remove) ──

mod edit_tests {
    use super::*;
    use crate::features::edge::EdgeConfig;
    use crate::features::node::edit::*;
    use crate::features::workbench::model::WorkbenchConfig;

    fn bench(ids: &[&str]) -> WorkbenchConfig {
        WorkbenchConfig::new(
            "deck",
            "/t",
            ids.iter()
                .map(|id| NodeConfig::new(NodeKind::Shell, *id))
                .collect(),
        )
    }

    #[test]
    fn id_livre_sh_sh_2_sh_3() {
        assert_eq!(next_id("sh", &bench(&[])), "sh");
        assert_eq!(next_id("sh", &bench(&["sh"])), "sh-2");
        assert_eq!(next_id("sh", &bench(&["sh", "sh-2", "web"])), "sh-3");
        assert_eq!(next_id("sh", &bench(&["sh", "sh-3"])), "sh-2");
    }

    #[test]
    fn no_novo_por_tipo() {
        let config = bench(&["sh"]);
        let shell = new_node(NodeKind::Shell, NewNode::default(), &config);
        assert_eq!((shell.kind, shell.id.as_str()), (NodeKind::Shell, "sh-2"));
        let web = new_node(NodeKind::Web, NewNode::default(), &config);
        assert_eq!(web.id, "web");
        assert_eq!(web.url.as_deref(), Some("https://www.google.com"));
        assert_eq!(web.profile.as_deref(), Some("pessoal"));
        let queue = new_node(NodeKind::Queue, NewNode::default(), &config);
        assert_eq!(queue.id, "fila");
        let spec = NewNode {
            agent: some("claude"),
            cwd: some("api"),
            cmd: some(""),
            url: some("http://x"),
            frame: Some(Frame {
                x: 1.4,
                y: 2.6,
                w: 300.0,
                h: 200.0,
            }),
        };
        let agent = new_node(NodeKind::Agent, spec.clone(), &config);
        assert_eq!(agent.id, "claude");
        assert_eq!(agent.agent.as_deref(), Some("claude"));
        assert_eq!(agent.cwd.as_deref(), Some("api"));
        assert_eq!(agent.cmd, None, "vazio é padrão");
        assert_eq!(agent.url, None, "só web tem url");
        assert_eq!(
            agent.frame(),
            Some(Frame {
                x: 1.0,
                y: 3.0,
                w: 300.0,
                h: 200.0
            })
        );
        // Agente sem CLI escolhido ainda é `sh`; shell nunca leva agente.
        assert_eq!(
            new_node(NodeKind::Agent, NewNode::default(), &config).id,
            "sh-2"
        );
        assert_eq!(new_node(NodeKind::Shell, spec, &config).agent, None);
    }

    fn agent_node() -> NodeConfig {
        let mut n = NodeConfig::new(NodeKind::Agent, "dev");
        n.agent = some("claude");
        n.model = some("opus");
        n.prompt = some("papel");
        n.cwd = some("src");
        n
    }

    #[test]
    fn campo_ausente_nao_mexe_null_volta_ao_padrao_e_vazio_tambem() {
        let current = agent_node();
        let (same, restart) = apply_patch(&current, &NodePatch::default());
        assert_eq!(same, current);
        assert!(!restart);

        let (cleared, restart) = apply_patch(
            &current,
            &NodePatch {
                model: Some(None),
                cwd: Some(some("")),
                ..NodePatch::default()
            },
        );
        assert_eq!((cleared.model, cleared.cwd), (None, None));
        assert!(restart, "modelo e pasta mudam o processo");

        let (set, restart) = apply_patch(
            &current,
            &NodePatch {
                effort: Some(some("high")),
                ..NodePatch::default()
            },
        );
        assert_eq!(set.effort.as_deref(), Some("high"));
        assert!(restart);
    }

    #[test]
    fn ultracode_nao_reinicia_como_no_swift_e_maestro_reinicia() {
        let current = agent_node();
        let (u, restart) = apply_patch(
            &current,
            &NodePatch {
                ultracode: Some(true),
                ..NodePatch::default()
            },
        );
        assert_eq!(u.ultracode, Some(true));
        assert!(!restart);
        let (off, _) = apply_patch(
            &u,
            &NodePatch {
                ultracode: Some(false),
                ..NodePatch::default()
            },
        );
        assert_eq!(off.ultracode, None, "desligado não grava `false`");

        let (m, restart) = apply_patch(
            &current,
            &NodePatch {
                maestro: Some(true),
                ..NodePatch::default()
            },
        );
        assert!(
            m.is_maestro() && restart,
            "o maestro tem seção própria no system prompt"
        );
        // Em shell o maestro não vale, e então nada muda no processo.
        let (sh, restart) = apply_patch(
            &NodeConfig::new(NodeKind::Shell, "sh"),
            &NodePatch {
                maestro: Some(true),
                ..NodePatch::default()
            },
        );
        assert!(!sh.is_maestro() && !restart);
    }

    #[test]
    fn o_papel_vai_para_onde_o_efetivo_mora() {
        let mut current = agent_node();
        current.by_agent = Some(BTreeMap::from([(
            "claude".to_owned(),
            over(|o| o.prompt = some("do claude")),
        )]));
        let (updated, restart) = apply_patch(
            &current,
            &NodePatch {
                role: Some(some("novo")),
                ..NodePatch::default()
            },
        );
        assert_eq!(updated.effective_prompt(), Some("novo"));
        assert_eq!(
            updated.prompt.as_deref(),
            Some("papel"),
            "o geral fica de pé"
        );
        assert!(restart);

        // Sem exceção do CLI, vai para o geral; `null` apaga o efetivo.
        let (plain, _) = apply_patch(
            &agent_node(),
            &NodePatch {
                role: Some(some("x")),
                ..NodePatch::default()
            },
        );
        assert_eq!(plain.prompt.as_deref(), Some("x"));
        let (gone, restart) = apply_patch(
            &updated,
            &NodePatch {
                role: Some(None),
                ..NodePatch::default()
            },
        );
        assert_eq!(gone.effective_prompt(), None);
        assert!(restart);

        let (rules, restart) = apply_patch(
            &agent_node(),
            &NodePatch {
                rules: Some(some("sem commit")),
                ..NodePatch::default()
            },
        );
        assert_eq!(rules.effective_rules(), Some("sem commit"));
        assert!(restart);
    }

    #[test]
    fn remover_o_no_leva_as_ligacoes_dele() {
        let mut config = bench(&["a", "b", "c"]);
        config.edges = Some(vec![
            EdgeConfig::new("a", "b", Some(2)),
            EdgeConfig::new("b", "a", Some(2)),
            EdgeConfig::new("b", "c", None),
            EdgeConfig::new("c", "a", None),
        ]);
        let removed = remove_node(&mut config, "a").unwrap();
        assert_eq!(removed.edges, 3);
        assert_eq!(
            config
                .nodes
                .iter()
                .map(|n| n.id.as_str())
                .collect::<Vec<_>>(),
            ["b", "c"]
        );
        assert_eq!(config.edge_list().len(), 1);
        assert_eq!(config.edge_list()[0].from, "b");
        assert_eq!(remove_node(&mut config, "a"), None, "já saiu");
        // Sem ligação nenhuma, `edges` continua como estava.
        let mut lone = bench(&["x"]);
        assert_eq!(remove_node(&mut lone, "x").unwrap().edges, 0);
        assert_eq!(lone.edges, None);
    }
}
