//! Porte de `MaestroPlanTests`, `MaestroLinksLayoutTests`,
//! `MaestroControllerTests` e `MaestroPermissionsTests`.

use std::cell::RefCell;
use std::collections::{BTreeMap, HashSet};
use std::time::{Duration, SystemTime};

use serde_json::{Value, json};

use super::controller::{self, MaestroEffect, MaestroWiring};
use super::guide;
use super::layout::{self, AGENT, GAP, LINKED_GAP_X, SHELL};
use super::links;
use super::permissions;
use super::plan::{MaestroPlan, PlanField};
use super::planner::{self, MaestroContext, MaestroOutcome};
use crate::features::activity::model::Activity;
use crate::features::agent::claude::profile::claude_code;
use crate::features::agent::model::AgentProfile;
use crate::features::agent::model_catalog::{CatalogModel, ModelCatalog};
use crate::features::edge::model::EdgeConfig;
use crate::features::node::model::{Frame, NodeConfig, NodeKind, Overrides};
use crate::features::permission::model::{PermissionAnswer, PermissionAsk};
use crate::features::permission::service::PermissionDesk;
use crate::features::workbench::model::WorkbenchConfig;

const HOME: &str = "/Users/teste";

fn parse(json: &str) -> Result<MaestroPlan, String> {
    MaestroPlan::parse(json.as_bytes())
}

fn model(
    id: &str,
    family: &str,
    label: &str,
    efforts: &[&str],
    auto: Option<&str>,
) -> CatalogModel {
    CatalogModel {
        efforts: efforts.iter().map(|e| (*e).to_owned()).collect(),
        default_effort: auto.map(str::to_owned),
        ..CatalogModel::new(id, family, label)
    }
}

fn catalog() -> ModelCatalog {
    ModelCatalog::new(
        vec![
            model(
                "claude-opus-5-5",
                "opus",
                "Opus 5.5",
                &["low", "medium", "high", "xhigh", "max"],
                Some("high"),
            ),
            model(
                "claude-sonnet-5-5",
                "sonnet",
                "Sonnet 5.5",
                &["low", "medium", "high"],
                Some("medium"),
            ),
            model("claude-haiku-4-5", "haiku", "Haiku 4.5", &[], None),
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

fn context(
    busy: &[&str],
    background: &[&str],
    missing: &[&'static str],
) -> MaestroContext<'static> {
    let missing: Vec<&'static str> = missing.to_vec();
    let mut c = MaestroContext::new("maestro", profiles(), HOME);
    c.catalog =
        Box::new(|p| (p.command.first().map(String::as_str) == Some("claude")).then(catalog));
    c.working = busy.iter().map(|s| (*s).to_owned()).collect::<HashSet<_>>();
    c.background = background
        .iter()
        .map(|s| (*s).to_owned())
        .collect::<HashSet<_>>();
    c.directory_exists = Box::new(move |path| !missing.iter().any(|m| path.ends_with(m)));
    c.suggested_config = Box::new(|cli| (cli == "claude").then(|| "~/.claude-agro".to_owned()));
    c.known_configs = Box::new(|_| vec!["~/.claude".to_owned(), "~/.claude-agro".to_owned()]);
    c
}

fn agent(id: &str) -> NodeConfig {
    let mut n = NodeConfig::new(NodeKind::Agent, id);
    n.agent = Some("claude".into());
    n
}

fn bench() -> WorkbenchConfig {
    let mut maestro = agent("maestro");
    maestro.maestro = Some(true);
    let mut revisor = agent("revisor");
    revisor.model = Some("sonnet".into());
    revisor.prompt = Some("Revise.".into());
    revisor.conversation_id = Some("conv-revisor".into());
    revisor.conversation_started = Some(true);
    let shell = NodeConfig::new(NodeKind::Shell, "sh");
    let mut b = WorkbenchConfig::new("deck", "/tmp/deck", vec![maestro, revisor, shell]);
    b.edges = Some(vec![
        EdgeConfig::with_default_limit("maestro", "revisor"),
        EdgeConfig::with_default_limit("revisor", "maestro"),
    ]);
    b
}

fn run_on(json: &str, base: &WorkbenchConfig, c: &MaestroContext) -> MaestroOutcome {
    let plan = parse(json).unwrap_or_else(|e| panic!("plano não leu: {json} — {e}"));
    planner::plan(&plan, base, c)
}

fn run(json: &str) -> MaestroOutcome {
    run_on(json, &bench(), &context(&[], &[], &[]))
}

fn has(out: &MaestroOutcome, text: &str) -> bool {
    out.errors.iter().any(|e| e.contains(text))
}

fn find<'a>(out: &'a MaestroOutcome, id: &str) -> Option<&'a NodeConfig> {
    out.next.nodes.iter().find(|n| n.id == id)
}

// MARK: - Leitura

#[test]
fn absent_null_and_value_are_three_different_things() {
    let plan = parse(r#"{"nodes":[{"id":"a","model":null,"effort":"high"}]}"#).unwrap();
    assert_eq!(plan.nodes[0].model, PlanField::Clear);
    assert_eq!(plan.nodes[0].effort, PlanField::Set("high".into()));
    assert_eq!(plan.nodes[0].role, PlanField::Keep);
}

#[test]
fn unknown_key_is_an_error_naming_the_field() {
    let error = parse(r#"{"nodes":[{"id":"a","modle":"opus"}]}"#).unwrap_err();
    assert!(error.contains("'modle'"), "{error}");
    assert!(error.contains("nó 'a'"), "{error}");
}

#[test]
fn unknown_top_level_key_is_an_error() {
    let error = parse(r#"{"node":[]}"#).unwrap_err();
    assert!(error.contains("'node'"), "{error}");
    assert!(
        error.starts_with("plano: campo(s) desconhecido(s) 'node' — aceitos: rules, nodes"),
        "{error}"
    );
}

#[test]
fn broken_json_says_so() {
    let error = parse("{nodes: [").unwrap_err();
    assert!(error.contains("JSON inválido"), "{error}");
}

#[test]
fn empty_body_is_an_error() {
    assert_eq!(
        parse("").unwrap_err(),
        "plano vazio — mande o JSON no stdin"
    );
}

#[test]
fn missing_and_null_say_where() {
    assert_eq!(
        parse(r#"{"nodes":[{"model":"x"}]}"#).unwrap_err(),
        "falta 'id' em nodes[0]"
    );
    assert_eq!(
        parse(r#"{"edges":[{"from":"a","to":null}]}"#).unwrap_err(),
        "valor nulo onde não pode em edges[0].to"
    );
    assert_eq!(
        parse(r#"{"nodes":[null]}"#).unwrap_err(),
        "valor nulo onde não pode em nodes[0]"
    );
    assert_eq!(parse("null").unwrap_err(), "valor nulo onde não pode");
    assert!(
        parse(r#"{"nodes":[{"id":"a","ultracode":"sim"}]}"#)
            .unwrap_err()
            .starts_with("tipo errado em nodes[0].ultracode")
    );
}

// MARK: - Criar

#[test]
fn new_agent_gets_defaults_and_no_drawn_edge() {
    let out = run(r#"{"nodes":[{"id":"front","model":"opus","effort":"xhigh","role":"Front."}]}"#);
    assert_eq!(out.errors, Vec::<String>::new());
    assert_eq!(out.created, ["front"]);
    let front = find(&out, "front").unwrap();
    assert_eq!(front.kind, NodeKind::Agent);
    assert_eq!(
        front.agent.as_deref(),
        Some("claude"),
        "sem cli, o Claude Code"
    );
    assert_eq!(front.config.as_deref(), Some("~/.claude-agro"));
    assert_eq!(front.prompt.as_deref(), Some("Front."));
    assert_eq!(front.maestro, None, "o plano não faz maestro");
    assert_eq!(front.component.as_deref(), Some("maestro"));
    assert!(
        !out.next
            .edge_list()
            .iter()
            .any(|e| e.from == "front" || e.to == "front")
    );
    assert!(!out.edges_changed);
    assert!(out.relaid, "time novo rearruma o canvas");
    assert!(front.frame().is_some());
}

#[test]
fn plan_can_still_draw_a_maestro_edge_with_its_own_limit() {
    let out = run(
        r#"{"nodes":[{"id":"front"}],"edges":[{"from":"maestro","to":"front","both":true,"maxSends":6}]}"#,
    );
    assert_eq!(out.errors, Vec::<String>::new());
    let limits: Vec<_> = out
        .next
        .edge_list()
        .iter()
        .filter(|e| e.from == "front" || e.to == "front")
        .map(|e| e.max_sends)
        .collect();
    assert_eq!(limits, [Some(6), Some(6)]);
}

#[test]
fn shell_node_rejects_agent_fields() {
    let ok = run(r#"{"nodes":[{"id":"dev","kind":"shell"}]}"#);
    assert_eq!(ok.errors, Vec::<String>::new());
    assert_eq!(
        ok.next.nodes.last().unwrap().cmd,
        None,
        "sem cmd, zsh de login"
    );
    assert!(!ok.next.edge_list().iter().any(|e| e.from == "dev"));
    let bad = run(r#"{"nodes":[{"id":"dev","kind":"shell","model":"opus"}]}"#);
    assert!(has(&bad, "'model' é de agente"), "{:?}", bad.errors);
}

#[test]
fn shell_gets_command_and_one_way_link() {
    let out = run(r#"{"nodes":[{"id":"dev","kind":"shell","cmd":"npm run dev","cwd":"web"}]}"#);
    assert_eq!(out.errors, Vec::<String>::new());
    assert_eq!(
        find(&out, "dev").unwrap().cmd.as_deref(),
        Some("npm run dev")
    );
    let effective = links::effective(&out.next);
    assert!(effective.contains(&EdgeConfig::new("maestro", "dev", None)));
    assert!(
        !effective.contains(&EdgeConfig::new("dev", "maestro", None)),
        "shell não responde"
    );
    let agent_cmd = run(r#"{"nodes":[{"id":"x","cmd":"ls"}]}"#);
    assert!(
        has(&agent_cmd, "'cmd' é de shell"),
        "{:?}",
        agent_cmd.errors
    );
}

#[test]
fn changing_a_shell_command_restarts_it() {
    let out = run(r#"{"nodes":[{"id":"sh","cmd":"npm test -- --watch"}]}"#);
    assert_eq!(out.errors, Vec::<String>::new());
    assert_eq!(out.restarted, ["sh"]);
}

#[test]
fn config_must_be_one_the_cli_knows() {
    let out = run(r#"{"nodes":[{"id":"x","config":"/tmp/settings-aberto"}]}"#);
    assert!(
        has(&out, "não está entre as de Claude Code"),
        "{:?}",
        out.errors
    );
    assert_eq!(
        run(r#"{"nodes":[{"id":"x","config":"~/.claude"}]}"#).errors,
        Vec::<String>::new()
    );
}

#[test]
fn id_must_be_a_slug() {
    let out = run(r#"{"nodes":[{"id":"Front End"}]}"#);
    assert!(has(&out, "front-end"), "{:?}", out.errors);
}

// MARK: - Catálogo

#[test]
fn unknown_model_is_refused() {
    let out = run(r#"{"nodes":[{"id":"x","model":"gpt-9"}]}"#);
    assert!(has(&out, "modelo 'gpt-9'"), "{:?}", out.errors);
}

#[test]
fn effort_must_belong_to_the_chosen_model() {
    let out = run(r#"{"nodes":[{"id":"x","model":"sonnet","effort":"max"}]}"#);
    assert!(
        has(&out, "Sonnet 5.5 não tem esforço 'max'"),
        "{:?}",
        out.errors
    );
    let none = run(r#"{"nodes":[{"id":"x","model":"haiku","effort":"low"}]}"#);
    assert!(has(&none, "não tem nível de esforço"), "{:?}", none.errors);
    assert_eq!(
        run(r#"{"nodes":[{"id":"x","model":"opus","effort":"max"}]}"#).errors,
        Vec::<String>::new()
    );
    assert!(!has(
        &run(r#"{"nodes":[{"id":"revisor","effort":"high"}]}"#),
        "esforço"
    ));
}

#[test]
fn cli_that_does_not_take_model_says_so() {
    let out = run(r#"{"nodes":[{"id":"x","cli":"opencode","model":"opus"}]}"#);
    assert!(has(&out, "não aceita escolher modelo"), "{:?}", out.errors);
}

#[test]
fn unknown_cli_lists_the_known_ones() {
    let out = run(r#"{"nodes":[{"id":"x","cli":"cursor"}]}"#);
    assert!(has(&out, "claude, opencode"), "{:?}", out.errors);
}

#[test]
fn missing_folder_is_refused() {
    let out = run_on(
        r#"{"nodes":[{"id":"x","cwd":"web"}]}"#,
        &bench(),
        &context(&[], &[], &["/web"]),
    );
    assert!(has(&out, "pasta 'web' não existe"), "{:?}", out.errors);
}

// MARK: - Atualizar

#[test]
fn update_keeps_what_is_absent_and_the_conversation() {
    let out = run(r#"{"nodes":[{"id":"revisor","effort":"high"}]}"#);
    assert_eq!(out.errors, Vec::<String>::new());
    let revisor = find(&out, "revisor").unwrap();
    assert_eq!(revisor.model.as_deref(), Some("sonnet"));
    assert_eq!(revisor.effort.as_deref(), Some("high"));
    assert_eq!(revisor.prompt.as_deref(), Some("Revise."));
    assert_eq!(revisor.conversation_id.as_deref(), Some("conv-revisor"));
    assert_eq!(out.restarted, ["revisor"]);
}

#[test]
fn null_goes_back_to_the_default() {
    let out = run(r#"{"nodes":[{"id":"revisor","model":null}]}"#);
    assert_eq!(find(&out, "revisor").unwrap().model, None);
}

#[test]
fn switching_cli_drops_the_conversation() {
    let out = run(r#"{"nodes":[{"id":"revisor","cli":"opencode","model":null}]}"#);
    assert_eq!(out.errors, Vec::<String>::new());
    let revisor = find(&out, "revisor").unwrap();
    assert_eq!(revisor.agent.as_deref(), Some("opencode"));
    assert_eq!(revisor.conversation_id, None);
}

#[test]
fn role_written_by_the_plan_beats_the_cli_override() {
    let mut base = bench();
    base.nodes[1].by_agent = Some(BTreeMap::from([(
        "claude".to_owned(),
        Overrides {
            prompt: Some("Papel antigo do Claude.".into()),
            ..Overrides::default()
        },
    )]));
    let out = run_on(
        r#"{"nodes":[{"id":"revisor","role":"Novo."}]}"#,
        &base,
        &context(&[], &[], &[]),
    );
    assert_eq!(out.next.nodes[1].effective_prompt(), Some("Novo."));
}

#[test]
fn same_values_do_not_restart() {
    let out = run(r#"{"nodes":[{"id":"revisor","model":"sonnet"}]}"#);
    assert!(out.restarted.is_empty());
    assert!(!out.changed());
}

#[test]
fn changing_folder_starts_a_fresh_conversation() {
    let out = run(r#"{"nodes":[{"id":"revisor","cwd":"api"}]}"#);
    assert_eq!(out.errors, Vec::<String>::new());
    assert_eq!(find(&out, "revisor").unwrap().conversation_id, None);
    assert_eq!(out.fresh_conversation, ["revisor"]);
}

#[test]
fn only_what_changed_is_validated() {
    let mut base = bench();
    base.nodes[1].model = Some("claude-3-opus-legado".into());
    let out = run_on(
        r#"{"nodes":[{"id":"revisor","role":"Outro."}]}"#,
        &base,
        &context(&[], &[], &[]),
    );
    assert_eq!(out.errors, Vec::<String>::new());
}

#[test]
fn other_maestro_and_non_terminal_nodes_are_off_limits() {
    let mut base = bench();
    base.nodes[1].maestro = Some(true);
    base.nodes.push(NodeConfig::new(NodeKind::Web, "docs"));
    for json in [
        r#"{"nodes":[{"id":"revisor","role":"x"}]}"#,
        r#"{"remove":["revisor"]}"#,
        r#"{"nodes":[{"id":"docs","role":"x"}]}"#,
    ] {
        assert!(
            !run_on(json, &base, &context(&[], &[], &[]))
                .errors
                .is_empty(),
            "{json}"
        );
    }
}

#[test]
fn chain_guards_have_a_ceiling() {
    assert!(
        !run(r#"{"edges":[{"from":"maestro","to":"revisor","maxSends":null}]}"#)
            .errors
            .is_empty()
    );
    assert!(
        !run(r#"{"edges":[{"from":"maestro","to":"revisor","maxSends":50}]}"#)
            .errors
            .is_empty()
    );
    assert_eq!(
        run(r#"{"edges":[{"from":"maestro","to":"revisor","maxSends":10}]}"#).errors,
        Vec::<String>::new()
    );
}

#[test]
fn unlink_of_a_removed_node_is_not_an_error() {
    assert_eq!(
        run(r#"{"remove":["revisor"],"unlink":[{"from":"maestro","to":"revisor","both":true}]}"#)
            .errors,
        Vec::<String>::new()
    );
}

#[test]
fn bench_only_keys_are_ignored_but_maestro_is_refused() {
    assert!(
        parse(r#"{"nodes":[{"id":"revisor","state":"idle","you":false,"maestro":false}]}"#).is_ok()
    );
    let error = parse(r#"{"nodes":[{"id":"revisor","maestro":true}]}"#).unwrap_err();
    assert!(error.contains("só o usuário"), "{error}");
}

#[test]
fn kind_does_not_change() {
    let out = run(r#"{"nodes":[{"id":"sh","kind":"agent"}]}"#);
    assert!(has(&out, "não vira agent"), "{:?}", out.errors);
}

#[test]
fn maestro_cannot_touch_itself() {
    assert!(has(
        &run(r#"{"nodes":[{"id":"maestro","model":"haiku"}]}"#),
        "é você"
    ));
    assert!(has(&run(r#"{"remove":["maestro"]}"#), "é você"));
}

#[test]
fn busy_node_is_not_restarted_nor_removed() {
    let busy = context(&["revisor"], &[], &[]);
    let restart = run_on(
        r#"{"nodes":[{"id":"revisor","effort":"low"}]}"#,
        &bench(),
        &busy,
    );
    assert!(
        has(&restart, "trabalhando agora: revisor"),
        "{:?}",
        restart.errors
    );
    assert!(has(
        &run_on(r#"{"remove":["revisor"]}"#, &bench(), &busy),
        "trabalhando agora"
    ));
    assert_eq!(
        run_on(
            r#"{"edges":[{"from":"maestro","to":"revisor","maxSends":5}]}"#,
            &bench(),
            &busy
        )
        .errors,
        Vec::<String>::new()
    );
}

#[test]
fn background_node_needs_force_but_working_never_passes() {
    let behind = context(&[], &["revisor"], &[]);
    let refused = run_on(r#"{"remove":["revisor"]}"#, &bench(), &behind);
    assert!(
        has(&refused, "em segundo plano: revisor"),
        "{:?}",
        refused.errors
    );
    assert!(has(&refused, "\"force\": true"));
    assert_eq!(
        run_on(r#"{"remove":["revisor"],"force":true}"#, &bench(), &behind).errors,
        Vec::<String>::new()
    );
    let busy = context(&["revisor"], &[], &[]);
    assert!(
        !run_on(r#"{"remove":["revisor"],"force":true}"#, &bench(), &busy)
            .errors
            .is_empty()
    );
}

#[test]
fn bench_rules_restart_the_other_agents_but_not_the_maestro() {
    let out = run(r#"{"rules":"Peça antes de commitar."}"#);
    assert_eq!(out.errors, Vec::<String>::new());
    assert_eq!(out.next.rules.as_deref(), Some("Peça antes de commitar."));
    assert_eq!(out.restarted, ["revisor"]);
    assert!(out.rules_changed);
}

#[test]
fn removing_takes_its_edges_along() {
    let out = run(r#"{"remove":["revisor"]}"#);
    assert_eq!(out.removed, ["revisor"]);
    assert!(find(&out, "revisor").is_none());
    assert!(out.next.edge_list().is_empty());
}

#[test]
fn edge_to_missing_node_is_refused() {
    let out = run(r#"{"edges":[{"from":"maestro","to":"fantasma"}]}"#);
    assert!(has(&out, "'fantasma' não existe"), "{:?}", out.errors);
}

#[test]
fn unlink_both() {
    let out = run(r#"{"unlink":[{"from":"maestro","to":"revisor","both":true}]}"#);
    assert_eq!(out.errors, Vec::<String>::new());
    assert!(out.next.edge_list().is_empty());
}

#[test]
fn errors_accumulate_instead_of_stopping_at_the_first() {
    let out = run(
        r#"{"nodes":[{"id":"a","model":"gpt-9"},{"id":"b","cli":"cursor"}],"edges":[{"from":"maestro","to":"revisor","maxSends":50}]}"#,
    );
    assert!(out.errors.len() >= 3, "{:?}", out.errors);
}

#[test]
fn layout_only_when_the_team_changes_unless_asked() {
    assert!(!run(r#"{"nodes":[{"id":"revisor","effort":"low"}]}"#).relaid);
    assert!(!run(r#"{"nodes":[{"id":"front"}],"layout":false}"#).relaid);
    assert!(
        run(r#"{"layout":true}"#).relaid,
        "layout sozinho é um plano"
    );
    assert!(run(r#"{"remove":["sh"]}"#).relaid);
}

#[test]
fn summary_reads_like_the_trace() {
    let out = run(r#"{"nodes":[{"id":"front"},{"id":"revisor","effort":"low"}],"remove":["sh"]}"#);
    assert_eq!(out.errors, Vec::<String>::new());
    assert!(
        out.summary().starts_with("+front ~revisor −sh"),
        "{}",
        out.summary()
    );
}

// MARK: - MaestroLinksLayoutTests

fn node(id: &str, kind: NodeKind, maestro: bool) -> NodeConfig {
    let mut n = NodeConfig::new(kind, id);
    if kind == NodeKind::Agent {
        n.agent = Some("claude".into());
    }
    n.maestro = maestro.then_some(true);
    n
}

fn e(from: &str, to: &str) -> EdgeConfig {
    EdgeConfig::with_default_limit(from, to)
}

fn intersects(a: &Frame, b: &Frame) -> bool {
    a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}

#[test]
fn maestro_reaches_everyone_and_agents_reach_back() {
    let b = WorkbenchConfig::new(
        "deck",
        "/tmp",
        vec![
            node("m", NodeKind::Agent, true),
            node("a", NodeKind::Agent, false),
            node("dev", NodeKind::Shell, false),
            node("docs", NodeKind::Web, false),
        ],
    );
    let edges = links::effective(&b);
    assert!(edges.contains(&e("m", "a")));
    assert!(edges.contains(&e("a", "m")), "é por onde chega a resposta");
    assert!(edges.contains(&e("m", "dev")));
    assert!(!edges.contains(&e("dev", "m")), "shell não responde");
    assert!(!edges.iter().any(|x| x.to == "docs"), "web não é alvo");
    assert!(edges.iter().all(|x| x.max_sends.is_none()));
    assert!(b.edge_list().is_empty());
}

#[test]
fn drawn_edge_wins_over_the_implicit_one() {
    let mut b = WorkbenchConfig::new(
        "deck",
        "/tmp",
        vec![
            node("m", NodeKind::Agent, true),
            node("a", NodeKind::Agent, false),
        ],
    );
    b.edges = Some(vec![EdgeConfig::new("m", "a", Some(3))]);
    let limits: Vec<_> = links::effective(&b)
        .iter()
        .filter(|x| **x == e("m", "a"))
        .map(|x| x.max_sends)
        .collect();
    assert_eq!(limits, [Some(3)]);
}

#[test]
fn without_maestro_nothing_is_added() {
    let b = WorkbenchConfig::new(
        "deck",
        "/tmp",
        vec![
            node("a", NodeKind::Agent, false),
            node("b", NodeKind::Agent, false),
        ],
    );
    assert!(links::effective(&b).is_empty());
}

#[test]
fn layout_puts_maestro_left_team_in_grid_shells_below() {
    let nodes = [
        node("m", NodeKind::Agent, true),
        node("a", NodeKind::Agent, false),
        node("b", NodeKind::Agent, false),
        node("c", NodeKind::Agent, false),
        node("dev", NodeKind::Shell, false),
    ];
    let f = layout::frames(&nodes, &[]);
    let (m, a, b, c, dev) = (f["m"], f["a"], f["b"], f["c"], f["dev"]);
    assert!(m.x + m.w < a.x, "maestro à esquerda do time");
    assert_eq!(a.y, b.y, "dois por linha com três agentes");
    assert!(c.y > a.y + a.h);
    assert_eq!(
        m.y + m.h,
        c.y + c.h,
        "a coluna do maestro tem a altura do time"
    );
    assert!(dev.y > m.y + m.h, "shell na faixa de baixo");
    assert_eq!((dev.w, dev.h), SHELL);
    let all: Vec<Frame> = f.values().copied().collect();
    for i in 0..all.len() {
        for j in i + 1..all.len() {
            assert!(!intersects(&all[i], &all[j]), "cards não se sobrepõem");
        }
    }
}

#[test]
fn maestro_keeps_its_place_and_the_team_follows_it() {
    let mut m = node("m", NodeKind::Agent, true);
    m.set_frame(Frame {
        x: 300.0,
        y: 900.0,
        w: 500.0,
        h: 600.0,
    });
    let f = layout::frames(
        &[
            m,
            node("a", NodeKind::Agent, false),
            node("b", NodeKind::Agent, false),
        ],
        &[],
    );
    assert_eq!(
        f["m"],
        Frame {
            x: 300.0,
            y: 900.0,
            w: 500.0,
            h: 600.0
        }
    );
    assert!(f["a"].x > 800.0);
    assert_eq!(f["a"].y, 900.0);
}

#[test]
fn linked_agents_get_room_for_the_arrows() {
    let nodes = [
        node("m", NodeKind::Agent, true),
        node("a", NodeKind::Agent, false),
        node("b", NodeKind::Agent, false),
    ];
    let loose = layout::frames(&nodes, &[]);
    let linked = layout::frames(&nodes, &[e("a", "b")]);
    assert_eq!(loose["b"].x - (loose["a"].x + loose["a"].w), GAP);
    assert_eq!(
        linked["b"].x - (linked["a"].x + linked["a"].w),
        LINKED_GAP_X
    );
    let implicit = layout::frames(&nodes, &[e("m", "a")]);
    assert_eq!(implicit["b"].x - (implicit["a"].x + implicit["a"].w), GAP);
}

#[test]
fn plan_does_not_move_the_maestro() {
    let mut m = node("m", NodeKind::Agent, true);
    let place = Frame {
        x: 1200.0,
        y: 80.0,
        w: 720.0,
        h: 460.0,
    };
    m.set_frame(place);
    let b = WorkbenchConfig::new("deck", "/tmp", vec![m]);
    let mut c = MaestroContext::new(
        "m",
        BTreeMap::from([("claude".to_owned(), claude_code())]),
        HOME,
    );
    c.directory_exists = Box::new(|_| true);
    let out = run_on(r#"{"nodes":[{"id":"a"}],"layout":true}"#, &b, &c);
    assert_eq!(out.errors, Vec::<String>::new());
    assert_eq!(find(&out, "m").unwrap().frame(), Some(place));
}

#[test]
fn linked_team_flows_left_to_right_and_centers_the_target() {
    let nodes = [
        node("m", NodeKind::Agent, true),
        node("planejador", NodeKind::Agent, false),
        node("testador", NodeKind::Agent, false),
        node("dev", NodeKind::Agent, false),
    ];
    let edges = [
        e("planejador", "testador"),
        e("testador", "planejador"),
        e("planejador", "dev"),
        e("testador", "dev"),
    ];
    let f = layout::frames(&nodes, &edges);
    let (p, t, d) = (f["planejador"], f["testador"], f["dev"]);
    assert_eq!(p.x, t.x);
    assert!(t.y > p.y + p.h);
    assert!(d.x > p.x + p.w);
    let mid = |f: Frame| f.y + f.h / 2.0;
    assert!((mid(d) - (mid(p) + mid(t)) / 2.0).abs() <= 0.5);
}

#[test]
fn cycle_is_anchored_on_the_target() {
    let nodes = [
        node("planejador", NodeKind::Agent, false),
        node("dev", NodeKind::Agent, false),
        node("testador", NodeKind::Agent, false),
    ];
    let edges = [
        e("planejador", "dev"),
        e("dev", "testador"),
        e("testador", "dev"),
        e("testador", "planejador"),
    ];
    let f = layout::frames(&nodes, &edges);
    let (p, t, d) = (f["planejador"], f["testador"], f["dev"]);
    assert_eq!(p.x, t.x);
    assert!(d.x > p.x + p.w);
    let mid = |f: Frame| f.y + f.h / 2.0;
    assert!((mid(d) - (mid(p) + mid(t)) / 2.0).abs() <= 0.5);
}

#[test]
fn only_two_way_pairs_stack_in_one_column() {
    let nodes = [
        node("a", NodeKind::Agent, false),
        node("b", NodeKind::Agent, false),
    ];
    let f = layout::frames(&nodes, &[e("a", "b"), e("b", "a")]);
    assert_eq!(f["a"].x, f["b"].x);
    assert!(f["b"].y > f["a"].y + f["a"].h);
}

#[test]
fn chain_of_one_way_arrows_makes_columns() {
    let nodes = [
        node("a", NodeKind::Agent, false),
        node("b", NodeKind::Agent, false),
        node("c", NodeKind::Agent, false),
    ];
    let f = layout::frames(&nodes, &[e("a", "b"), e("b", "c")]);
    assert!(f["a"].x + f["a"].w < f["b"].x);
    assert!(f["b"].x + f["b"].w < f["c"].x);
    assert!((f["a"].y - f["c"].y).abs() <= 0.5, "pipeline em linha reta");
}

#[test]
fn one_way_cycle_does_not_hang() {
    let nodes = [
        node("a", NodeKind::Agent, false),
        node("b", NodeKind::Agent, false),
        node("c", NodeKind::Agent, false),
    ];
    let f = layout::frames(&nodes, &[e("a", "b"), e("b", "c"), e("c", "a")]);
    assert_eq!(f.len(), 3);
}

#[test]
fn plan_frame_moves_and_resizes_a_card() {
    let mut a = node("a", NodeKind::Agent, false);
    a.set_frame(Frame {
        x: 800.0,
        y: 40.0,
        w: 720.0,
        h: 460.0,
    });
    let b = WorkbenchConfig::new("deck", "/tmp", vec![node("m", NodeKind::Agent, true), a]);
    let mut c = MaestroContext::new(
        "m",
        BTreeMap::from([("claude".to_owned(), claude_code())]),
        HOME,
    );
    c.directory_exists = Box::new(|_| true);
    let moved = run_on(r#"{"nodes":[{"id":"a","frame":{"y":900}}]}"#, &b, &c);
    assert_eq!(moved.errors, Vec::<String>::new());
    assert_eq!(
        moved.next.nodes[1].frame(),
        Some(Frame {
            x: 800.0,
            y: 900.0,
            w: 720.0,
            h: 460.0
        })
    );
    assert!(moved.relaid);
    assert!(moved.restarted.is_empty(), "mover não reinicia");
    assert!(
        !run_on(r#"{"nodes":[{"id":"a","frame":{"x":-5}}]}"#, &b, &c)
            .errors
            .is_empty()
    );
    assert!(
        !run_on(r#"{"nodes":[{"id":"a","frame":{"w":100}}]}"#, &b, &c)
            .errors
            .is_empty()
    );
    assert!(
        !run_on(r#"{"nodes":[{"id":"m","frame":{"x":0}}]}"#, &b, &c)
            .errors
            .is_empty()
    );
    assert!(parse(r#"{"nodes":[{"id":"a","frame":{"left":3}}]}"#).is_err());
}

#[test]
fn negative_size_is_normalized_like_cgrect() {
    let mut a = node("a", NodeKind::Agent, false);
    a.set_frame(Frame {
        x: 800.0,
        y: 40.0,
        w: 720.0,
        h: 460.0,
    });
    let b = WorkbenchConfig::new("deck", "/tmp", vec![node("m", NodeKind::Agent, true), a]);
    let mut c = MaestroContext::new(
        "m",
        BTreeMap::from([("claude".to_owned(), claude_code())]),
        HOME,
    );
    c.directory_exists = Box::new(|_| true);
    let out = run_on(
        r#"{"nodes":[{"id":"a","frame":{"x":1200,"w":-400}}]}"#,
        &b,
        &c,
    );
    assert_eq!(out.errors, Vec::<String>::new());
    assert_eq!(
        out.next.nodes[1].frame(),
        Some(Frame {
            x: 800.0,
            y: 40.0,
            w: 400.0,
            h: 460.0
        })
    );
}

#[test]
fn plan_with_layout_is_not_empty() {
    assert!(!parse(r#"{"layout":true}"#).unwrap().is_empty());
}

#[test]
fn guide_example_is_a_valid_plan() {
    let text = guide::TEXT;
    let start = text.find("egeon plan <<'JSON'\n").unwrap() + "egeon plan <<'JSON'\n".len();
    let end = start + text[start..].find("\nJSON").unwrap();
    let plan = parse(&text[start..end]).unwrap();
    let ids: Vec<_> = plan.nodes.iter().map(|n| n.id.as_str()).collect();
    assert_eq!(ids, ["back", "web", "revisor"]);
}

#[test]
fn agent_size_is_the_default_card() {
    assert_eq!(AGENT, (720.0, 460.0));
}

// MARK: - MaestroControllerTests

struct World {
    bench: RefCell<WorkbenchConfig>,
}

impl MaestroWiring for World {
    fn bench(&self, name: &str) -> Option<WorkbenchConfig> {
        let b = self.bench.borrow();
        (b.name == name).then(|| b.clone())
    }
    fn context(&self, _: &WorkbenchConfig, caller: &str) -> MaestroContext<'_> {
        let mut c = MaestroContext::new(
            caller,
            BTreeMap::from([("claude".to_owned(), claude_code())]),
            HOME,
        );
        c.directory_exists = Box::new(|_| true);
        c
    }
    fn activity(&self, _: &str) -> Option<Activity> {
        Some(Activity::Ready)
    }
    fn profiles(&self) -> BTreeMap<String, AgentProfile> {
        BTreeMap::from([("claude".to_owned(), claude_code())])
    }
    fn catalog(&self, _: &AgentProfile) -> Option<ModelCatalog> {
        None
    }
    fn home(&self) -> String {
        HOME.to_owned()
    }
}

fn world() -> World {
    let mut maestro = agent("maestro");
    maestro.maestro = Some(true);
    World {
        bench: RefCell::new(WorkbenchConfig::new(
            "deck",
            "/tmp",
            vec![maestro, agent("revisor")],
        )),
    }
}

fn names(effects: &[MaestroEffect]) -> Vec<String> {
    effects
        .iter()
        .map(|e| match e {
            MaestroEffect::Commit(_) => "commit".to_owned(),
            MaestroEffect::Spawn { node, .. } => format!("spawn {node}"),
            MaestroEffect::Restart { node, .. } => format!("restart {node}"),
            MaestroEffect::Dispose { node, .. } => format!("dispose {node}"),
            MaestroEffect::RedrawEdges { .. } => "edges".to_owned(),
            MaestroEffect::Arrange { .. } => "arrange".to_owned(),
            MaestroEffect::Persist => "persist".to_owned(),
            MaestroEffect::Trace { address, text } => format!("trace {address}: {text}"),
            MaestroEffect::PermissionAnswered { address } => format!("answered {address}"),
        })
        .collect()
}

#[test]
fn only_a_maestro_may_ask() {
    let w = world();
    assert_eq!(controller::bench(&w, Some("deck/revisor")).status, 403);
    assert_eq!(controller::bench(&w, None).status, 403);
    assert_eq!(controller::models(&w, Some("deck/revisor")).status, 403);
    assert_eq!(
        controller::apply(
            &w,
            br#"{"nodes":[{"id":"x"}]}"#,
            Some("deck/revisor"),
            false
        )
        .status,
        403
    );
    assert_eq!(controller::bench(&w, Some("outra/maestro")).status, 404);
    assert_eq!(controller::bench(&w, Some("deck/maestro")).status, 200);
}

#[test]
fn bench_marks_who_is_asking() {
    let reply = controller::bench(&world(), Some("deck/maestro"));
    let nodes = reply.json["nodes"].as_array().unwrap();
    let by = |id: &str| nodes.iter().find(|n| n["id"] == id).unwrap().clone();
    assert_eq!(by("maestro")["you"], true);
    assert_eq!(by("revisor")["state"], "idle");
    assert_eq!(by("revisor")["cli"], "claude");
    assert_eq!(by("revisor")["model"], Value::Null);
}

#[test]
fn models_list_the_clis() {
    let reply = controller::models(&world(), Some("deck/maestro"));
    assert_eq!(reply.json["clis"][0]["cli"], "claude");
    assert_eq!(reply.json["clis"][0]["acceptsModel"], true);
}

#[test]
fn dry_run_changes_nothing() {
    let reply = controller::apply(
        &world(),
        br#"{"nodes":[{"id":"front"}]}"#,
        Some("deck/maestro"),
        true,
    );
    assert_eq!(reply.status, 200);
    assert_eq!(reply.json["created"], json!(["front"]));
    assert_eq!(reply.json["dry"], true);
    assert!(reply.json["result"]["nodes"].is_array());
    assert!(reply.effects.is_empty());
}

#[test]
fn invalid_plan_changes_nothing_and_lists_errors() {
    let reply = controller::apply(
        &world(),
        br#"{"nodes":[{"id":"front","cli":"cursor"}]}"#,
        Some("deck/maestro"),
        false,
    );
    assert_eq!(reply.status, 422);
    assert!(!reply.json["errors"].as_array().unwrap().is_empty());
    assert!(reply.effects.is_empty());
    let empty = controller::apply(&world(), b"{}", Some("deck/maestro"), false);
    assert_eq!(empty.status, 400);
    assert_eq!(
        controller::apply(&world(), b"{x", Some("deck/maestro"), false).status,
        400
    );
}

#[test]
fn apply_commits_first_then_touches_the_screen_and_leaves_a_trace() {
    let reply = controller::apply(
        &world(),
        br#"{"nodes":[{"id":"front"},{"id":"revisor","effort":"low"}]}"#,
        Some("deck/maestro"),
        false,
    );
    assert_eq!(reply.status, 200, "{}", reply.json);
    assert_eq!(
        names(&reply.effects),
        [
            "commit",
            "restart revisor",
            "spawn front",
            "edges",
            "arrange",
            "persist",
            "trace deck/maestro: maestro aplicou: +front ~revisor · canvas rearrumado"
        ]
    );
    let MaestroEffect::Commit(next) = &reply.effects[0] else {
        panic!("o primeiro efeito é gravar");
    };
    assert!(next.nodes.iter().any(|n| n.id == "front"));
    assert!(
        reply.json["notes"]
            .as_array()
            .is_some_and(|n| !n.is_empty())
    );
}

#[test]
fn plan_that_changes_nothing_does_not_touch_anything() {
    let reply = controller::apply(
        &world(),
        br#"{"nodes":[{"id":"revisor"}]}"#,
        Some("deck/maestro"),
        false,
    );
    assert_eq!(reply.status, 200);
    assert!(reply.effects.is_empty());
}

// MARK: - MaestroPermissionsTests

fn ask(id: &str, from: &str, tool: &str) -> PermissionAsk {
    PermissionAsk {
        id: id.into(),
        address: from.into(),
        tool: tool.into(),
        summary: "rm -rf build".into(),
        detail: Some("limpa o build".into()),
        suggestions: Vec::new(),
        input: serde_json::Map::new(),
        opened_at: SystemTime::UNIX_EPOCH,
    }
}

fn perm_bench() -> WorkbenchConfig {
    let mut maestro = agent("maestro");
    maestro.maestro = Some(true);
    WorkbenchConfig::new("deck", "/tmp", vec![maestro, agent("revisor")])
}

#[test]
fn approver_is_the_maestro_and_never_the_asker() {
    let mut b = perm_bench();
    let open = [
        ask("p1", "deck/revisor", "Bash"),
        ask("p2", "deck/maestro", "Bash"),
        ask("p3", "outra/revisor", "Bash"),
        ask("p4", "deck/revisor", "AskUserQuestion"),
    ];
    assert_eq!(
        permissions::approver(&open[0], &b).map(|n| n.id.as_str()),
        Some("maestro")
    );
    assert!(
        permissions::approver(&open[1], &b).is_none(),
        "o próprio pedido"
    );
    assert!(
        permissions::approver(&open[2], &b).is_none(),
        "outra bancada"
    );
    assert!(
        permissions::approver(&open[3], &b).is_none(),
        "pergunta ao usuário"
    );
    b.nodes[0].maestro = None;
    assert!(
        permissions::approver(&open[0], &b).is_none(),
        "deixou de ser maestro"
    );
}

#[test]
fn notice_is_one_short_line_with_the_commands() {
    assert_eq!(
        permissions::notice(&ask("p1", "deck/revisor", "Bash")),
        "[ED] pedido de permissão de revisor — Bash: rm -rf build (limpa o build) — \
         responda: egeon allow p1 · egeon deny p1"
    );
    let long = PermissionAsk {
        summary: format!("{}\nsegunda linha", "x".repeat(300)),
        detail: None,
        suggestions: vec![json!({"type": "addRules"})],
        ..ask("p9", "deck/revisor", "Bash")
    };
    let notice = permissions::notice(&long);
    assert!(!notice.contains('\n'));
    assert!(notice.chars().count() < 260);
    assert!(notice.ends_with("egeon allow p9 (ou --always) · egeon deny p9"));
}

fn t() -> SystemTime {
    SystemTime::UNIX_EPOCH + Duration::from_secs(10_000)
}

fn open_desk() -> (PermissionDesk, Vec<String>) {
    let mut desk = PermissionDesk::new();
    let ids = [
        ("deck/revisor", "Bash"),
        ("deck/maestro", "Bash"),
        ("outra/revisor", "Bash"),
        ("deck/revisor", "AskUserQuestion"),
    ]
    .iter()
    .map(|(from, tool)| {
        desk.open_ask(
            from,
            &json!({"tool_name": tool, "tool_input": {"command": "rm -rf build"}}),
            t(),
        )
        .unwrap()
        .id
    })
    .collect();
    (desk, ids)
}

#[test]
fn listing_shows_only_the_teams_tool_requests() {
    let w = World {
        bench: RefCell::new(perm_bench()),
    };
    let (mut desk, ids) = open_desk();
    let reply = controller::permissions(&w, Some("deck/maestro"), &mut desk, t());
    let listed: Vec<_> = reply.json["open"]
        .as_array()
        .unwrap()
        .iter()
        .map(|a| a["id"].as_str().unwrap().to_owned())
        .collect();
    assert_eq!(listed, [ids[0].clone()]);
}

#[test]
fn answer_refusals() {
    let w = World {
        bench: RefCell::new(perm_bench()),
    };
    let (mut desk, ids) = open_desk();
    let answer = |id: &str, caller: &str, desk: &mut PermissionDesk| {
        controller::answer_permission(&w, id, PermissionAnswer::Allow, Some(caller), desk, t())
            .status
    };
    assert_eq!(
        answer(&ids[0], "deck/revisor", &mut desk),
        403,
        "quem não é maestro"
    );
    assert_eq!(
        answer(&ids[1], "deck/maestro", &mut desk),
        403,
        "o próprio pedido"
    );
    assert_eq!(
        answer(&ids[2], "deck/maestro", &mut desk),
        403,
        "outra bancada"
    );
    assert_eq!(
        answer(&ids[3], "deck/maestro", &mut desk),
        403,
        "pergunta ao usuário"
    );
    assert_eq!(answer("p7", "deck/maestro", &mut desk), 404);
    w.bench.borrow_mut().nodes[0].maestro = None;
    assert_eq!(
        answer(&ids[0], "deck/maestro", &mut desk),
        403,
        "deixou de ser maestro"
    );
    assert_eq!(
        controller::permissions(&w, Some("deck/maestro"), &mut desk, t()).status,
        403
    );
    assert_eq!(desk.open(t()).len(), 4, "nada respondido");
}

#[test]
fn answer_goes_through_and_is_traced() {
    let w = World {
        bench: RefCell::new(perm_bench()),
    };
    let (mut desk, ids) = open_desk();
    let reply = controller::answer_permission(
        &w,
        &ids[0],
        PermissionAnswer::Deny,
        Some("deck/maestro"),
        &mut desk,
        t(),
    );
    assert_eq!(reply.status, 200);
    assert_eq!(
        names(&reply.effects),
        [
            "answered deck/revisor".to_owned(),
            "trace deck/maestro: maestro negou Bash de revisor: rm -rf build".to_owned()
        ]
    );
    assert_eq!(
        desk.state(&ids[0], t()),
        crate::features::permission::service::PermissionState::Answered(PermissionAnswer::Deny)
    );
    assert_eq!(controller::answered_by("maestro"), "pelo maestro maestro");
    assert_eq!(
        controller::answer_permission(
            &w,
            &ids[0],
            PermissionAnswer::Allow,
            Some("deck/maestro"),
            &mut desk,
            t()
        )
        .status,
        404,
        "respondido uma vez, acabou"
    );
}

#[test]
fn only_the_user_grants_it() {
    use crate::features::node::service::{capture, instantiate};
    // O plano do maestro não dá o poder a ninguém, nem a si mesmo.
    assert!(parse(r#"{"nodes":[{"id":"revisor","approvesPermissions":true}]}"#).is_err());

    // Vem com o maestro, sem caixa à parte: o componente maestro aprova.
    let mut template = capture(&perm_bench().nodes[0], "regente");
    assert!(instantiate(&template, "m").approves_team_permissions());
    template.maestro = None;
    assert!(!instantiate(&template, "m").approves_team_permissions());

    // A chave antiga, de quando era caixa à parte, é só ignorada.
    let old: NodeConfig =
        serde_json::from_str(r#"{"type":"agent","id":"m","maestro":true,"approvesTeam":false}"#)
            .unwrap();
    assert!(old.approves_team_permissions());
}

// MARK: - A rota

impl crate::features::dispatch::Surface for World {
    fn running(&self, _: &str) -> bool {
        true
    }
    fn focused(&self, _: &str) -> bool {
        false
    }
    fn peek(&self, _: &str, _: usize) -> Vec<String> {
        Vec::new()
    }
    fn last_marker(
        &self,
        _: &std::path::Path,
        _: &crate::features::dispatch::marker::MarkerConfig,
    ) -> Option<crate::features::dispatch::marker::LastMarker> {
        None
    }
}

impl crate::features::dispatch::coordination::World for World {
    fn workbench(&self, name: &str) -> Option<WorkbenchConfig> {
        MaestroWiring::bench(self, name)
    }
    fn app_active(&self) -> bool {
        false
    }
    fn notifier_authorized(&self) -> bool {
        false
    }
}

fn route(
    state: &mut crate::features::dispatch::coordination::Coordination,
    w: &World,
    method: &str,
    path: &str,
    query: &[(&str, &str)],
    origin: Option<&str>,
) -> (
    crate::protocol::handler::RouteReply,
    Vec<crate::features::dispatch::coordination::Outward>,
) {
    let req = crate::protocol::handler::RouteRequest {
        method: method.into(),
        target: path.into(),
        path: path.into(),
        query: query
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect(),
        body: Vec::new(),
        origin: origin.map(str::to_owned),
    };
    super::routes::maestro(state, &req, t(), w, w)
}

#[test]
fn the_route_dispatches_by_suffix_and_answers_wake_the_asker() {
    use crate::features::dispatch::coordination::{Coordination, Outward};
    let w = World {
        bench: RefCell::new(perm_bench()),
    };
    let mut state = Coordination::new();
    for id in ["maestro", "revisor"] {
        state.register(format!("deck/{id}"), None, true, t());
    }
    let bench = route(
        &mut state,
        &w,
        "GET",
        "/maestro/bench",
        &[],
        Some("deck/maestro"),
    )
    .0;
    assert_eq!(bench.status, 200);
    assert_eq!(bench.json["workbench"], "deck");
    let wrong = route(
        &mut state,
        &w,
        "GET",
        "/maestro/xyz",
        &[],
        Some("deck/maestro"),
    )
    .0;
    assert_eq!(wrong.status, 404);
    let no_id = route(
        &mut state,
        &w,
        "POST",
        "/maestro/answer",
        &[],
        Some("deck/maestro"),
    )
    .0;
    assert_eq!(
        no_id.json["error"],
        "use ?id=<pedido>&answer=allow|always|deny"
    );
    let stranger = route(&mut state, &w, "GET", "/maestro/bench", &[], None).0;
    assert_eq!(stranger.status, 403);

    let ask = state
        .desk
        .open_ask(
            "deck/revisor",
            &json!({"tool_name": "Bash", "tool_input": {"command": "ls"}}),
            t(),
        )
        .unwrap();
    let (ok, out) = route(
        &mut state,
        &w,
        "POST",
        "/maestro/answer",
        &[("id", &ask.id), ("answer", "allow")],
        Some("deck/maestro"),
    );
    assert_eq!(ok.status, 200);
    assert!(
        out.iter()
            .any(|o| matches!(o, Outward::Maestro(MaestroEffect::Trace { .. })))
    );
}
