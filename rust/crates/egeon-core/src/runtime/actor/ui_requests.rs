//! As rotas de tela do Swift que agora moram na UI (decisão 35): `/layout`,
//! `/sidebar`, `/geometry` e `/shot`.
//!
//! O pedido vai à UI como efeito no tópico `app`, e a resposta dela volta por
//! `ui_reply` ao cliente HTTP que esperava. Sem UI assinando, ou sem resposta
//! a tempo, a rota responde como o Swift responderia sem janela.

use std::collections::HashMap;
use std::time::Duration;

use serde_json::{Value, json};

use super::{Actor, Msg, Replier};
use crate::protocol::app::AppEffect;
use crate::protocol::handler::{RouteReply, RouteRequest};
use crate::protocol::message::{Reply, Topic};
use crate::protocol::node::UiReply;
use crate::protocol::routes::FeatureRoute;

/// Quanto o cliente HTTP espera a UI.
const UI_TIMEOUT: Duration = Duration::from_secs(5);

/// Os pedidos que estão com a UI.
#[derive(Default)]
pub(super) struct UiRequests {
    next: u64,
    waiting: HashMap<u64, (FeatureRoute, RouteRequest, Replier)>,
    /// Pedidos guardados até a UI assinar `app` pela primeira vez.
    parked: Vec<u64>,
    /// Alguma UI já assinou `app` nesta sessão.
    seen_app: bool,
}

impl Actor {
    pub(super) fn ui_route(&mut self, route: FeatureRoute, request: RouteRequest, reply: Replier) {
        if route_name(route).is_empty() {
            return super::not_ported(route, reply);
        }
        let watched = self
            .clients
            .values()
            .any(|c| c.topics.contains(&Topic::App));
        // A UI que lançou o core ainda está subindo: o pedido espera a
        // primeira assinatura de `app`, até o mesmo teto.
        let park = !watched && self.config.ui_parent && !self.ui_requests.seen_app;
        if !watched && !park {
            let _ = reply.send(compose(route, &request, &Value::Null));
            return;
        }
        self.ui_requests.next += 1;
        let id = self.ui_requests.next;
        self.ui_requests.waiting.insert(id, (route, request, reply));
        if park {
            self.ui_requests.parked.push(id);
        } else {
            self.deliver_ui_request(id);
        }
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(UI_TIMEOUT).await;
            let job = move |actor: &mut Actor| actor.ui_timeout(id);
            let _ = inbox.send(Msg::Run(Box::new(job))).await;
        });
    }

    /// A primeira UI assinou `app`: os pedidos guardados vão a ela.
    pub(super) fn ui_app_subscribed(&mut self) {
        self.ui_requests.seen_app = true;
        for id in std::mem::take(&mut self.ui_requests.parked) {
            self.deliver_ui_request(id);
        }
    }

    /// O `/shot` cria antes a pasta `shots/`, como o `createDirectory` do
    /// Swift (main.swift:1881), fora do ator; o pedido só vai à UI depois.
    fn deliver_ui_request(&mut self, id: u64) {
        let Some((route, _, _)) = self.ui_requests.waiting.get(&id) else {
            return;
        };
        if *route != FeatureRoute::Shot {
            return self.emit_ui_request(id);
        }
        let shots = self.config.paths.config("shots");
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let made = tokio::task::spawn_blocking(move || {
                std::fs::create_dir_all(&shots).map_err(|e| format!("{}: {e}", shots.display()))
            })
            .await;
            if let Ok(Err(error)) = made {
                crate::log!("ui: não criei a pasta das capturas, {error}");
            }
            let job = move |actor: &mut Actor| actor.emit_ui_request(id);
            let _ = inbox.send(Msg::Run(Box::new(job))).await;
        });
    }

    /// Pedido que já venceu não sai: o cliente HTTP já teve a resposta.
    fn emit_ui_request(&mut self, id: u64) {
        let Some((route, request, _)) = self.ui_requests.waiting.get(&id) else {
            return;
        };
        let effect = AppEffect::UiRequest {
            id,
            route: route_name(*route).to_owned(),
            params: params_of(*route, request, &self.config.paths),
        };
        self.app_effect(effect);
    }

    /// `ui_reply`: o corpo da UI vai a quem pediu. Resposta a pedido que já
    /// venceu é recusada, para a UI saber que chegou tarde.
    pub(super) fn ui_reply(&mut self, re: u64, answer: UiReply) -> Reply {
        let Some((route, request, reply)) = self.ui_requests.waiting.remove(&answer.request) else {
            return Reply::err(re, format!("pedido {} não está esperando", answer.request));
        };
        let _ = reply.send(compose(route, &request, &answer.value));
        Reply::ok(re)
    }

    fn ui_timeout(&mut self, id: u64) {
        if let Some((route, request, reply)) = self.ui_requests.waiting.remove(&id) {
            crate::log!(
                "ui: {route:?} sem resposta em {}s; respondo sem janela",
                UI_TIMEOUT.as_secs()
            );
            let _ = reply.send(compose(route, &request, &Value::Null));
        }
    }
}

fn route_name(route: FeatureRoute) -> &'static str {
    match route {
        FeatureRoute::Layout => "layout",
        FeatureRoute::Sidebar => "sidebar",
        FeatureRoute::Geometry => "geometry",
        FeatureRoute::Shot => "shot",
        _ => "",
    }
}

/// A query como veio; no `/shot`, mais o `file` onde gravar, o mesmo do
/// Swift (ControlSocket.swift:947): `<pasta de dados>/shots/<alvo com _ no
/// lugar de />.png`.
fn params_of(
    route: FeatureRoute,
    request: &RouteRequest,
    paths: &crate::commons::paths::Paths,
) -> std::collections::BTreeMap<String, String> {
    let mut params: std::collections::BTreeMap<String, String> =
        request.query.clone().into_iter().collect();
    if route == FeatureRoute::Shot {
        let target = request.param("target").unwrap_or("").replace('/', "_");
        let file = paths.config("shots").join(format!("{target}.png"));
        params.insert("file".to_owned(), file.to_string_lossy().into_owned());
    }
    params
}

/// A resposta HTTP do `ControlSocket.swift` para o valor do `AppControl`;
/// `null` é o app sem janela (o `AppControl.*` nulo).
fn compose(route: FeatureRoute, request: &RouteRequest, value: &Value) -> RouteReply {
    let param = |name: &str| request.param(name).unwrap_or("").to_owned();
    // :913/:920 — aplicado é 200 com o valor; nulo é 404 com o pedido.
    let applied = |key: &str, asked: Value| {
        let status = if value.is_null() { 404 } else { 200 };
        let shown = if value.is_null() {
            asked
        } else {
            value.clone()
        };
        RouteReply::with_status(status, json!({"ok": !value.is_null(), key: shown}))
    };
    match route {
        FeatureRoute::Layout => applied("mode", json!(param("mode"))),
        FeatureRoute::Sidebar => match request.param("tab") {
            Some(tab) => applied("tab", json!(tab)),
            None => applied("collapsed", json!(false)),
        },
        // :683 — sem canvas, o retrato é vazio.
        FeatureRoute::Geometry => match value {
            Value::Object(_) => RouteReply::ok(value.clone()),
            _ => RouteReply::ok(json!({})),
        },
        // :942 — o caminho, ou o texto do erro.
        FeatureRoute::Shot => RouteReply::ok(json!({
            "target": param("target"),
            "path": value.as_str().unwrap_or("erro: app sem canvas"),
        })),
        other => RouteReply::err(501, format!("{other:?} não é rota de tela")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::handler::RouteRequest;

    fn request(query: &[(&str, &str)]) -> RouteRequest {
        RouteRequest {
            method: "GET".into(),
            target: String::new(),
            path: String::new(),
            query: query
                .iter()
                .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
                .collect(),
            body: Vec::new(),
            origin: None,
        }
    }

    fn without_window(route: FeatureRoute, request: &RouteRequest) -> RouteReply {
        compose(route, request, &Value::Null)
    }

    #[test]
    fn com_janela_monta_a_resposta_do_swift() {
        let layout = compose(
            FeatureRoute::Layout,
            &request(&[("mode", "chat")]),
            &json!("chat"),
        );
        assert_eq!(
            (layout.status, layout.json),
            (200, json!({"ok": true, "mode": "chat"}))
        );
        let collapse = compose(
            FeatureRoute::Sidebar,
            &request(&[("collapsed", "toggle")]),
            &json!(true),
        );
        assert_eq!(
            (collapse.status, collapse.json),
            (200, json!({"ok": true, "collapsed": true}))
        );
        let geometry = compose(
            FeatureRoute::Geometry,
            &request(&[]),
            &json!({"deck/a": {"x": 1}}),
        );
        assert_eq!(geometry.json, json!({"deck/a": {"x": 1}}));
        let shot = compose(
            FeatureRoute::Shot,
            &request(&[("target", "deck/a")]),
            &json!("/tmp/deck_a.png"),
        );
        assert_eq!(
            shot.json,
            json!({"target": "deck/a", "path": "/tmp/deck_a.png"})
        );
    }

    #[test]
    fn sem_janela_responde_como_o_swift() {
        let layout = without_window(FeatureRoute::Layout, &request(&[("mode", "chat")]));
        assert_eq!(
            (layout.status, layout.json),
            (404, json!({"ok": false, "mode": "chat"}))
        );
        let tab = without_window(FeatureRoute::Sidebar, &request(&[("tab", "active")]));
        assert_eq!(
            (tab.status, tab.json),
            (404, json!({"ok": false, "tab": "active"}))
        );
        let collapse = without_window(FeatureRoute::Sidebar, &request(&[("collapsed", "1")]));
        assert_eq!(collapse.json, json!({"ok": false, "collapsed": false}));
        let geometry = without_window(FeatureRoute::Geometry, &request(&[]));
        assert_eq!((geometry.status, geometry.json), (200, json!({})));
        let shot = without_window(FeatureRoute::Shot, &request(&[("target", "deck/a")]));
        assert_eq!(
            shot.json,
            json!({"target": "deck/a", "path": "erro: app sem canvas"})
        );
    }
}
