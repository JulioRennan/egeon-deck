//! As rotas do envio entre agentes e dos ganchos, porte do `ControlSocket.swift`.
//!
//! Todas com a mesma forma — `(estado, pedido, agora, mundo)` → resposta e o que
//! o ator executa —, para a tabela registrar sem adaptar. O casamento (a linha
//! do Swift) vai no comentário de cada uma; quem casa é o runtime, nesta ordem
//! relativa: `targets`, `conversation`, (permissões), `activity`, `retry`,
//! `message`, (maestro), …, `peers`, …, `dispatch`.

use std::time::SystemTime;

use serde_json::{Value, json};

use super::coordination::{Coordination, Links, Outward, World};
use super::marker::HookEvent;
use super::request::DispatchRequest;
use super::target::Hook;
use crate::protocol::handler::{RouteReply, RouteRequest};

pub type Handled = (RouteReply, Vec<Outward>);

pub const NOT_FROM_TERMINAL: &str = "esta conexão não veio de um terminal";

pub(crate) fn plain(reply: RouteReply) -> Handled {
    (reply, Vec::new())
}

/// `GET …/targets` — `ControlSocket.swift:205` (`bare.hasSuffix("/targets")`).
pub fn targets(
    state: &mut Coordination,
    _: &RouteRequest,
    _: SystemTime,
    _: &dyn World,
) -> Handled {
    let all = state.dispatcher.active_addresses();
    plain(RouteReply::ok(json!({"targets": all, "all": all})))
}

/// `POST` com `/conversation` ou `/session` no alvo — `ControlSocket.swift:213`.
/// `?target=&id=<uuid>[&transcript=][&noturn=1]`: o CLI dizendo qual conversa
/// está aberta. `noturn` é o `/clear`: conversa nova sem turno nenhum.
pub fn conversation(
    state: &mut Coordination,
    req: &RouteRequest,
    now: SystemTime,
    world: &dyn World,
) -> Handled {
    let id = req.param("id").unwrap_or_default();
    if id.is_empty() {
        return plain(RouteReply::err(400, "id é obrigatório"));
    }
    let Some(address) = state.hook_caller(req.origin.as_deref(), req.param("target")) else {
        return plain(RouteReply::with_status(
            403,
            json!({"ok": false, "error": NOT_FROM_TERMINAL}),
        ));
    };
    let mut out = vec![Outward::Conversation {
        address: address.clone(),
        id: id.to_owned(),
        transcript: req.param("transcript").map(str::to_owned),
    }];
    if req.param("noturn").is_none() {
        out.extend(
            state
                .hook(&address, Hook::new(HookEvent::Prompt), now, world)
                .unwrap_or_default(),
        );
    }
    (RouteReply::ok(json!({"ok": true})), out)
}

/// `POST` com `/activity` no alvo — `ControlSocket.swift:334`.
/// `?event=stop|prompt|ask|start|failure[&transcript=][&bg=][&bgw=][&bgd=][&last=][&error=][&detail=]`.
pub fn activity(
    state: &mut Coordination,
    req: &RouteRequest,
    now: SystemTime,
    world: &dyn World,
) -> Handled {
    let raw = req.param("event").unwrap_or_default();
    if raw.is_empty() {
        return plain(RouteReply::err(400, "event é obrigatório"));
    }
    let Some(event) = HookEvent::parse(raw) else {
        return plain(RouteReply::err(
            400,
            format!("evento desconhecido '{raw}'; use {}", HookEvent::expected()),
        ));
    };
    let Some(address) = state.hook_caller(req.origin.as_deref(), req.param("target")) else {
        return plain(RouteReply::err(403, NOT_FROM_TERMINAL));
    };
    let out = state
        .hook(&address, Hook::from_query(event, &req.query), now, world)
        .unwrap_or_default();
    (RouteReply::ok(json!({"ok": true})), out)
}

/// `POST` com `/retry` no alvo — `ControlSocket.swift:363`. `?target=&now=1`
/// tenta já; sem `now`, cancela a tentativa agendada (ADR-072).
pub fn retry(
    state: &mut Coordination,
    req: &RouteRequest,
    now: SystemTime,
    world: &dyn World,
) -> Handled {
    let target = req.param("target").unwrap_or_default();
    match state
        .dispatcher
        .retry_control(target, req.param("now") == Some("1"), now)
    {
        Some(effects) => (
            RouteReply::ok(json!({"ok": true})),
            state.absorb(effects, now, world),
        ),
        None => plain(RouteReply::err(
            409,
            format!("nenhuma tentativa agendada em '{target}'"),
        )),
    }
}

/// `POST` com `/message` no alvo — `ControlSocket.swift:378`. `?target=`; o
/// corpo é o texto puro.
pub fn message(
    state: &mut Coordination,
    req: &RouteRequest,
    _: SystemTime,
    world: &dyn World,
) -> Handled {
    let request = DispatchRequest::from_message(req.param("target").unwrap_or_default(), &req.body);
    deliver(state, &request, req, world)
}

/// `POST …/dispatch` — `ControlSocket.swift:955` (`bare.hasSuffix("/dispatch")`,
/// o último caso antes do 404). Corpo JSON do [`DispatchRequest`].
pub fn dispatch(
    state: &mut Coordination,
    req: &RouteRequest,
    _: SystemTime,
    world: &dyn World,
) -> Handled {
    let Ok(request) = serde_json::from_slice::<DispatchRequest>(&req.body) else {
        return plain(RouteReply::err(400, "json inválido"));
    };
    deliver(state, &request, req, world)
}

/// Quem chamou sai do kernel (`origin`), não do pedido.
fn deliver(
    state: &mut Coordination,
    request: &DispatchRequest,
    req: &RouteRequest,
    world: &dyn World,
) -> Handled {
    let origin = req
        .origin
        .as_deref()
        .filter(|o| state.dispatcher.target(o).is_some());
    match state.dispatcher.dispatch(request, origin, &Links(world)) {
        Ok(detail) => plain(RouteReply::ok(json!({"ok": true, "detail": detail}))),
        Err(error) => plain(RouteReply::err(404, error.to_string())),
    }
}

/// `GET` com `/peers` no alvo — `ControlSocket.swift:646`. Quem pergunta sai
/// do processo do outro lado; de fora de um terminal, lista vazia.
pub fn peers(
    state: &mut Coordination,
    req: &RouteRequest,
    _: SystemTime,
    world: &dyn World,
) -> Handled {
    let origin = req
        .origin
        .as_deref()
        .filter(|o| state.dispatcher.target(o).is_some());
    let peers: Vec<Value> = origin
        .map(|o| state.dispatcher.peers(o, &Links(world)))
        .unwrap_or_default()
        .into_iter()
        .map(|peer| {
            let mut entry = json!({"address": peer.address, "cli": peer.cli});
            if let (Some(role), Some(map)) = (peer.role, entry.as_object_mut()) {
                map.insert("role".to_owned(), json!(role));
            }
            entry
        })
        .collect();
    plain(RouteReply::ok(json!({ "peers": peers })))
}
