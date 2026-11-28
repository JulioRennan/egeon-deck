//! Atende o maestro: confere que quem chama é um, lê a bancada e aplica o
//! plano (ADR-066). Porte de `MaestroController.swift`.
//!
//! Não guarda bancada nem nó: lê pelo [`MaestroWiring`] e devolve o que mudar
//! como [`MaestroEffect`], na ordem em que o Swift chamava as closures.

use std::collections::BTreeMap;
use std::time::SystemTime;

use serde_json::{Value, json};

use super::permissions;
use super::plan::MaestroPlan;
use super::planner::{self, MaestroContext};
use super::snapshot;
use crate::features::activity::model::Activity;
use crate::features::agent::model::AgentProfile;
use crate::features::agent::model_catalog::ModelCatalog;
use crate::features::node::model::NodeConfig;
use crate::features::permission::model::PermissionAnswer;
use crate::features::permission::service::PermissionDesk;
use crate::features::workbench::model::WorkbenchConfig;
use crate::log;

pub const NOT_MAESTRO: &str = "este terminal não é maestro — quem decide isso é o usuário, no \
formulário do terminal (⚙ no card → \"Maestro\")";
pub const NOT_APPROVER: &str = "só o maestro da bancada responde permissões do time";
const NOT_FROM_TERMINAL: &str = "esta conexão não veio de um terminal";

/// O que o controller lê do mundo.
pub trait MaestroWiring {
    /// A bancada pelo nome — a primeira parte do endereço.
    fn bench(&self, name: &str) -> Option<WorkbenchConfig>;
    /// O mundo que o planejador precisa, montado na hora para a bancada.
    fn context(&self, bench: &WorkbenchConfig, caller: &str) -> MaestroContext<'_>;
    fn activity(&self, address: &str) -> Option<Activity>;
    fn profiles(&self) -> BTreeMap<String, AgentProfile>;
    fn catalog(&self, profile: &AgentProfile) -> Option<ModelCatalog>;
    fn home(&self) -> String;
}

/// O que o ator faz depois de um `apply`, nesta ordem.
#[derive(Debug, Clone, PartialEq)]
pub enum MaestroEffect {
    /// Grava a bancada seguinte no lugar da atual, pelo id.
    Commit(WorkbenchConfig),
    Dispose {
        bench: String,
        node: String,
    },
    Restart {
        bench: String,
        node: String,
    },
    Spawn {
        bench: String,
        node: String,
    },
    RedrawEdges {
        bench: String,
    },
    /// Leva os cards na tela aos frames gravados, e enquadra.
    Arrange {
        bench: String,
    },
    Persist,
    /// Linha na trilha da bancada, carimbada como quem chamou.
    Trace {
        address: String,
        text: String,
    },
    /// Um pedido do time foi respondido pelo maestro: o terminal que pediu
    /// volta ao trabalho (`Dispatcher::permission_answered`).
    PermissionAnswered {
        address: String,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub struct Reply {
    pub status: u16,
    pub json: Value,
    pub effects: Vec<MaestroEffect>,
}

impl Reply {
    fn ok(json: Value) -> Self {
        Self {
            status: 200,
            json,
            effects: Vec::new(),
        }
    }

    fn refuse(status: u16, message: &str) -> Self {
        Self {
            status,
            json: json!({"ok": false, "error": message}),
            effects: Vec::new(),
        }
    }
}

/// Quem chama tem de ser um nó maestro com bancada carregada.
fn authorize(
    wiring: &dyn MaestroWiring,
    caller: Option<&str>,
) -> Result<(WorkbenchConfig, NodeConfig), Reply> {
    let Some(caller) = caller else {
        return Err(Reply::refuse(403, NOT_FROM_TERMINAL));
    };
    let parts: Vec<&str> = caller.splitn(2, '/').collect();
    let found = match parts.as_slice() {
        [bench, node] if !bench.is_empty() && !node.is_empty() => {
            wiring.bench(bench).and_then(|b| {
                b.nodes
                    .iter()
                    .find(|n| n.id == *node)
                    .cloned()
                    .map(|n| (b, n))
            })
        }
        _ => None,
    };
    let Some((bench, node)) = found else {
        return Err(Reply::refuse(404, "nó sem bancada carregada"));
    };
    if !node.is_maestro() {
        return Err(Reply::refuse(403, NOT_MAESTRO));
    }
    Ok((bench, node))
}

fn approver(
    wiring: &dyn MaestroWiring,
    caller: Option<&str>,
) -> Result<(WorkbenchConfig, NodeConfig), Reply> {
    let (bench, me) = authorize(wiring, caller)?;
    if !me.approves_team_permissions() {
        return Err(Reply::refuse(403, NOT_APPROVER));
    }
    Ok((bench, me))
}

/// `GET /maestro/asks`: os pedidos de ferramenta abertos no time, sem os seus.
pub fn permissions(
    wiring: &dyn MaestroWiring,
    caller: Option<&str>,
    desk: &mut PermissionDesk,
    now: SystemTime,
) -> Reply {
    let (bench, me) = match approver(wiring, caller) {
        Ok(found) => found,
        Err(refusal) => return refusal,
    };
    let mine = format!("{}/{}", bench.name, me.id);
    let prefix = format!("{}/", bench.name);
    let open: Vec<Value> = desk
        .open(now)
        .iter()
        .filter(|a| {
            a.address.starts_with(&prefix) && a.address != mine && permissions::delegable(a)
        })
        .map(permissions::listing)
        .collect();
    Reply::ok(json!({"ok": true, "open": open}))
}

/// Quem respondeu, para o log da mesa.
pub fn answered_by(maestro: &str) -> String {
    format!("pelo maestro {maestro}")
}

/// `POST /maestro/answer?id=&answer=`.
pub fn answer_permission(
    wiring: &dyn MaestroWiring,
    id: &str,
    answer: PermissionAnswer,
    caller: Option<&str>,
    desk: &mut PermissionDesk,
    now: SystemTime,
) -> Reply {
    let (bench, me) = match approver(wiring, caller) {
        Ok(found) => found,
        Err(refusal) => return refusal,
    };
    let mine = format!("{}/{}", bench.name, me.id);
    let Some(ask) = desk.open(now).iter().find(|a| a.id == id).cloned() else {
        return Reply::refuse(
            404,
            &format!("pedido {id} já acabou — respondido, expirado ou o turno seguiu"),
        );
    };
    if !ask.address.starts_with(&format!("{}/", bench.name)) {
        return Reply::refuse(403, &format!("pedido {id} é de outra bancada"));
    }
    if ask.address == mine {
        return Reply::refuse(403, "esse pedido é seu — quem responde é o usuário");
    }
    if !permissions::delegable(&ask) {
        return Reply::refuse(403, "pergunta ao usuário não é sua para responder");
    }
    if !desk.answer(id, answer, &answered_by(&me.id), now) {
        return Reply::refuse(404, &format!("pedido {id} já acabou"));
    }
    let who = ask
        .address
        .rsplit('/')
        .find(|s| !s.is_empty())
        .unwrap_or(&ask.address);
    let verb = match answer {
        PermissionAnswer::Deny => "negou",
        PermissionAnswer::Always => "permitiu sempre",
        PermissionAnswer::Allow => "permitiu",
    };
    let summary: String = ask.summary.chars().take(160).collect();
    Reply {
        status: 200,
        json: json!({"ok": true, "id": id, "answer": answer.as_str(), "from": ask.address}),
        effects: vec![
            MaestroEffect::PermissionAnswered {
                address: ask.address.clone(),
            },
            MaestroEffect::Trace {
                address: mine,
                text: format!("maestro {verb} {} de {who}: {summary}", ask.tool),
            },
        ],
    }
}

/// `GET /maestro/bench`.
pub fn bench(wiring: &dyn MaestroWiring, caller: Option<&str>) -> Reply {
    match authorize(wiring, caller) {
        Err(refusal) => refusal,
        Ok((bench, node)) => {
            let name = bench.name.clone();
            let activity = |id: &str| wiring.activity(&format!("{name}/{id}"));
            Reply::ok(snapshot::bench(&bench, &node.id, &activity))
        }
    }
}

/// `GET /maestro/models`.
pub fn models(wiring: &dyn MaestroWiring, caller: Option<&str>) -> Reply {
    match authorize(wiring, caller) {
        Err(refusal) => refusal,
        Ok(_) => {
            let catalog = |p: &AgentProfile| wiring.catalog(p);
            Reply::ok(snapshot::models(
                &wiring.profiles(),
                &catalog,
                &wiring.home(),
            ))
        }
    }
}

/// `POST /maestro/apply[?dry=1]`: `dry` valida e mostra o que mudaria; sem
/// ele, aplica. Plano com erro não muda nada, em nenhum dos dois.
pub fn apply(wiring: &dyn MaestroWiring, body: &[u8], caller: Option<&str>, dry: bool) -> Reply {
    let (bench, me) = match authorize(wiring, caller) {
        Ok(found) => found,
        Err(refusal) => return refusal,
    };
    let plan = match MaestroPlan::parse(body) {
        Ok(plan) => plan,
        Err(message) => {
            return Reply {
                status: 400,
                json: json!({"ok": false, "errors": [message]}),
                effects: Vec::new(),
            };
        }
    };
    if plan.is_empty() {
        return Reply {
            status: 400,
            json: json!({"ok": false,
                "errors": ["plano sem nada: use nodes, remove, edges, unlink ou rules"]}),
            effects: Vec::new(),
        };
    }

    let outcome = {
        let context = wiring.context(&bench, &me.id);
        planner::plan(&plan, &bench, &context)
    };
    if !outcome.errors.is_empty() {
        return Reply {
            status: 422,
            json: json!({"ok": false, "errors": outcome.errors,
                "detail": "nada foi aplicado — corrija e mande o plano inteiro de novo"}),
            effects: Vec::new(),
        };
    }

    let mut payload = json!({
        "ok": true,
        "dry": dry,
        "summary": outcome.summary(),
        "created": outcome.created,
        "restarted": outcome.restarted,
        "removed": outcome.removed,
    });
    let put = |payload: &mut Value, key: &str, value: Value| {
        if let Some(map) = payload.as_object_mut() {
            map.insert(key.to_owned(), value);
        }
    };
    if dry {
        let result = snapshot::bench(&outcome.next, &me.id, &|_| None);
        put(&mut payload, "result", result);
        put(
            &mut payload,
            "detail",
            json!("prévia — nada mudou. `egeon apply` com o mesmo plano aplica."),
        );
        return Reply::ok(payload);
    }
    if !outcome.changed() {
        put(
            &mut payload,
            "detail",
            json!("o plano já é o que está na bancada — nada mudou"),
        );
        return Reply::ok(payload);
    }

    let name = bench.name.clone();
    let address = format!("{name}/{}", me.id);
    let mut effects = vec![MaestroEffect::Commit(outcome.next.clone())];
    let each = |ids: &[String], make: fn(String, String) -> MaestroEffect| {
        ids.iter()
            .map(|id| make(name.clone(), id.clone()))
            .collect::<Vec<_>>()
    };
    effects.extend(each(&outcome.removed, |bench, node| {
        MaestroEffect::Dispose { bench, node }
    }));
    effects.extend(each(&outcome.restarted, |bench, node| {
        MaestroEffect::Restart { bench, node }
    }));
    effects.extend(each(&outcome.created, |bench, node| MaestroEffect::Spawn {
        bench,
        node,
    }));
    effects.push(MaestroEffect::RedrawEdges {
        bench: name.clone(),
    });
    if outcome.relaid {
        effects.push(MaestroEffect::Arrange {
            bench: name.clone(),
        });
    }
    effects.push(MaestroEffect::Persist);
    effects.push(MaestroEffect::Trace {
        address: address.clone(),
        text: format!("maestro aplicou: {}", outcome.summary()),
    });
    log!("maestro[{address}]: {}", outcome.summary());

    let mut notes: Vec<String> = Vec::new();
    if !outcome.created.is_empty() {
        notes.push(format!(
            "{} sobem em alguns segundos; você já os alcança sem aresta, e `egeon send` \
             enfileira até ficarem prontos",
            outcome.created.join(", ")
        ));
    }
    let kept: Vec<&str> = outcome
        .restarted
        .iter()
        .filter(|id| !outcome.fresh_conversation.contains(id))
        .map(String::as_str)
        .collect();
    if !kept.is_empty() {
        notes.push(format!(
            "{} reiniciaram com a mesma conversa",
            kept.join(", ")
        ));
    }
    if !outcome.fresh_conversation.is_empty() {
        notes.push(format!(
            "{} reiniciaram com conversa NOVA (pasta, configuração ou CLI mudou) — o que eles \
             sabiam ficou para trás",
            outcome.fresh_conversation.join(", ")
        ));
    }
    if outcome.rules_changed {
        notes.push("as regras novas da bancada valem para você no seu próximo arranque".to_owned());
    }
    if !notes.is_empty() {
        put(&mut payload, "notes", json!(notes));
    }
    Reply {
        status: 200,
        json: payload,
        effects,
    }
}
