//! Dono: `app`. Itens do menu do app que só leem o estado do core.
//!
//! Comandos do `/ui` que chegam aqui: copy_targets.

use serde_json::json;

use super::Actor;
use crate::protocol::message::Reply;

impl Actor {
    /// "Copiar alvos de dispatch" (`copyTargets`): os endereços vivos, um por
    /// linha. Quem escreve na área de transferência é a UI.
    pub(super) fn copy_targets(&mut self, re: u64) -> Reply {
        let text = self.dispatch.coordination.dispatcher.addresses().join("\n");
        crate::log!("alvos copiados:\n{text}");
        Reply::with(re, &json!({ "text": text }))
    }
}
