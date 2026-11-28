//! "+ Nova fila" do chat (ADR-088): o `chat_new_queue` do `/ui` e o
//! `/chat?newqueue=1`, como o `createQueue` do Swift (main.swift:3154).

use serde_json::json;

use super::{Actor, ClientId};
use crate::features::edge::EdgeConfig;
use crate::features::node::model::NodeKind as ConfigKind;
use crate::features::workspace::routes::OrgEffect;
use crate::protocol::chat::ChatNewQueue;
use crate::protocol::message::{CommandKind, Reply};
use crate::protocol::org::{CreateNode, NodeKind};

impl Actor {
    pub(super) fn chat_new_queue(&mut self, client: ClientId, re: u64, c: ChatNewQueue) -> Reply {
        let Some(index) = self.org.index_of(&c.workbench) else {
            return Reply::err(re, format!("bancada desconhecida '{}'", c.workbench));
        };
        let agent = match c.agent {
            Some(agent) => {
                let is_agent = self.org.state.workbenches[index]
                    .nodes
                    .iter()
                    .any(|n| n.id == agent.as_str() && n.kind == ConfigKind::Agent);
                if !is_agent {
                    return Reply::err(re, format!("'{agent}' não é agente desta bancada"));
                }
                Some(agent.to_string())
            }
            None => self.chat_new_queue_agent(c.workbench.as_str()),
        };
        let create = CommandKind::CreateNode(CreateNode {
            workbench: c.workbench.clone(),
            kind: NodeKind::Queue,
            frame: None,
            visible: None,
            component: None,
            agent: None,
            cwd: None,
            cmd: None,
            url: None,
            form: None,
        });
        let Some(created) = self.node_command(client, re, create) else {
            return Reply::err(re, "a fila não foi criada");
        };
        let Some(queue) = created
            .data
            .get("node")
            .and_then(|n| n.as_str())
            .map(str::to_owned)
            .filter(|_| created.ok)
        else {
            return created;
        };
        // Já ligada, para funcionar sem voltar ao canvas desenhar a aresta. A
        // fila não tem porta: a aresta entra direto, sem a regra do `link`.
        if let Some(agent) = agent
            && let Some(bench) = self.org.state.workbenches.get_mut(index)
        {
            let mut edges = bench.edge_list().to_vec();
            edges.push(EdgeConfig::with_default_limit(queue.clone(), agent.clone()));
            bench.edges = Some(edges);
            crate::log!("aresta[{}]: {queue} → {agent}", bench.name);
            self.apply_org(vec![OrgEffect::PersistWorkbenches]);
        }
        Reply::with(re, &json!({"node": queue}))
    }

    /// O `/chat?newqueue=1`: o "+ Nova fila" de fora (`newQueueClicked`), com
    /// o agente em foco ou o primeiro. A resposta é o retrato do chat, como
    /// a do Swift; bancada desconhecida responde pelo próprio `/chat`.
    pub(super) fn chat_new_queue_route(
        &mut self,
        request: &crate::protocol::handler::RouteRequest,
    ) {
        let target = request.param("target").unwrap_or("");
        let Some(workbench) = self
            .org
            .state
            .workbenches
            .iter()
            .find(|b| b.name == target)
            .and_then(|b| crate::commons::ids::WorkbenchId::new(b.id.clone()).ok())
        else {
            return;
        };
        // Nenhum cliente do `/ui` espera esta resposta: o `/chat` responde.
        let reply = self.chat_new_queue(
            0,
            0,
            ChatNewQueue {
                workbench,
                agent: None,
            },
        );
        if !reply.ok {
            crate::log!("chat: nova fila em {target} falhou: {:?}", reply.error);
        }
    }
}
