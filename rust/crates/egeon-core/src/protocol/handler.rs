//! O que um handler de rota recebe e devolve. As features escrevem os
//! handlers delas como funções puras sobre estes tipos, em
//! `features/<x>/routes.rs`: `(estado da feature, &RouteRequest, agora)` →
//! [`RouteReply`], com os testes da resposta. O runtime casa a rota, na ordem
//! do `ControlSocket.swift`, e chama.

use std::collections::HashMap;

use serde_json::{Value, json};

use super::http::Request;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RouteRequest {
    pub method: String,
    /// O alvo inteiro, com a query, como veio: é nele que o Swift casa
    /// (`contains`, `hasSuffix`).
    pub target: String,
    /// O caminho sem a query.
    pub path: String,
    /// A query com a semântica do Swift (`ControlSocket.query`).
    pub query: HashMap<String, String>,
    pub body: Vec<u8>,
    /// O endereço (`bancada/nó`) do terminal de onde a conexão partiu,
    /// resolvido pelo pid do par. `None` é você: o chat, um `curl`, um teste.
    pub origin: Option<String>,
}

impl RouteRequest {
    pub fn from_http(request: &Request, origin: Option<String>) -> Self {
        Self {
            method: request.method.clone(),
            target: request.target.clone(),
            path: request.path().to_owned(),
            query: request.query(),
            body: request.body.clone(),
            origin,
        }
    }

    pub fn param(&self, name: &str) -> Option<&str> {
        self.query.get(name).map(String::as_str)
    }

    /// O corpo como texto: o Swift lê com `String(decoding:as:)`, que troca
    /// o que não é UTF-8 em vez de recusar.
    pub fn text(&self) -> String {
        String::from_utf8_lossy(&self.body).into_owned()
    }
}

/// Status e corpo JSON da resposta, iguais aos do Swift.
#[derive(Debug, Clone, PartialEq)]
pub struct RouteReply {
    pub status: u16,
    pub json: Value,
}

impl RouteReply {
    pub fn ok(json: Value) -> Self {
        Self { status: 200, json }
    }

    pub fn with_status(status: u16, json: Value) -> Self {
        Self { status, json }
    }

    /// O erro de sempre: `{"ok": false, "error": …}`.
    pub fn err(status: u16, error: impl Into<String>) -> Self {
        Self {
            status,
            json: json!({"ok": false, "error": error.into()}),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::protocol::http::{Parsed, parse_request};

    #[test]
    fn requisicao_traz_alvo_caminho_query_e_corpo() {
        let raw = b"POST /message?target=deck%2Fclaude HTTP/1.1\r\nContent-Length: 3\r\n\r\noi\xff";
        let Parsed::Complete { request, .. } = parse_request(raw, false).unwrap() else {
            panic!("incompleta");
        };
        let req = RouteRequest::from_http(&request, Some("deck/rev".into()));
        assert_eq!(req.method, "POST");
        assert_eq!(req.target, "/message?target=deck%2Fclaude");
        assert_eq!(req.path, "/message");
        assert_eq!(req.param("target"), Some("deck/claude"));
        assert_eq!(req.text(), "oi\u{fffd}");
        assert_eq!(req.origin.as_deref(), Some("deck/rev"));
    }

    #[test]
    fn erro_no_formato_de_hoje() {
        let reply = RouteReply::err(404, "alvo desconhecido 'x'");
        assert_eq!(reply.status, 404);
        assert_eq!(
            reply.json,
            json!({"ok": false, "error": "alvo desconhecido 'x'"})
        );
    }
}
