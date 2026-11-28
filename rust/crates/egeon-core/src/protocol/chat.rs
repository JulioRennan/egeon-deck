//! O chat de uma bancada no `/ui` (decisão 29): o tópico `chat/<wb id>` e os
//! comandos do composer, dos passos e da bandeja de permissão.
//!
//! O evento do tópico é o `ChatUpdate` de `features::chat::view`
//! (`{topic, workbench, rev, ops}`), com o diff de blocos por id. Na
//! assinatura e em `rev` perdido vem um `reset`; `chat_snapshot` devolve o
//! retrato inteiro a quem preferir pedir.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use crate::commons::ids::{NodeId, WorkbenchId};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatRef {
    pub workbench: WorkbenchId,
}

/// "+ Nova fila" (ADR-088): cria o nó de fila já ligado a `agent` (o
/// participante em foco na UI); sem ele, ao primeiro agente; bancada sem
/// agente ganha a fila solta, como o `createQueue` do Swift. Resposta:
/// `{node}`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatNewQueue {
    pub workbench: WorkbenchId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent: Option<crate::commons::ids::NodeId>,
}

/// Abre ou fecha um passo, ou sobe o nível de uma capa: o `/chat?expand=` do
/// Swift.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatStep {
    pub workbench: WorkbenchId,
    pub block: String,
}

/// O composer: `to` são os agentes que recebem, e `quote` cita uma mensagem
/// pelo `messageKey`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatSend {
    pub workbench: WorkbenchId,
    pub to: Vec<NodeId>,
    pub text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub quote: Option<String>,
}

/// O menu do composer: o core acha o gatilho (`@` ou `/`) antes do cursor e
/// responde `{items:[{label,insert,detail?,kind}], range:[ini,fim]}`. O
/// `caret` conta em UTF-16, como o campo de texto da UI. `to` escolhe de qual
/// agente vem a lista de `/`; `search` é a busca dessa lista.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatComplete {
    pub workbench: WorkbenchId,
    pub text: String,
    pub caret: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub to: Option<NodeId>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub search: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PermissionChoice {
    Allow,
    Always,
    Deny,
}

/// Os botões da bandeja, como o `/permission/answer` do Swift: `answer`;
/// `choice` quando o pedido traz opções (a pergunta do agente); ou `answers`
/// quando o AskUserQuestion faz mais de uma pergunta (`{pergunta: [opções]}`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PermissionAnswer {
    pub workbench: WorkbenchId,
    pub request: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub answer: Option<PermissionChoice>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub choice: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub answers: Option<BTreeMap<String, Vec<String>>>,
}
