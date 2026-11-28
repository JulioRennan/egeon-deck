//! Dono: `cli`. Liga ao ator a trilha e a rota /trace.
//!
//! O ator só copia o que sabe do nó que chamou (a bancada e a configuração
//! dele); a identidade — nome do CLI, modelo literal do transcript — e a
//! gravação em disco bloqueiam e saem por `spawn_blocking`. A trilha não tem
//! estado no ator: a resposta sai de lá mesmo.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::SystemTime;

use super::dispatch_commands::literal_model;
use super::{Actor, Replier, not_ported};
use crate::commons::clock::local_offset_secs;
use crate::features::agent::model::AgentProfile;
use crate::features::node::model::NodeConfig;
use crate::features::trace::routes::{NodeIdentities, NodeIdentity, TraceRoutes, trace};
use crate::features::trace::store::{OffsetAt, TraceLog};
use crate::protocol::handler::{RouteReply, RouteRequest};
use crate::protocol::routes::FeatureRoute;

/// O estado da trilha dentro do ator. Nenhum por enquanto: a identidade é
/// lida na hora, do `Org`.
#[derive(Default)]
pub(super) struct TraceState {}

/// O que o ator sabe de um nó e a rota precisa para carimbá-lo.
struct NodeFacts {
    workbench_id: String,
    node: NodeConfig,
    /// O perfil do agente do nó, se ele tem um e o `agents.json` o conhece.
    profile: Option<AgentProfile>,
}

/// A identidade do nó que chamou, já calculada: o trait é de uma pergunta só.
/// `None` quando o nó não tem bancada carregada.
struct Prepared {
    address: String,
    identity: Option<NodeIdentity>,
}

impl NodeIdentities for Prepared {
    fn identity(&self, address: &str) -> Option<NodeIdentity> {
        (address == self.address)
            .then(|| self.identity.clone())
            .flatten()
    }
}

impl Actor {
    pub(super) fn trace_route(
        &mut self,
        route: FeatureRoute,
        request: RouteRequest,
        reply: Replier,
    ) {
        if route != FeatureRoute::Trace {
            return not_ported(route, reply);
        }
        // O `Dispatcher.target(callingOn:)` vem antes de qualquer outra coisa:
        // sem terminal de origem a rota responde 403 sem procurar nó nenhum.
        let facts = request
            .origin
            .as_deref()
            .and_then(|address| self.node_facts(address));
        let workbenches = self.config.paths.workbenches_dir();
        let user_home = std::path::PathBuf::from(&self.org.home);
        tokio::spawn(async move {
            let done = tokio::task::spawn_blocking(move || {
                // A hora local de CADA data, com o horário de verão dela, como o
                // `DateFormatter` do Swift.
                let offset: OffsetAt = Arc::new(local_offset_secs);
                let origin = request.origin.clone().unwrap_or_default();
                let identity = facts.map(|f| identity_of(&f, &user_home));
                let mut state = TraceRoutes {
                    log: TraceLog::new(workbenches, offset),
                    identities: Box::new(Prepared {
                        address: origin,
                        identity,
                    }),
                };
                trace(&mut state, &request, SystemTime::now())
            })
            .await;
            let answer = done.unwrap_or_else(|_| RouteReply::err(500, "a trilha não terminou"));
            let _ = reply.send(answer);
        });
    }

    /// "Limpar a bancada" leva a trilha junto com o chat: o `trace.md` vai para
    /// `trace-archive/` e o próximo registro abre outro, com cabeçalho novo.
    /// `None` se não havia trilha. Mexe em disco (renomeia): rápido, e o org
    /// o chama no meio do limpar, que já roda fora do ator.
    pub(super) fn trace_archive(&mut self, workbench_id: &str, now: SystemTime) -> Option<PathBuf> {
        let log = TraceLog::new(
            self.config.paths.workbenches_dir(),
            Arc::new(local_offset_secs),
        );
        log.archive(workbench_id, now)
    }

    /// A bancada e o nó de `bancada/nó`, como o `nodeIdentity` do Swift: pelo
    /// nome da bancada e o id do nó.
    fn node_facts(&self, address: &str) -> Option<NodeFacts> {
        let (bench, node) = address.split_once('/')?;
        let workbench = self
            .org
            .state
            .workbenches
            .iter()
            .find(|w| w.name == bench)?;
        let node = workbench.nodes.iter().find(|n| n.id == node)?.clone();
        let profile = node
            .agent
            .as_ref()
            .and_then(|key| self.org.profiles.get(key))
            .cloned();
        Some(NodeFacts {
            workbench_id: workbench.id.clone(),
            node,
            profile,
        })
    }
}

/// `AppControl.nodeIdentity` do Swift: o CLI pelo nome do perfil (ou a chave),
/// o modelo literal e a conversa do nó. Lê o fim do transcript: bloqueia.
fn identity_of(facts: &NodeFacts, user_home: &Path) -> NodeIdentity {
    let node = &facts.node;
    let profile = facts.profile.as_ref();
    NodeIdentity {
        workbench_id: facts.workbench_id.clone(),
        cli: profile
            .map(|p| p.display_name.clone())
            .or_else(|| node.agent.clone()),
        model: literal_model(node, profile, user_home),
        conversation: node.conversation_id.clone(),
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::super::processes_commands::support::{Rig, request};
    use crate::features::agent::model::AgentProfile;
    use crate::features::node::model::{NodeConfig, NodeKind};
    use crate::features::workbench::model::WorkbenchConfig;
    use crate::protocol::routes::FeatureRoute;

    /// A bancada "deck" com o agente "revisor" (CLI "Claude Code", conversa
    /// conhecida) e um terminal comum "sh".
    fn rig_with_deck() -> (Rig, String) {
        let mut rig = Rig::new();
        let mut agent = NodeConfig::new(NodeKind::Agent, "revisor");
        agent.agent = Some("claude".into());
        agent.conversation_id = Some("3C0C394C-E0A8-46FD".into());
        let shell = NodeConfig::new(NodeKind::Shell, "sh");
        let bench = WorkbenchConfig::new("deck", "/tmp/deck", vec![agent, shell]);
        let id = bench.id.clone();
        rig.actor.org.state.workbenches.push(bench);
        rig.actor.org.profiles.insert(
            "claude".into(),
            AgentProfile::new("Claude Code", &["claude"]),
        );
        (rig, id)
    }

    async fn post(rig: &mut Rig, origin: Option<&str>, text: &str) -> (u16, serde_json::Value) {
        let mut req = request("POST", "/trace", origin);
        req.body = text.as_bytes().to_vec();
        let reply = rig.call(FeatureRoute::Trace, req).await;
        (reply.status, reply.json)
    }

    #[tokio::test]
    async fn so_terminal_escreve_e_o_no_precisa_existir() {
        let (mut rig, _) = rig_with_deck();
        let (status, body) = post(&mut rig, None, "fiz").await;
        assert_eq!(status, 403);
        assert_eq!(body["error"], "esta conexão não veio de um terminal");
        let (status, body) = post(&mut rig, Some("deck/revisor"), "  \n ").await;
        assert_eq!(
            (status, body["error"].as_str()),
            (400, Some("texto vazio — o que você fez?"))
        );
        let (status, body) = post(&mut rig, Some("deck/fantasma"), "fiz").await;
        assert_eq!(
            (status, body["error"].as_str()),
            (404, Some("nó sem bancada carregada"))
        );
        let (status, _) = post(&mut rig, Some("outra/revisor"), "fiz").await;
        assert_eq!(status, 404);
    }

    #[tokio::test]
    async fn grava_na_trilha_da_bancada_com_o_carimbo_do_no() {
        let (mut rig, id) = rig_with_deck();
        let (status, body) = post(&mut rig, Some("deck/revisor"), "pedido: x — entrega: y\n").await;
        assert_eq!(status, 200);
        let file = rig.data.join("workbenches").join(&id).join("trace.md");
        assert_eq!(
            body,
            json!({"ok": true, "address": "deck/revisor", "file": file.to_string_lossy()})
        );
        let text = std::fs::read_to_string(&file).unwrap();
        assert!(
            text.starts_with(&format!("# deck\nbancada `{id}`\n")),
            "{text}"
        );
        assert!(
            text.contains(" · revisor\nClaude Code · conversa 3C0C394C\n"),
            "{text}"
        );
        assert!(text.ends_with("\n\npedido: x — entrega: y\n\n"));

        // O terminal comum também registra, sem carimbo de CLI nem conversa.
        post(&mut rig, Some("deck/sh"), "ls").await;
        let text = std::fs::read_to_string(&file).unwrap();
        assert!(text.contains(" · sh\n\nls\n\n"), "{text}");
        assert_eq!(text.matches("# deck\n").count(), 1, "cabeçalho uma vez só");
    }

    #[tokio::test]
    async fn o_modelo_vem_do_transcript_e_so_sem_modelo_escolhido_do_padrao() {
        let (mut rig, id) = rig_with_deck();
        let transcript = rig.dir.path().join("t.jsonl");
        std::fs::write(
            &transcript,
            r#"{"type":"assistant","message":{"model":"claude-haiku-4-5","content":[]}}"#
                .to_owned()
                + "\n",
        )
        .unwrap();
        rig.actor.org.state.workbenches[0].nodes[0].transcript =
            Some(transcript.to_string_lossy().into_owned());
        // Com modelo pedido, o transcript ainda manda.
        rig.actor.org.state.workbenches[0].nodes[0].model = Some("haiku".into());
        post(&mut rig, Some("deck/revisor"), "fiz").await;
        let file = rig.data.join("workbenches").join(&id).join("trace.md");
        let text = std::fs::read_to_string(&file).unwrap();
        assert!(
            text.contains("Claude Code · claude-haiku-4-5 · conversa 3C0C394C\n"),
            "{text}"
        );

        // Sem transcript e com modelo escolhido: sem modelo no carimbo (o
        // `settings.json` diria o que o CLI usaria sem a flag).
        rig.actor.org.state.workbenches[0].nodes[0].transcript = None;
        post(&mut rig, Some("deck/revisor"), "de novo").await;
        let text = std::fs::read_to_string(&file).unwrap();
        assert!(
            text.contains("\nClaude Code · conversa 3C0C394C\n\nde novo\n"),
            "{text}"
        );
    }

    #[tokio::test]
    async fn arquivar_leva_a_trilha_e_o_proximo_registro_abre_outra() {
        let (mut rig, id) = rig_with_deck();
        assert!(
            rig.actor
                .trace_archive(&id, std::time::SystemTime::now())
                .is_none()
        );
        post(&mut rig, Some("deck/revisor"), "primeiro").await;
        let current = rig.data.join("workbenches").join(&id).join("trace.md");
        let archived = rig
            .actor
            .trace_archive(&id, std::time::SystemTime::now())
            .expect("havia trilha");
        assert!(!current.exists());
        assert_eq!(
            archived.parent().unwrap(),
            current.parent().unwrap().join("trace-archive")
        );
        assert!(
            std::fs::read_to_string(&archived)
                .unwrap()
                .contains("primeiro")
        );

        post(&mut rig, Some("deck/revisor"), "segundo").await;
        let fresh = std::fs::read_to_string(&current).unwrap();
        assert!(fresh.starts_with("# deck\n"), "{fresh}");
        assert!(!fresh.contains("primeiro"));
    }
}
