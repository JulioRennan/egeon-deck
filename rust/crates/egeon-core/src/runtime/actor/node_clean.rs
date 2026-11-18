//! Limpar a bancada (ADR-059) e o cronômetro dela, no ator.
//!
//! A máquina é a `WorkbenchCleaner` (features): manda o `clear` de cada agente
//! pela fila do Dispatcher, ESPERA os agentes assentarem e só então arquiva o
//! chat e a trilha. O ator a mantém de pé e a avança a cada tique (`node_tick`);
//! a resposta de quem pediu (a rota, que segura a conexão, ou o comando do
//! `/ui`) sai no fim. Não é declarado ainda: depende de `chat_archive`,
//! `chat_cleared` e `trace_archive`, dos donos do chat e da trilha.

use std::collections::{BTreeMap, BTreeSet};
use std::time::SystemTime;

use serde_json::Value;

use super::{Actor, ClientId, Replier};
use crate::features::node::model::NodeKind;
use crate::features::workbench::cleaner::{
    Archived, CleanAgent, CleanResult, CleanerHost, Phase, WorkbenchCleaner, is_busy,
};
use crate::features::workbench::clock::{ClockPhase, WorkbenchClock, WorkbenchClocks};
use crate::protocol::handler::RouteReply;
use crate::protocol::message::Reply;

/// Quem espera o fim da limpeza.
pub(super) enum Waiter {
    /// A conexão HTTP da rota `/workbench/clear`.
    Route(Replier),
    /// O cliente do `/ui` que mandou `clear_workbench`.
    Client(ClientId, u64),
}

pub(super) struct Cleaning {
    cleaner: WorkbenchCleaner,
    name: String,
    waiter: Option<Waiter>,
}

/// O que a limpeza pede ao ator, emprestado só durante uma chamada.
struct Host<'a> {
    actor: &'a mut Actor,
    bench_id: String,
    now: SystemTime,
    finished: Option<CleanResult>,
}

impl CleanerHost for Host<'_> {
    fn dispatch(&mut self, agent: &CleanAgent) -> bool {
        let Some(command) = agent.command.as_deref() else {
            return false;
        };
        match self
            .actor
            .dispatch_chat_send(&self.bench_id, &agent.id, command)
        {
            Ok(()) => true,
            Err(error) => {
                crate::log!("limpar[{}]: {error}", agent.address);
                false
            }
        }
    }

    fn is_busy(&mut self, agent: &CleanAgent) -> bool {
        let target = self
            .actor
            .dispatch
            .coordination
            .dispatcher
            .target(&agent.address);
        target.is_some_and(|t| is_busy(t.activity(), t.pending()))
    }

    fn archive(&mut self) -> Archived {
        Archived {
            chat: self.actor.chat_archive(&self.bench_id, self.now),
            trace: self.actor.trace_archive(&self.bench_id, self.now),
        }
    }

    fn on_phase(&mut self, phase: Phase) {
        if let Some(label) = phase.label() {
            crate::log!("limpar[{}]: {label}", self.bench_id);
        }
    }

    fn on_finish(&mut self, result: CleanResult) {
        self.finished = Some(result);
    }
}

impl Actor {
    /// Começa a limpar a bancada `name`; a resposta sai no fim, pelo `waiter`.
    /// `Err` é a recusa imediata.
    pub(super) fn start_clean(
        &mut self,
        name: &str,
        waiter: Waiter,
    ) -> Result<(), (String, Waiter)> {
        let Some(bench) = self
            .org
            .state
            .workbenches
            .iter()
            .find(|w| w.name == name)
            .cloned()
        else {
            return Err((format!("bancada desconhecida '{name}'"), waiter));
        };
        if self.node.cleaning.contains_key(&bench.id) {
            return Err(("limpeza já em curso nesta bancada".to_owned(), waiter));
        }
        let agents: Vec<CleanAgent> = bench
            .nodes
            .iter()
            .filter(|n| n.kind == NodeKind::Agent)
            .map(|n| CleanAgent {
                id: n.id.clone(),
                address: bench.address_of(n),
                command: self.profile_of(n).and_then(|p| p.clear),
            })
            .collect();
        let mut cleaning = Cleaning {
            cleaner: WorkbenchCleaner::with_defaults(agents),
            name: bench.name.clone(),
            waiter: Some(waiter),
        };
        let now = SystemTime::now();
        let finished = self.drive(&bench.id, &mut cleaning, now, true);
        self.settle(bench.id, cleaning, finished);
        Ok(())
    }

    /// Avança a máquina um passo, com o ator emprestado ao `Host`.
    fn drive(
        &mut self,
        bench_id: &str,
        cleaning: &mut Cleaning,
        now: SystemTime,
        start: bool,
    ) -> Option<CleanResult> {
        let mut host = Host {
            actor: self,
            bench_id: bench_id.to_owned(),
            now,
            finished: None,
        };
        if start {
            cleaning.cleaner.start(now, &mut host);
        } else {
            cleaning.cleaner.tick(now, &mut host);
        }
        host.finished
    }

    /// Terminou: fecha e responde. Senão, volta ao mapa para o próximo tique.
    fn settle(&mut self, bench_id: String, cleaning: Cleaning, finished: Option<CleanResult>) {
        match finished {
            Some(result) => self.finish_clean(&bench_id, cleaning, result),
            None => {
                self.node.cleaning.insert(bench_id, cleaning);
            }
        }
    }

    fn finish_clean(&mut self, bench_id: &str, mut cleaning: Cleaning, result: CleanResult) {
        // Bancada limpa é período novo: o cronômetro recomeça junto com o chat e
        // a trilha.
        self.reset_clock(bench_id);
        // O arquivo saiu do disco; o eco local e o turno ao vivo ainda estavam
        // na memória do chat e voltariam a desenhar numa thread vazia.
        self.chat_cleared(bench_id);
        crate::log!(
            "bancada \"{}\" limpa: clear em [{}]{}{}{}",
            cleaning.name,
            result.cleared.join(", "),
            if result.skipped.is_empty() {
                String::new()
            } else {
                format!(", pulados [{}]", result.skipped.join(", "))
            },
            result.chat.as_ref().map_or_else(
                || ", chat já vazio".to_owned(),
                |p| format!(", chat arquivado em {}", file_name(p))
            ),
            result.trace.as_ref().map_or_else(
                || ", trilha vazia".to_owned(),
                |p| format!(", trilha arquivada em {}", file_name(p))
            ),
        );
        let mut payload = result.payload();
        payload["workbench"] = Value::String(cleaning.name.clone());
        let ok = payload["ok"].as_bool().unwrap_or(false);
        match cleaning.waiter.take() {
            Some(Waiter::Route(reply)) => {
                let _ = reply.send(RouteReply::with_status(if ok { 200 } else { 404 }, payload));
            }
            Some(Waiter::Client(client, re)) => {
                self.send_reply(client, &Reply::with(re, &payload));
            }
            None => {}
        }
    }

    /// O relógio do limpar e o do cronômetro.
    pub(super) fn node_tick(&mut self, now: SystemTime) {
        let ids: Vec<String> = self.node.cleaning.keys().cloned().collect();
        for id in ids {
            let Some(mut cleaning) = self.node.cleaning.remove(&id) else {
                continue;
            };
            let finished = self.drive(&id, &mut cleaning, now, false);
            self.settle(id, cleaning, finished);
        }
        self.tick_clocks(now);
    }

    pub(super) fn clocks(&mut self) -> &mut WorkbenchClocks {
        let dir = self.config.paths.workbenches_dir();
        self.node
            .clocks
            .get_or_insert_with(|| WorkbenchClocks::new(dir))
    }

    /// Soma o tempo desde o tique anterior a cada fase em curso de cada bancada
    /// (ADR-074): uma bancada parada, ou sem terminais de pé, não anda.
    fn tick_clocks(&mut self, now: SystemTime) {
        let mut phases: BTreeMap<String, BTreeSet<ClockPhase>> = BTreeMap::new();
        for bench in &self.org.state.workbenches {
            if !self.org.live.contains(&bench.id) {
                continue;
            }
            let summary = self
                .dispatch
                .coordination
                .dispatcher
                .activity_summary()
                .get(&bench.name)
                .copied()
                .unwrap_or_default();
            phases.insert(bench.id.clone(), WorkbenchClock::phases(&summary));
        }
        if let Err(error) = self.clocks().tick(&phases, now) {
            crate::log!("cronômetro: não gravei — {error}");
        }
    }

    fn reset_clock(&mut self, bench_id: &str) {
        if let Err(error) = self.clocks().reset(bench_id, SystemTime::now()) {
            crate::log!("cronômetro: não gravei — {error}");
        }
    }

    /// O cronômetro de uma bancada, para o tópico.
    pub(super) fn clock_of(&mut self, bench_id: &str) -> WorkbenchClock {
        self.clocks().clock(bench_id)
    }

    /// Grava o que mudou no cronômetro, no encerramento.
    pub(super) fn flush_clocks(&mut self) {
        if self.node.clocks.is_some()
            && let Err(error) = self.clocks().flush(SystemTime::now())
        {
            crate::log!("cronômetro: não gravei — {error}");
        }
    }
}

fn file_name(path: &std::path::Path) -> String {
    path.file_name()
        .map_or_else(String::new, |n| n.to_string_lossy().into_owned())
}

impl Actor {
    /// O comando `clear_workbench` do `/ui`: a resposta sai quando a limpeza
    /// termina.
    pub(super) fn clear_workbench_command(
        &mut self,
        client: ClientId,
        re: u64,
        name: &str,
    ) -> Option<Reply> {
        match self.start_clean(name, Waiter::Client(client, re)) {
            Ok(()) => None,
            Err((error, _)) => Some(Reply::err(re, error)),
        }
    }

    /// `POST /workbench/clear?target=<bancada>`: a conexão fica parada até o
    /// fim — responder no disparo devolvia "ok" antes de a conversa ter saído
    /// do lugar.
    pub(super) fn clear_workbench_route(&mut self, target: &str, reply: Replier) {
        if let Err((error, Waiter::Route(reply))) = self.start_clean(target, Waiter::Route(reply)) {
            let _ = reply.send(RouteReply::with_status(
                404,
                serde_json::json!({"ok": false, "error": error}),
            ));
        }
    }
}
