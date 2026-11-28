//! Os pedidos de permissão abertos e a resposta que o gancho vem buscar
//! (ADR-068). Porte de `PermissionDesk.swift`: só em memória, com o relógio
//! como parâmetro.
//!
//! O diálogo do CLI continua na tela enquanto o gancho espera, e responder lá
//! também vale. O pedido tem três fins: resposta daqui, resposta no terminal
//! (você teclou nele; o gancho sai calado) ou turno que seguiu.

use std::collections::HashMap;
use std::time::{Duration, SystemTime};

use serde_json::{Value, json};

use super::model::{PermissionAnswer, PermissionAsk};
use crate::features::agent::claude::hooks::PERMISSION_WAIT;
use crate::log;

/// Quanto o gancho espera (`ClaudeHooks.permissionWait`): pedido mais velho
/// não tem quem leve a resposta, e clicar nele seria aprovar nada.
pub const LIFETIME: Duration = Duration::from_secs(PERMISSION_WAIT as u64);

#[derive(Debug, Clone, PartialEq)]
pub enum PermissionState {
    Pending,
    Answered(PermissionAnswer),
    /// Respondido em outro lugar, ou o pedido nunca existiu.
    Gone,
}

#[derive(Debug, Default)]
pub struct PermissionDesk {
    asks: Vec<PermissionAsk>,
    answers: HashMap<String, (PermissionAnswer, Value, SystemTime)>,
    counter: u64,
}

impl PermissionDesk {
    pub fn new() -> Self {
        Self::default()
    }

    fn expire(&mut self, now: SystemTime) {
        let Some(limit) = now.checked_sub(LIFETIME) else {
            return;
        };
        self.asks.retain(|a| a.opened_at >= limit);
        self.answers.retain(|_, (_, _, at)| *at >= limit);
    }

    /// Os pedidos ainda respondíveis, na ordem em que abriram.
    pub fn open(&mut self, now: SystemTime) -> &[PermissionAsk] {
        self.expire(now);
        &self.asks
    }

    /// Abre um pedido. Vários do mesmo terminal convivem: ferramentas em
    /// paralelo disparam um gancho cada. `None` sem `tool_name`.
    pub fn open_ask(
        &mut self,
        address: &str,
        payload: &Value,
        now: SystemTime,
    ) -> Option<PermissionAsk> {
        self.counter += 1;
        let ms = now
            .duration_since(SystemTime::UNIX_EPOCH)
            .map(|d| d.as_secs_f64() * 1000.0)
            .unwrap_or(0.0);
        let id = format!("p{}-{ms:.0}", self.counter);
        let ask = PermissionAsk::from_payload(id.clone(), address, payload, now)?;
        let summary: String = ask.summary.chars().take(120).collect();
        log!(
            "permissão[{address}]: aberta {id} — {}: {summary}",
            ask.tool
        );
        self.asks.push(ask.clone());
        Some(ask)
    }

    pub fn state(&mut self, id: &str, now: SystemTime) -> PermissionState {
        self.expire(now);
        if let Some((answer, _, _)) = self.answers.get(id) {
            return PermissionState::Answered(*answer);
        }
        if self.asks.iter().any(|a| a.id == id) {
            PermissionState::Pending
        } else {
            PermissionState::Gone
        }
    }

    /// A saída que o gancho imprime. Lida uma vez: entregue, o pedido acaba.
    pub fn take_output(&mut self, id: &str) -> Option<Value> {
        self.answers.remove(id).map(|(_, output, _)| output)
    }

    /// O `GET /permission?id=`: `answered` leva a saída pronta para o gancho
    /// imprimir; `gone` é "acabou em outro lugar, saia calado".
    pub fn poll(&mut self, id: &str, now: SystemTime) -> Value {
        match self.state(id, now) {
            PermissionState::Pending => json!({"state": "pending"}),
            PermissionState::Gone => json!({"state": "gone"}),
            PermissionState::Answered(_) => json!({
                "state": "answered",
                "output": self.take_output(id).unwrap_or_else(|| json!({})),
            }),
        }
    }

    /// Você respondeu daqui. `false` se o pedido já tinha acabado.
    pub fn answer(
        &mut self,
        id: &str,
        answer: PermissionAnswer,
        by: &str,
        now: SystemTime,
    ) -> bool {
        self.expire(now);
        let Some(index) = self.asks.iter().position(|a| a.id == id) else {
            return false;
        };
        let ask = self.asks.remove(index);
        self.answers.insert(
            id.to_owned(),
            (answer, answer.hook_output(&ask.suggestions), now),
        );
        log!(
            "permissão[{}]: {} {by} — {id}",
            ask.address,
            answer.as_str()
        );
        true
    }

    /// As perguntas do `AskUserQuestion` respondidas daqui. `false` se o
    /// pedido acabou ou se as escolhas não fecham com as perguntas.
    pub fn answer_choices(
        &mut self,
        id: &str,
        choices: &HashMap<String, Vec<String>>,
        now: SystemTime,
    ) -> bool {
        self.expire(now);
        let Some(index) = self
            .asks
            .iter()
            .position(|a| a.id == id && a.accepts(choices))
        else {
            return false;
        };
        let ask = self.asks.remove(index);
        self.answers.insert(
            id.to_owned(),
            (PermissionAnswer::Allow, ask.answer_output(choices), now),
        );
        log!(
            "permissão[{}]: pergunta respondida pelo chat — {id}",
            ask.address
        );
        true
    }

    /// `choice=<opção>` na rota: vale para a primeira pergunta do pedido.
    pub fn first_question_choice(
        &mut self,
        id: &str,
        choice: &str,
        now: SystemTime,
    ) -> Option<HashMap<String, Vec<String>>> {
        let ask = self.open(now).iter().find(|a| a.id == id)?;
        let question = ask.questions().into_iter().next()?;
        Some(HashMap::from([(
            question.question,
            vec![choice.to_owned()],
        )]))
    }

    /// O pedido deste terminal acabou fora daqui.
    pub fn drop(&mut self, address: &str, why: Option<&str>) {
        let before = self.asks.len();
        self.asks.retain(|a| a.address != address);
        if self.asks.len() != before
            && let Some(why) = why
        {
            log!("permissão[{address}]: fechada — {why}");
        }
    }

    pub fn pending_in_workbench(&mut self, name: &str, now: SystemTime) -> Vec<PermissionAsk> {
        let prefix = format!("{name}/");
        self.open(now)
            .iter()
            .filter(|a| a.address.starts_with(&prefix))
            .cloned()
            .collect()
    }

    /// Os pedidos respondíveis da bancada `name`, sem mexer na mesa: para quem
    /// só lê (a bandeja do chat), na ordem em que abriram.
    pub fn pending_at(&self, name: &str, now: SystemTime) -> Vec<&PermissionAsk> {
        let prefix = format!("{name}/");
        let limit = now.checked_sub(LIFETIME);
        self.asks
            .iter()
            .filter(|a| a.address.starts_with(&prefix))
            .filter(|a| limit.is_none_or(|l| a.opened_at >= l))
            .collect()
    }

    /// O resumo do último pedido aberto deste terminal: o detalhe da
    /// notificação de "precisa de você".
    pub fn last_summary(&mut self, address: &str, now: SystemTime) -> Option<String> {
        self.open(now)
            .iter()
            .rev()
            .find(|a| a.address == address)
            .map(|a| a.summary.clone())
    }

    /// O endereço mudou com a bancada renomeada.
    pub fn renamed(&mut self, old: &str, new: &str) {
        for ask in &mut self.asks {
            if ask.address == old {
                new.clone_into(&mut ask.address);
            }
        }
    }

    /// O `GET /permissions`.
    pub fn listing(&mut self, now: SystemTime) -> Value {
        let open: Vec<Value> = self
            .open(now)
            .iter()
            .map(|ask| {
                let questions: Vec<Value> = ask
                    .questions()
                    .into_iter()
                    .map(|q| {
                        json!({"question": q.question, "options": q.options,
                            "multiSelect": q.multi_select})
                    })
                    .collect();
                json!({
                    "id": ask.id, "address": ask.address, "tool": ask.tool,
                    "summary": ask.summary, "detail": ask.detail.clone().unwrap_or_default(),
                    "always": ask.can_always_allow(), "questions": questions,
                })
            })
            .collect();
        json!({ "open": open })
    }
}
