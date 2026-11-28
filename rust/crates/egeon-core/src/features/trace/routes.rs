//! A rota `POST /trace` (`egeon trace`). Casamento no Swift:
//! `ControlSocket.swift:441` (`case ("POST", _, _) where route.contains("/trace")`).

use std::path::PathBuf;
use std::time::SystemTime;

use serde_json::json;

use super::model::TraceEntry;
use super::store::TraceLog;
use crate::protocol::handler::{RouteReply, RouteRequest};

/// O que o nó diz de si e o app sabe: a bancada de verdade (o id, não o nome) e
/// o carimbo de CLI, modelo e conversa.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NodeIdentity {
    pub workbench_id: String,
    pub cli: Option<String>,
    pub model: Option<String>,
    pub conversation: Option<String>,
}

/// De onde sai a identidade de um nó (`AppControl.nodeIdentity` no Swift).
pub trait NodeIdentities: Send {
    /// `None` quando o nó não tem bancada carregada.
    fn identity(&self, address: &str) -> Option<NodeIdentity>;
}

/// O que a rota usa: o arquivo da trilha e as identidades.
pub struct TraceRoutes {
    pub log: TraceLog,
    pub identities: Box<dyn NodeIdentities>,
}

impl TraceRoutes {
    /// Grava uma entrada em nome de `address`, sem as checagens da rota: é o
    /// que o maestro usa para registrar na trilha. `None` se o nó não tem
    /// bancada carregada.
    pub fn record(&self, address: &str, text: &str, now: SystemTime) -> Option<PathBuf> {
        let identity = self.identities.identity(address)?;
        let entry = TraceEntry::new(address, identity.workbench_id.as_str(), now, text).stamped(
            identity.cli,
            identity.model,
            identity.conversation,
        );
        self.log.record(&entry);
        Some(self.log.file(&entry))
    }
}

/// `POST /trace` — o corpo é o texto puro (`egeon trace`, heredoc). Quem
/// escreveu sai do processo do outro lado do socket, e CLI, modelo e conversa
/// saem do nó: o agente não carimba nada (ADR-036). Escreve em disco: o core a
/// chama de `spawn_blocking`.
pub fn trace(state: &mut TraceRoutes, req: &RouteRequest, now: SystemTime) -> RouteReply {
    let text = req.text();
    let text = text.trim();
    let Some(origin) = &req.origin else {
        return RouteReply::err(403, "esta conexão não veio de um terminal");
    };
    if text.is_empty() {
        return RouteReply::err(400, "texto vazio — o que você fez?");
    }
    match state.record(origin, text, now) {
        Some(file) => RouteReply::ok(json!({
            "ok": true,
            "address": origin,
            "file": file.to_string_lossy(),
        })),
        None => RouteReply::err(404, "nó sem bancada carregada"),
    }
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, UNIX_EPOCH};

    use super::*;

    struct Known;

    impl NodeIdentities for Known {
        fn identity(&self, address: &str) -> Option<NodeIdentity> {
            (address == "deck/revisor").then(|| NodeIdentity {
                workbench_id: "aaaa1111".into(),
                cli: Some("Claude Code".into()),
                model: Some("claude-haiku-4-5".into()),
                conversation: Some("3C0C394C-E0A8".into()),
            })
        }
    }

    fn now() -> SystemTime {
        UNIX_EPOCH + Duration::from_secs(1_787_678_363)
    }

    fn state() -> (TraceRoutes, tempfile::TempDir) {
        let dir = tempfile::tempdir().unwrap();
        let routes = TraceRoutes {
            log: TraceLog::fixed(dir.path().to_owned(), 0),
            identities: Box::new(Known),
        };
        (routes, dir)
    }

    fn post(origin: Option<&str>, body: &str) -> RouteRequest {
        RouteRequest {
            method: "POST".into(),
            target: "/trace".into(),
            path: "/trace".into(),
            query: Default::default(),
            body: body.as_bytes().to_vec(),
            origin: origin.map(str::to_owned),
        }
    }

    #[test]
    fn grava_e_responde_com_o_endereco_e_o_arquivo() {
        let (mut routes, dir) = state();
        let reply = trace(
            &mut routes,
            &post(Some("deck/revisor"), "\n  pedido: x — entrega: y  \n"),
            now(),
        );
        assert_eq!(reply.status, 200);
        let file = dir.path().join("aaaa1111").join("trace.md");
        assert_eq!(
            reply.json,
            json!({"ok": true, "address": "deck/revisor", "file": file.to_string_lossy()})
        );
        let written = std::fs::read_to_string(file).unwrap();
        assert!(written.starts_with("# deck\nbancada `aaaa1111`\n"));
        assert!(written.contains(
            "## 2026-08-25 17:19 · revisor\nClaude Code · claude-haiku-4-5 · conversa 3C0C394C\n"
        ));
        assert!(written.ends_with("\n\npedido: x — entrega: y\n\n"));
    }

    #[test]
    fn so_terminal_escreve_na_trilha() {
        let (mut routes, dir) = state();
        let reply = trace(&mut routes, &post(None, "fiz"), now());
        assert_eq!(reply.status, 403);
        assert_eq!(
            reply.json,
            json!({"ok": false, "error": "esta conexão não veio de um terminal"})
        );
        assert!(!dir.path().join("aaaa1111").exists());
    }

    #[test]
    fn texto_vazio_e_no_sem_bancada_sao_recusados_nessa_ordem() {
        let (mut routes, _dir) = state();
        let empty = trace(&mut routes, &post(Some("deck/revisor"), " \n\t "), now());
        assert_eq!(empty.status, 400);
        assert_eq!(
            empty.json,
            json!({"ok": false, "error": "texto vazio — o que você fez?"})
        );
        // Texto vazio vem antes de o nó ser procurado.
        assert_eq!(
            trace(&mut routes, &post(Some("deck/outro"), ""), now()).status,
            400
        );
        let unknown = trace(&mut routes, &post(Some("deck/outro"), "fiz"), now());
        assert_eq!(unknown.status, 404);
        assert_eq!(
            unknown.json,
            json!({"ok": false, "error": "nó sem bancada carregada"})
        );
    }

    #[test]
    fn o_maestro_registra_sem_as_checagens_da_rota() {
        let (routes, dir) = state();
        assert!(routes.record("deck/outro", "x", now()).is_none());
        let file = routes
            .record("deck/revisor", "plano aplicado", now())
            .unwrap();
        assert_eq!(file, dir.path().join("aaaa1111/trace.md"));
    }
}
