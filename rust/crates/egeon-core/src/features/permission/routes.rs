//! As rotas da permissão respondida pelo app (ADR-068), porte do
//! `ControlSocket.swift`. Mesma forma das de `dispatch::routes`.
//!
//! Ordem relativa no Swift: `answer` (`contains("/permission/answer")`),
//! `list` (`hasSuffix("/permissions")`), `open` (POST `hasSuffix("/permission")`),
//! `poll` (GET `hasSuffix("/permission")`) — entre `/conversation` e `/activity`.

use std::collections::HashMap;
use std::time::SystemTime;

use serde_json::{Value, json};

use super::model::PermissionAnswer;
use crate::features::dispatch::coordination::{Coordination, World};
use crate::features::dispatch::routes::{Handled, NOT_FROM_TERMINAL, plain};
use crate::features::dispatch::service::workbench_of;
use crate::features::maestro::permissions as maestro;
use crate::log;
use crate::protocol::handler::{RouteReply, RouteRequest};

/// `POST` com `/permission/answer` no alvo — `ControlSocket.swift:250`.
/// `?id=&answer=allow|always|deny`, `?id=&choice=<opção>` (pergunta única) ou
/// corpo `{"answers": {"pergunta": ["opção"]}}`.
pub fn answer(
    state: &mut Coordination,
    req: &RouteRequest,
    now: SystemTime,
    world: &dyn World,
) -> Handled {
    let parsed: Option<Value> = serde_json::from_slice(&req.body).ok();
    let body_choices: Option<HashMap<String, Vec<String>>> = parsed
        .as_ref()
        .and_then(|p| p.get("answers"))
        .and_then(Value::as_object)
        .map(|answers| {
            answers
                .iter()
                .map(|(question, value)| {
                    let picked = match value.as_array() {
                        Some(items) if items.iter().all(Value::is_string) => items
                            .iter()
                            .filter_map(Value::as_str)
                            .map(str::to_owned)
                            .collect(),
                        _ => vec![value.as_str().unwrap_or("").to_owned()],
                    };
                    (question.clone(), picked)
                })
                .collect()
        });
    let parsed_answer = req.param("answer").and_then(PermissionAnswer::parse);
    let id = match req.param("id") {
        Some(id)
            if parsed_answer.is_some()
                || req.param("choice").is_some()
                || body_choices.is_some() =>
        {
            id
        }
        _ => {
            return plain(RouteReply::err(
                400,
                "use ?id=<pedido>&answer=allow|always|deny, ?id=<pedido>&choice=<opção> ou corpo \
                 {\"answers\": {…}}",
            ));
        }
    };
    let address = state
        .desk
        .open(now)
        .iter()
        .find(|a| a.id == id)
        .map(|a| a.address.clone());
    let ok = if let Some(answer) = parsed_answer {
        state.desk.answer(id, answer, "pelo chat", now)
    } else {
        let mut choices = body_choices.unwrap_or_default();
        if let Some(choice) = req.param("choice")
            && let Some(first) = state.desk.first_question_choice(id, choice, now)
        {
            choices = first;
        }
        state.desk.answer_choices(id, &choices, now)
    };
    if !ok {
        return plain(RouteReply::err(
            404,
            format!("pedido {id} já acabou, ou escolha fora das opções"),
        ));
    }
    let out = address
        .map(|a| state.answered(&a, now, world))
        .unwrap_or_default();
    (RouteReply::ok(json!({"ok": true})), out)
}

/// `GET …/permissions` — `ControlSocket.swift:287`.
pub fn list(state: &mut Coordination, _: &RouteRequest, now: SystemTime, _: &dyn World) -> Handled {
    plain(RouteReply::ok(state.desk.listing(now)))
}

/// `POST …/permission` — `ControlSocket.swift:299`. Corpo: o payload do gancho
/// `PermissionRequest`, inteiro. Com um maestro que aprova pelo time, o aviso
/// entra na fila dele (`AppControl.permissionOpened`, ADR-080).
pub fn open(
    state: &mut Coordination,
    req: &RouteRequest,
    now: SystemTime,
    world: &dyn World,
) -> Handled {
    let payload: Value = serde_json::from_slice::<Value>(&req.body)
        .ok()
        .filter(Value::is_object)
        .unwrap_or_else(|| json!({}));
    let Some(address) = state.hook_caller(req.origin.as_deref(), req.param("target")) else {
        return plain(RouteReply::err(403, NOT_FROM_TERMINAL));
    };
    let Some(ask) = state.desk.open_ask(&address, &payload, now) else {
        return plain(RouteReply::err(400, "payload sem tool_name"));
    };
    if let Some(bench) = world.workbench(workbench_of(&ask.address))
        && let Some(approver) = maestro::approver(&ask, &bench)
    {
        let to = format!("{}/{}", bench.name, approver.id);
        // Fila, e não interrupção: com o maestro no meio de um turno, o aviso
        // entra quando ele parar.
        if state.dispatcher.enqueue(&to, maestro::notice(&ask)) {
            log!(
                "permissão[{}]: avisada ao maestro {to} — {}",
                ask.address,
                ask.id
            );
        }
    }
    plain(RouteReply::ok(json!({"ok": true, "id": ask.id})))
}

/// `GET …/permission?id=` — `ControlSocket.swift:319`: o gancho perguntando se
/// já tem resposta.
pub fn poll(
    state: &mut Coordination,
    req: &RouteRequest,
    now: SystemTime,
    _: &dyn World,
) -> Handled {
    plain(RouteReply::ok(
        state.desk.poll(req.param("id").unwrap_or_default(), now),
    ))
}
