//! O que o maestro lê antes de desenhar: a bancada como está e o que cada CLI
//! aceita (ADR-066). Porte de `MaestroSnapshot.swift`; JSON pronto, porque é
//! isso que volta pelo socket.

use std::collections::BTreeMap;
use std::path::Path;

use serde_json::{Map, Value, json};

use crate::features::activity::model::Activity;
use crate::features::agent::model::AgentProfile;
use crate::features::agent::model_catalog::ModelCatalog;
use crate::features::node::model::{NodeConfig, NodeKind};
use crate::features::workbench::model::WorkbenchConfig;

/// A bancada no MESMO vocabulário do plano, para o maestro copiar um nó daqui
/// para lá. `state`, `you` e `maestro` são só de leitura.
pub fn bench(
    bench: &WorkbenchConfig,
    caller: &str,
    activity: &dyn Fn(&str) -> Option<Activity>,
) -> Value {
    let nodes: Vec<Value> = bench
        .nodes
        .iter()
        .map(|n| node(n, caller, activity(&n.id).as_ref()))
        .collect();
    let edges: Vec<Value> = bench
        .edge_list()
        .iter()
        .map(|e| json!({"from": e.from, "to": e.to, "maxSends": e.max_sends}))
        .collect();
    let mut payload = json!({
        "workbench": bench.name,
        "path": bench.path,
        "you": caller,
        "nodes": nodes,
        "edges": edges,
        "note": "edges são as desenhadas; o maestro alcança todo terminal sem aresta, e todo agente alcança o maestro",
    });
    if let (Some(rules), Some(map)) = (&bench.rules, payload.as_object_mut()) {
        map.insert("rules".to_owned(), json!(rules));
    }
    payload
}

pub fn node(node: &NodeConfig, caller: &str, activity: Option<&Activity>) -> Value {
    let mut out = Map::new();
    let mut put = |k: &str, v: Value| {
        out.insert(k.to_owned(), v);
    };
    put("id", json!(node.id));
    put(
        "kind",
        serde_json::to_value(node.kind).unwrap_or(Value::Null),
    );
    if node.kind == NodeKind::Agent {
        put("cli", json!(node.agent));
        put("model", json!(node.model));
        put("effort", json!(node.effort));
        if node.ultracode == Some(true) {
            put("ultracode", json!(true));
        }
        if let Some(role) = node.effective_prompt() {
            put("role", json!(role));
        }
        if let Some(rules) = node.effective_rules() {
            put("rules", json!(rules));
        }
        if let Some(config) = &node.config {
            put("config", json!(config));
        }
    }
    if node.kind == NodeKind::Shell
        && let Some(cmd) = &node.cmd
    {
        put("cmd", json!(cmd));
    }
    if let Some(cwd) = &node.cwd {
        put("cwd", json!(cwd));
    }
    if let Some(f) = node.frame() {
        // `Int(CGFloat)` trunca, como o `as` daqui.
        put(
            "frame",
            json!({"x": f.x as i64, "y": f.y as i64, "w": f.w as i64, "h": f.h as i64}),
        );
    }
    if node.is_maestro() {
        put("maestro", json!(true));
    }
    if node.approves_team_permissions() {
        put("approvesPermissions", json!(true));
    }
    if node.id == caller {
        put("you", json!(true));
    }
    if let Some(activity) = activity {
        put("state", json!(state(activity)));
    }
    Value::Object(out)
}

/// Estado em palavra fixa, não o rótulo da tela: é o que o maestro compara.
pub fn state(activity: &Activity) -> &'static str {
    match activity {
        Activity::Starting => "starting",
        Activity::Ready => "idle",
        Activity::Working => "working",
        Activity::Background => "background",
        Activity::Awaiting(_) => "awaiting",
        Activity::Waiting => "done",
        Activity::Asking => "asking",
        Activity::Retrying { .. } => "retrying",
        Activity::Failed(_) => "failed",
        Activity::Dead => "dead",
    }
}

/// Os CLIs que existem, com modelos e níveis: do catálogo do binário quando
/// há (ADR-064), senão os apelidos do `agents.json`.
pub fn models(
    profiles: &BTreeMap<String, AgentProfile>,
    catalog: &dyn Fn(&AgentProfile) -> Option<ModelCatalog>,
    home: &str,
) -> Value {
    let clis: Vec<Value> = profiles
        .iter()
        .map(|(key, profile)| {
            let mut out = Map::new();
            out.insert("cli".into(), json!(key));
            out.insert("name".into(), json!(profile.display_name));
            out.insert("acceptsModel".into(), json!(profile.offers_models()));
            out.insert("acceptsEffort".into(), json!(profile.offers_efforts()));
            out.insert("ultracode".into(), json!(profile.ultracode.is_some()));
            if let Some(catalog) = catalog(profile).filter(|c| !c.models.is_empty()) {
                let models: Vec<Value> = catalog
                    .featured()
                    .into_iter()
                    .chain(catalog.older())
                    .map(|m| {
                        let mut entry = json!({"id": m.id, "label": m.label,
                            "family": m.family, "efforts": m.efforts});
                        if let (Some(auto), Some(map)) = (&m.default_effort, entry.as_object_mut())
                        {
                            map.insert("defaultEffort".into(), json!(auto));
                        }
                        entry
                    })
                    .collect();
                out.insert("models".into(), Value::Array(models));
            } else if let Some(listed) = profile.models.as_ref().filter(|l| !l.is_empty()) {
                let models: Vec<Value> = listed.iter().map(|id| json!({"id": id})).collect();
                out.insert("models".into(), Value::Array(models));
            }
            if let Some(efforts) = profile.efforts.as_ref().filter(|e| !e.is_empty()) {
                out.insert("efforts".into(), json!(efforts));
            }
            let configs: Vec<String> = profile
                .discovered_configs(Path::new(home))
                .iter()
                .map(|p| p.to_string_lossy().into_owned())
                .collect();
            if !configs.is_empty() {
                out.insert("configs".into(), json!(configs));
            }
            Value::Object(out)
        })
        .collect();
    json!({
        "clis": clis,
        "note": "model aceita o id ou o apelido da família (opus, sonnet, haiku); effort tem de estar em efforts do modelo escolhido",
    })
}
