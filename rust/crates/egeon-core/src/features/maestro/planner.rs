//! Valida um plano contra a bancada e calcula a bancada seguinte (ADR-066).
//! Porte de `MaestroPlanner.swift`.
//!
//! Não aplica nada: só decide. Quem aplica é o controller, e só quando aqui
//! não sobrou erro — o plano vale inteiro ou não vale.

use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::path::Path;

use super::layout;
use super::plan::{MaestroPlan, PlanField, PlanNode};
use crate::commons::ids::NodeId;
use crate::features::agent::model::AgentProfile;
use crate::features::agent::model_catalog::{CatalogModel, ModelCatalog};
use crate::features::edge::model::EdgeConfig;
use crate::features::node::model::{Frame, NodeConfig, NodeKind, Overrides};
use crate::features::path_text;
use crate::features::workbench::model::WorkbenchConfig;

/// Tetos do que o maestro pode afrouxar: quem tira as guardas de vez é o
/// usuário.
pub const MAX_SENDS_CEILING: i64 = 10;
/// Menor que isto o terminal não mostra uma linha de prompt inteira.
pub const MINIMUM_SIZE: (f64, f64) = (320.0, 200.0);

type Catalog<'a> = Box<dyn Fn(&AgentProfile) -> Option<ModelCatalog> + 'a>;
type Suggest<'a> = Box<dyn Fn(&str) -> Option<String> + 'a>;
type Configs<'a> = Box<dyn Fn(&AgentProfile) -> Vec<String> + 'a>;

/// O que o planejador precisa saber do mundo, entregue por quem chama: a
/// decisão inteira roda em teste, sem app, sem disco e sem pty.
pub struct MaestroContext<'a> {
    /// O nó maestro que aplica — fica fora do plano.
    pub caller: String,
    pub profiles: BTreeMap<String, AgentProfile>,
    pub home: String,
    pub catalog: Catalog<'a>,
    /// Em turno ou parados num pedido de permissão: reiniciar perderia o turno.
    pub working: HashSet<String>,
    /// Em segundo plano — esperando vizinho ou com processo rodando; só com
    /// `force`.
    pub background: HashSet<String>,
    pub directory_exists: Box<dyn Fn(&str) -> bool + 'a>,
    /// A configuração do CLI que o workspace usa por último.
    pub suggested_config: Suggest<'a>,
    /// As configurações que o maestro pode escolher: as que existem no padrão
    /// do CLI. Pasta arbitrária não — seria um settings com permissões abertas.
    pub known_configs: Configs<'a>,
}

impl<'a> MaestroContext<'a> {
    pub fn new(
        caller: impl Into<String>,
        profiles: BTreeMap<String, AgentProfile>,
        home: impl Into<String>,
    ) -> Self {
        let home: String = home.into();
        let configs_home = home.clone();
        Self {
            caller: caller.into(),
            profiles,
            home,
            catalog: Box::new(|_| None),
            working: HashSet::new(),
            background: HashSet::new(),
            directory_exists: Box::new(|path| Path::new(path).is_dir()),
            suggested_config: Box::new(|_| None),
            known_configs: Box::new(move |profile| {
                profile
                    .discovered_configs(Path::new(&configs_home))
                    .iter()
                    .map(|p| p.to_string_lossy().into_owned())
                    .collect()
            }),
        }
    }
}

/// A bancada como ficaria e o que muda na tela. Com `errors`, nada vale.
#[derive(Debug, Clone)]
pub struct MaestroOutcome {
    pub errors: Vec<String>,
    pub next: WorkbenchConfig,
    pub created: Vec<String>,
    /// Mudam e precisam de processo novo.
    pub restarted: Vec<String>,
    pub removed: Vec<String>,
    /// Dos reiniciados, os que mudaram de pasta, configuração ou CLI: a
    /// conversa é zerada de propósito.
    pub fresh_conversation: Vec<String>,
    pub edges_changed: bool,
    pub rules_changed: bool,
    pub relaid: bool,
}

impl MaestroOutcome {
    pub fn new(next: WorkbenchConfig) -> Self {
        Self {
            errors: Vec::new(),
            next,
            created: Vec::new(),
            restarted: Vec::new(),
            removed: Vec::new(),
            fresh_conversation: Vec::new(),
            edges_changed: false,
            rules_changed: false,
            relaid: false,
        }
    }

    pub fn changed(&self) -> bool {
        !self.created.is_empty()
            || !self.restarted.is_empty()
            || !self.removed.is_empty()
            || self.edges_changed
            || self.rules_changed
            || self.relaid
    }

    /// `+front ~revisor −velho · arestas · regras da bancada`.
    pub fn summary(&self) -> String {
        let mut parts = Vec::new();
        let nodes: Vec<String> = self
            .created
            .iter()
            .map(|id| format!("+{id}"))
            .chain(self.restarted.iter().map(|id| format!("~{id}")))
            .chain(self.removed.iter().map(|id| format!("−{id}")))
            .collect();
        if !nodes.is_empty() {
            parts.push(nodes.join(" "));
        }
        if self.edges_changed {
            parts.push(format!("{} aresta(s)", self.next.edge_list().len()));
        }
        if self.rules_changed {
            parts.push("regras da bancada".to_owned());
        }
        if self.relaid {
            parts.push("canvas rearrumado".to_owned());
        }
        if parts.is_empty() {
            "nada muda".to_owned()
        } else {
            parts.join(" · ")
        }
    }
}

fn kind_name(kind: NodeKind) -> &'static str {
    match kind {
        NodeKind::Shell => "shell",
        NodeKind::Agent => "agent",
        NodeKind::Web => "web",
        NodeKind::Queue => "queue",
    }
}

pub fn plan(
    plan: &MaestroPlan,
    bench: &WorkbenchConfig,
    context: &MaestroContext,
) -> MaestroOutcome {
    let mut out = MaestroOutcome::new(bench.clone());
    let mut errors: Vec<String> = Vec::new();

    let mut seen: HashSet<&str> = HashSet::new();
    for node in &plan.nodes {
        let slug = NodeId::slug(&node.id);
        if node.id != slug.as_str() {
            errors.push(format!(
                "nó '{}': id tem de ser minúsculo, com letras, números, - ou _ (ex.: '{}')",
                node.id,
                slug.as_str()
            ));
        }
        if node.id == context.caller {
            errors.push(format!(
                "nó '{}': é você — o maestro não se reconfigura pelo plano (reiniciar mataria \
                 este turno). Peça ao usuário no seletor do card.",
                node.id
            ));
        }
        if !seen.insert(node.id.as_str()) {
            errors.push(format!("nó '{}' aparece duas vezes em nodes", node.id));
        }
    }
    for id in &plan.remove {
        if *id == context.caller {
            errors.push(format!("remove '{id}': é você — o maestro não se remove"));
        } else if let Some(node) = bench.nodes.iter().find(|n| n.id == *id) {
            if node.is_maestro() {
                errors.push(format!("remove '{id}': é maestro — só o usuário o remove"));
            }
        } else {
            errors.push(format!("remove '{id}': não existe nesta bancada"));
        }
        if seen.contains(id.as_str()) {
            errors.push(format!("'{id}' está em nodes e em remove ao mesmo tempo"));
        }
    }

    // Upsert, validado depois de montado: é o nó final que tem de fazer
    // sentido, não cada campo isolado.
    let mut next = bench.clone();
    for patch in plan.nodes.iter().filter(|p| p.id != context.caller) {
        if let Some(position) = next.nodes.iter().position(|n| n.id == patch.id) {
            let current = next.nodes[position].clone();
            if current.is_maestro() {
                errors.push(format!(
                    "nó '{}': é maestro — só o usuário mexe em outro maestro",
                    patch.id
                ));
                continue;
            }
            if !matches!(current.kind, NodeKind::Agent | NodeKind::Shell) {
                errors.push(format!(
                    "nó '{}': é {} — o maestro só mexe em agent e shell",
                    patch.id,
                    kind_name(current.kind)
                ));
                continue;
            }
            let (updated, problems) = apply(patch, &current, context, false);
            errors.extend(problems);
            errors.extend(validate(&updated, Some(&current), bench, context));
            if needs_restart(&current, &updated) {
                out.restarted.push(patch.id.clone());
            }
            if updated.conversation_id.is_none() && current.conversation_id.is_some() {
                out.fresh_conversation.push(patch.id.clone());
            }
            next.nodes[position] = updated;
        } else {
            let (created, problems) = create(patch, context);
            errors.extend(problems);
            if let Some(created) = created {
                errors.extend(validate(&created, None, bench, context));
                next.nodes.push(created);
                out.created.push(patch.id.clone());
            }
        }
    }

    let removed: HashSet<&str> = plan
        .remove
        .iter()
        .map(String::as_str)
        .filter(|id| *id != context.caller)
        .collect();
    next.nodes.retain(|n| !removed.contains(n.id.as_str()));
    out.removed = plan
        .remove
        .iter()
        .filter(|id| removed.contains(id.as_str()) && bench.nodes.iter().any(|n| n.id == **id))
        .cloned()
        .collect();

    match &plan.rules {
        PlanField::Keep => {}
        PlanField::Clear => next.rules = None,
        PlanField::Set(text) => {
            let trimmed = text.trim();
            next.rules = (!trimmed.is_empty()).then(|| trimmed.to_owned());
        }
    }
    out.rules_changed = next.rules != bench.rules;

    // Arestas: some o que aponta para nó removido, depois o que o plano diz.
    // Nó novo não ganha seta para o maestro: a ligação é implícita.
    let ids: HashSet<String> = next.nodes.iter().map(|n| n.id.clone()).collect();
    let mut edges: Vec<EdgeConfig> = bench
        .edge_list()
        .iter()
        .filter(|e| ids.contains(&e.from) && ids.contains(&e.to))
        .cloned()
        .collect();
    for edge in &plan.edges {
        let mut ok = true;
        for end in [&edge.from, &edge.to] {
            if !ids.contains(end) {
                let why = if removed.contains(end.as_str()) {
                    "(está em remove)"
                } else {
                    "nesta bancada nem no plano"
                };
                errors.push(format!(
                    "aresta {}→{}: '{end}' não existe {why}",
                    edge.from, edge.to
                ));
                ok = false;
            }
        }
        if edge.from == edge.to {
            errors.push(format!(
                "aresta {}→{}: um nó não se liga a si mesmo",
                edge.from, edge.to
            ));
            ok = false;
        }
        match edge.max_sends {
            PlanField::Set(n) if !(1..=MAX_SENDS_CEILING).contains(&n) => {
                errors.push(format!(
                    "aresta {}→{}: maxSends tem de ficar entre 1 e {MAX_SENDS_CEILING}",
                    edge.from, edge.to
                ));
                ok = false;
            }
            PlanField::Clear => {
                errors.push(format!(
                    "aresta {}→{}: sem limite (null) só o usuário põe — use um número até \
                     {MAX_SENDS_CEILING}",
                    edge.from, edge.to
                ));
                ok = false;
            }
            _ => {}
        }
        if !ok {
            continue;
        }
        let pairs = if edge.both {
            vec![(&edge.from, &edge.to), (&edge.to, &edge.from)]
        } else {
            vec![(&edge.from, &edge.to)]
        };
        for (from, to) in pairs {
            let probe = EdgeConfig::new(from, to, None);
            if let Some(existing) = edges.iter_mut().find(|e| **e == probe) {
                existing.max_sends = edge.max_sends.applied(existing.max_sends);
            } else {
                let mut fresh = EdgeConfig::with_default_limit(from, to);
                if !edge.max_sends.is_keep() {
                    fresh.max_sends = edge.max_sends.applied(None);
                }
                edges.push(fresh);
            }
        }
    }
    for cut in &plan.unlink {
        let pairs = if cut.both {
            vec![(&cut.from, &cut.to), (&cut.to, &cut.from)]
        } else {
            vec![(&cut.from, &cut.to)]
        };
        let mut found = false;
        for (from, to) in pairs {
            let probe = EdgeConfig::new(from, to, None);
            let before = edges.len();
            edges.retain(|e| *e != probe);
            found = found || edges.len() != before;
        }
        // Aresta de nó removido já saiu junto com ele: pedir de novo não é erro.
        let gone = removed.contains(cut.from.as_str()) || removed.contains(cut.to.as_str());
        if !found && !gone {
            errors.push(format!(
                "unlink {}→{}: essa aresta não existe",
                cut.from, cut.to
            ));
        }
    }
    next.edges = if edges.is_empty() {
        bench.edges.as_ref().map(|_| Vec::new())
    } else {
        Some(edges)
    };
    out.edges_changed = !same_edges(next.edge_list(), bench.edge_list());

    // O time mudou: o canvas é rearrumado, a menos que o plano diga não.
    if plan
        .layout
        .unwrap_or(!out.created.is_empty() || !out.removed.is_empty())
    {
        let frames = layout::frames(&next.nodes, next.edge_list());
        for node in &mut next.nodes {
            if let Some(frame) = frames.get(&node.id) {
                node.set_frame(*frame);
            }
        }
    }
    // O lugar que o maestro deu à mão vence o arranjo — vem depois dele.
    for patch in plan.nodes.iter().filter(|p| p.id != context.caller) {
        let Some(wanted) = patch.frame else { continue };
        let Some(node) = next.nodes.iter_mut().find(|n| n.id == patch.id) else {
            continue;
        };
        let base = node.frame().unwrap_or(Frame {
            x: 0.0,
            y: 0.0,
            w: layout::AGENT.0,
            h: layout::AGENT.1,
        });
        let rect = standardized(Frame {
            x: wanted.x.unwrap_or(base.x),
            y: wanted.y.unwrap_or(base.y),
            w: wanted.w.unwrap_or(base.w),
            h: wanted.h.unwrap_or(base.h),
        });
        if rect.x < 0.0 || rect.y < 0.0 {
            errors.push(format!(
                "nó '{}': frame fora do canvas — x e y começam em 0",
                patch.id
            ));
        } else if rect.w < MINIMUM_SIZE.0 || rect.h < MINIMUM_SIZE.1 {
            errors.push(format!(
                "nó '{}': frame pequeno demais — mínimo {}×{}",
                patch.id, MINIMUM_SIZE.0 as i64, MINIMUM_SIZE.1 as i64
            ));
        } else {
            node.set_frame(rect);
        }
    }
    out.relaid = next.nodes.iter().any(|node| {
        node.frame().is_some()
            && bench
                .nodes
                .iter()
                .find(|b| b.id == node.id)
                .map(NodeConfig::frame)
                != Some(node.frame())
    });

    // Regra da bancada nova só sobe com processo novo: os outros agentes
    // reiniciam. O maestro não — as dele valem no próximo arranque.
    if out.rules_changed {
        for node in &next.nodes {
            if node.kind == NodeKind::Agent
                && node.id != context.caller
                && !out.created.contains(&node.id)
                && !out.restarted.contains(&node.id)
            {
                out.restarted.push(node.id.clone());
            }
        }
    }

    // Reiniciar ou remover quem está trabalhando perde o turno dele.
    let touched: Vec<&String> = out.restarted.iter().chain(out.removed.iter()).collect();
    let in_turn: Vec<&str> = touched
        .iter()
        .filter(|id| context.working.contains(id.as_str()))
        .map(|id| id.as_str())
        .collect();
    if !in_turn.is_empty() {
        errors.push(format!(
            "trabalhando agora: {} — este plano reiniciaria ou removeria, e o turno se perderia. \
             Espere terminar e mande de novo.",
            in_turn.join(", ")
        ));
    }
    let behind: Vec<&str> = touched
        .iter()
        .filter(|id| context.background.contains(id.as_str()))
        .map(|id| id.as_str())
        .collect();
    if !behind.is_empty() && !plan.force {
        errors.push(format!(
            "em segundo plano: {} — pode ser só esperando um vizinho, ou um processo rodando. \
             Confira com `egeon peek`; se puder interromper, mande o mesmo plano com \
             \"force\": true.",
            behind.join(", ")
        ));
    }

    out.next = next;
    out.errors = errors;
    out
}

/// Como o `CGRect` do Swift lê `minX`/`width`: largura e altura negativas
/// viram positivas, com a origem do outro lado.
fn standardized(mut f: Frame) -> Frame {
    if f.w < 0.0 {
        f.x += f.w;
        f.w = -f.w;
    }
    if f.h < 0.0 {
        f.y += f.h;
        f.h = -f.h;
    }
    f
}

fn create(patch: &PlanNode, context: &MaestroContext) -> (Option<NodeConfig>, Vec<String>) {
    let kind = patch.kind.unwrap_or(NodeKind::Agent);
    if !matches!(kind, NodeKind::Agent | NodeKind::Shell) {
        return (
            None,
            vec![format!(
                "nó '{}': kind '{}' — o maestro cria agent ou shell",
                patch.id,
                kind_name(kind)
            )],
        );
    }
    let mut node = NodeConfig::new(kind, &patch.id);
    if kind == NodeKind::Agent {
        let cli = match &patch.cli {
            PlanField::Set(value) => Some(value.clone()),
            PlanField::Keep | PlanField::Clear => {
                if context.profiles.contains_key("claude") {
                    Some("claude".to_owned())
                } else {
                    context.profiles.keys().next().cloned()
                }
            }
        };
        node.config = cli.as_deref().and_then(|c| (context.suggested_config)(c));
        node.agent = cli;
    }
    let (mut filled, mut problems) = apply(patch, &node, context, true);
    filled.component = Some("maestro".to_owned());
    if kind == NodeKind::Agent && filled.agent.is_none() {
        problems.push(format!("nó '{}': falta 'cli'", patch.id));
    }
    (Some(filled), problems)
}

fn apply(
    patch: &PlanNode,
    current: &NodeConfig,
    context: &MaestroContext,
    is_new: bool,
) -> (NodeConfig, Vec<String>) {
    let mut node = current.clone();
    let mut problems = Vec::new();
    let label = format!("nó '{}'", patch.id);

    if let Some(kind) = patch.kind
        && kind != current.kind
        && !is_new
    {
        problems.push(format!(
            "{label}: é {} e não vira {} — remova e crie de novo com outro id",
            kind_name(current.kind),
            kind_name(kind)
        ));
    }

    if node.kind == NodeKind::Agent && !is_new {
        match &patch.cli {
            PlanField::Keep => {}
            PlanField::Clear => {
                problems.push(format!("{label}: 'cli' não pode ser null num agente"))
            }
            PlanField::Set(cli) if Some(cli) != node.agent.as_ref() => {
                // A conversa é do outro programa, e o que era dele não serve.
                node = node.without_conversation();
                node.agent = Some(cli.clone());
                node.cmd = None;
                node.model = None;
                node.effort = None;
                node.ultracode = None;
                node.config = (context.suggested_config)(cli);
            }
            PlanField::Set(_) => {}
        }
    }
    if node.kind == NodeKind::Shell {
        for (name, keep) in [
            ("cli", patch.cli.is_keep()),
            ("model", patch.model.is_keep()),
            ("effort", patch.effort.is_keep()),
            ("role", patch.role.is_keep()),
            ("rules", patch.rules.is_keep()),
            ("config", patch.config.is_keep()),
        ] {
            if !keep {
                problems.push(format!("{label}: '{name}' é de agente; este é shell"));
            }
        }
        if matches!(patch.ultracode, PlanField::Set(_)) {
            problems.push(format!("{label}: 'ultracode' é de agente; este é shell"));
        }
    }

    node.model = clean(patch.model.applied(node.model.clone()));
    node.effort = clean(patch.effort.applied(node.effort.clone()));
    node.ultracode = (patch.ultracode.applied(node.ultracode) == Some(true)).then_some(true);
    node.cwd = clean(patch.cwd.applied(node.cwd.clone()));
    node.config = clean(patch.config.applied(node.config.clone()));
    if node.kind == NodeKind::Shell {
        node.cmd = clean(patch.cmd.applied(node.cmd.clone()));
    } else if !patch.cmd.is_keep() {
        problems.push(format!(
            "{label}: 'cmd' é de shell — o comando do agente é o do CLI"
        ));
    }
    // A conversa do CLI é da pasta e da configuração em que nasceu.
    if !is_new && (node.cwd != current.cwd || node.config != current.config) {
        node = node.without_conversation();
    }

    // Papel e regras escritos aqui são os que sobem: a exceção do CLI em uso
    // cede o lugar (ADR-057).
    if !patch.role.is_keep() {
        node.prompt = clean(patch.role.applied(node.prompt.clone()));
        node.by_agent = dropping(
            |o| &mut o.prompt,
            node.agent.as_deref(),
            node.by_agent.take(),
        );
    }
    if !patch.rules.is_keep() {
        node.rules = clean(patch.rules.applied(node.rules.clone()));
        node.by_agent = dropping(
            |o| &mut o.rules,
            node.agent.as_deref(),
            node.by_agent.take(),
        );
    }
    (node, problems)
}

/// `expandingTildeInPath` + `standardized`.
fn standard(path: &str, home: &str) -> String {
    path_text::standardize(&path_text::expand_tilde(path, home))
}

/// Confere só o que o plano mudou (ou tudo, num nó novo).
fn validate(
    node: &NodeConfig,
    previous: Option<&NodeConfig>,
    bench: &WorkbenchConfig,
    context: &MaestroContext,
) -> Vec<String> {
    let mut problems = Vec::new();
    let label = format!("nó '{}'", node.id);
    let same_cli = previous.map(|p| &p.agent) == Some(&node.agent);
    let changed = |f: fn(&NodeConfig) -> Option<&String>| previous.is_none_or(|p| f(p) != f(node));
    let cwd_changed = changed(|n| n.cwd.as_ref());
    let config_changed = changed(|n| n.config.as_ref());
    let model_changed = changed(|n| n.model.as_ref());
    let effort_changed = changed(|n| n.effort.as_ref());

    if let Some(cwd) = &node.cwd
        && cwd_changed
    {
        let resolved = WorkbenchConfig::resolve(cwd, &bench.url_path(&context.home), &context.home);
        if !(context.directory_exists)(&resolved) {
            problems.push(format!(
                "{label}: pasta '{cwd}' não existe (resolve em {resolved})"
            ));
        }
    }
    if node.kind != NodeKind::Agent {
        return problems;
    }

    let Some((key, profile)) = node
        .agent
        .as_ref()
        .and_then(|k| context.profiles.get_key_value(k))
    else {
        let known: Vec<&str> = context.profiles.keys().map(String::as_str).collect();
        problems.push(format!(
            "{label}: CLI '{}' não existe — disponíveis: {}",
            node.agent.as_deref().unwrap_or(""),
            known.join(", ")
        ));
        return problems;
    };
    if let Some(config) = &node.config
        && (config_changed || !same_cli)
    {
        let wanted = standard(config, &context.home);
        let mut allowed = (context.known_configs)(profile);
        allowed.extend((context.suggested_config)(key));
        if !allowed.iter().any(|a| standard(a, &context.home) == wanted) {
            problems.push(format!(
                "{label}: config '{config}' não está entre as de {} — use uma de `configs` em \
                 `egeon models`",
                profile.display_name
            ));
        }
    }

    let catalog = (context.catalog)(profile);
    let mut chosen: Option<CatalogModel> = None;
    if let Some(model) = &node.model
        && (model_changed || !same_cli)
    {
        if !profile.offers_models() {
            problems.push(format!(
                "{label}: {} não aceita escolher modelo",
                profile.display_name
            ));
        } else if let Some(catalog) = catalog.as_ref().filter(|c| !c.models.is_empty()) {
            chosen = catalog.model_for(Some(model)).cloned();
            if chosen.is_none() {
                problems.push(format!(
                    "{label}: modelo '{model}' não existe no {} — veja `egeon models`",
                    profile.display_name
                ));
            }
        } else if let Some(listed) = profile.models.as_ref().filter(|l| !l.is_empty())
            && !listed.contains(model)
        {
            problems.push(format!(
                "{label}: modelo '{model}' não está entre {}",
                listed.join(", ")
            ));
        }
    }
    if let Some(effort) = &node.effort
        && (effort_changed || model_changed || !same_cli)
    {
        if !profile.offers_efforts() {
            problems.push(format!(
                "{label}: {} não aceita escolher esforço",
                profile.display_name
            ));
        } else if let Some(chosen) = &chosen {
            if chosen.efforts.is_empty() {
                problems.push(format!(
                    "{label}: {} não tem nível de esforço — tire 'effort'",
                    chosen.label
                ));
            } else if !chosen.efforts.contains(effort) {
                problems.push(format!(
                    "{label}: {} não tem esforço '{effort}' — aceita {}",
                    chosen.label,
                    chosen.efforts.join(", ")
                ));
            }
        } else {
            // Sem modelo escolhido, o padrão do CLI decide — qualquer nível de
            // algum modelo dele é plausível.
            let known: BTreeSet<&String> = catalog
                .iter()
                .flat_map(|c| c.models.iter().flat_map(|m| m.efforts.iter()))
                .chain(profile.efforts.iter().flatten())
                .collect();
            if !known.is_empty() && !known.contains(effort) {
                let list: Vec<&str> = known.iter().map(|s| s.as_str()).collect();
                problems.push(format!(
                    "{label}: esforço '{effort}' não existe no {} — aceitos: {}",
                    profile.display_name,
                    list.join(", ")
                ));
            }
        }
    }
    if node.ultracode == Some(true) && profile.ultracode.is_none() {
        problems.push(format!(
            "{label}: {} não tem ultracode",
            profile.display_name
        ));
    }
    problems
}

/// A régua do formulário: o que entra na linha de comando ou no system prompt
/// só vale com processo novo.
pub fn needs_restart(a: &NodeConfig, b: &NodeConfig) -> bool {
    a.kind != b.kind
        || a.agent != b.agent
        || a.model != b.model
        || a.effort != b.effort
        || a.ultracode != b.ultracode
        || a.cmd != b.cmd
        || a.config != b.config
        || a.cwd != b.cwd
        || a.effective_prompt() != b.effective_prompt()
        || a.effective_rules() != b.effective_rules()
}

fn clean(text: Option<String>) -> Option<String> {
    let text = text?;
    let trimmed = text.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_owned())
}

fn dropping(
    field: impl Fn(&mut Overrides) -> &mut Option<String>,
    cli: Option<&str>,
    map: Option<BTreeMap<String, Overrides>>,
) -> Option<BTreeMap<String, Overrides>> {
    let (Some(cli), Some(mut map)) = (cli, map.clone()) else {
        return map;
    };
    let Some(mut over) = map.get(cli).cloned() else {
        return Some(map);
    };
    if field(&mut over).is_none() {
        return Some(map);
    }
    *field(&mut over) = None;
    if over.is_empty() {
        map.remove(cli);
    } else {
        map.insert(cli.to_owned(), over);
    }
    (!map.is_empty()).then_some(map)
}

fn same_edges(a: &[EdgeConfig], b: &[EdgeConfig]) -> bool {
    a.len() == b.len()
        && a.iter()
            .all(|edge| b.iter().any(|o| o == edge && o.max_sends == edge.max_sends))
}
