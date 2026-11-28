//! As rotas do maestro, porte do `ControlSocket.swift:391` — o caso
//! `bare.hasPrefix("/maestro/")`, que vem depois de `/message` e antes de
//! `/trace`. Sem "permission" no nome: os casos do gancho casam pelo sufixo.
//!
//! `GET /maestro?target=&on=` (ligar o maestro de fora) é do formulário do nó,
//! não daqui.

use std::time::SystemTime;

use super::controller::{self, MaestroEffect, MaestroWiring, Reply};
use crate::features::dispatch::coordination::{Coordination, Outward, World};
use crate::features::dispatch::routes::Handled;
use crate::features::permission::model::PermissionAnswer;
use crate::protocol::handler::{RouteReply, RouteRequest};

/// `/maestro/asks` · `POST /maestro/answer?id=&answer=` · `GET /maestro/bench` ·
/// `GET /maestro/models` · `POST /maestro/apply[?dry=1]`. Quem pergunta é o
/// `origin`; o controller recusa quem não é maestro.
pub fn maestro(
    state: &mut Coordination,
    req: &RouteRequest,
    now: SystemTime,
    world: &dyn World,
    wiring: &dyn MaestroWiring,
) -> Handled {
    let bare = req.path.as_str();
    let caller = req
        .origin
        .as_deref()
        .filter(|o| state.dispatcher.target(o).is_some());
    let reply = if bare.ends_with("/asks") {
        controller::permissions(wiring, caller, &mut state.desk, now)
    } else if req.method == "POST" && bare.ends_with("/answer") {
        match (
            req.param("id"),
            req.param("answer").and_then(PermissionAnswer::parse),
        ) {
            (Some(id), Some(answer)) => {
                controller::answer_permission(wiring, id, answer, caller, &mut state.desk, now)
            }
            _ => return plain(400, "use ?id=<pedido>&answer=allow|always|deny"),
        }
    } else {
        match req.method.as_str() {
            "GET" if bare.ends_with("/bench") => controller::bench(wiring, caller),
            "GET" if bare.ends_with("/models") => controller::models(wiring, caller),
            "POST" if bare.ends_with("/apply") => {
                controller::apply(wiring, &req.body, caller, req.param("dry") == Some("1"))
            }
            _ => {
                return plain(
                    404,
                    "use GET /maestro/bench, GET /maestro/models ou POST /maestro/apply[?dry=1]",
                );
            }
        }
    };
    let Reply {
        status,
        json,
        effects,
    } = reply;
    let mut out = Vec::new();
    for effect in effects {
        match effect {
            MaestroEffect::PermissionAnswered { address } => {
                out.extend(state.answered(&address, now, world));
            }
            other => out.push(Outward::Maestro(other)),
        }
    }
    (RouteReply::with_status(status, json), out)
}

fn plain(status: u16, message: &str) -> Handled {
    (RouteReply::err(status, message), Vec::new())
}
