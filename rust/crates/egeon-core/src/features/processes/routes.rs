//! As rotas dos processos e dos apps abertos. Casamento no Swift, em
//! `ControlSocket.swift` (todas sobre `bare`, o caminho sem a query, com
//! `hasSuffix`):
//! - `:602` `case ("GET", _, _) where bare.hasSuffix("/apps")`
//! - `:606` `case ("POST", _, _) where bare.hasSuffix("/processes/reap")`
//! - `:615` `case ("POST", _, _) where bare.hasSuffix("/processes/kill")`
//! - `:625` `case ("GET", _, _) where bare.hasSuffix("/processes")`
//!
//! Nenhuma casa com a outra (`/processes/reap` não termina em `/processes`),
//! mas o core as registra na ordem do Swift.
//!
//! Tudo aqui, menos `/apps`, lê o kernel ou manda sinal: o core chama de
//! `spawn_blocking`.

use std::collections::HashSet;
use std::time::SystemTime;

use serde_json::{Value, json};

use super::keeper::AppKeeper;
use super::model::ReapPolicy;
use super::reaper::reap;
use super::scanner::{ProcessScanner, ScanContext};
use crate::ports::procs::ProcessDriver;
use crate::protocol::handler::{RouteReply, RouteRequest};

/// O que as rotas que lêem o kernel precisam, sem estado nenhum: assim o core
/// as leva para fora do ator (`spawn_blocking`) sem tirar nada de lá.
pub struct ProcessEnv<'a> {
    pub procs: &'a dyn ProcessDriver,
    pub context: &'a ScanContext,
}

impl<'a> ProcessEnv<'a> {
    fn scanner(&self) -> ProcessScanner<'a> {
        ProcessScanner::new(self.procs, self.context)
    }
}

/// O que a rota `/processes` pede à UI.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProcessEffect {
    /// `show=1`: abre a janela "Processos".
    ShowWindow,
}

/// `GET /apps` — os apps de desktop que o Egeon abriu e quem usa cada um.
/// Só lê a memória: pode responder dentro do ator.
pub fn apps(keeper: &AppKeeper, _req: &RouteRequest, _now: SystemTime) -> RouteReply {
    RouteReply::ok(keeper.snapshot())
}

/// `POST /processes/reap[?dry=1]` — a limpeza periódica agora, com a política
/// de `processes.json`: órfão velho, fora o daemon do Claude Code. `dry` só diz
/// quem ela levaria. Devolve também quantos foram levados, para o core anotar
/// em `OrphanReaper::record` (zero no `dry`, que não é uma limpeza).
pub fn reap_route(
    env: &ProcessEnv<'_>,
    policy: &ReapPolicy,
    req: &RouteRequest,
    now: SystemTime,
) -> (RouteReply, Option<usize>) {
    let dry = req.param("dry") == Some("1");
    let killed = reap(policy, &env.scanner(), now, dry);
    let list: Vec<Value> = killed.iter().map(|p| p.json(now)).collect();
    let key = if dry { "wouldKill" } else { "killed" };
    let reply = RouteReply::ok(json!({"ok": true, key: list}));
    (reply, (!dry).then_some(killed.len()))
}

/// `POST /processes/kill[?pid=N,M]` — SIGTERM nos órfãos, ou nos pids dados se
/// a leitura de agora disser que são do Egeon (ADR-083). Pid que não é número
/// é ignorado; `pid=` só com lixo não leva ninguém, em vez de levar os órfãos.
pub fn kill(env: &ProcessEnv<'_>, req: &RouteRequest, now: SystemTime) -> RouteReply {
    let pids: Option<HashSet<u32>> = req
        .param("pid")
        .map(|raw| raw.split(',').filter_map(|p| p.parse().ok()).collect());
    let killed = env.scanner().terminate(pids.as_ref());
    let list: Vec<Value> = killed.iter().map(|p| p.json(now)).collect();
    RouteReply::ok(json!({"ok": true, "killed": list}))
}

/// `GET /processes[?orphans=1][&show=1]` — o que o Egeon lançou: debaixo do
/// app, e os órfãos que ainda carregam a marca no ambiente (ADR-083).
pub fn processes(
    env: &ProcessEnv<'_>,
    req: &RouteRequest,
    now: SystemTime,
) -> (RouteReply, Vec<ProcessEffect>) {
    let effects = if req.param("show") == Some("1") {
        vec![ProcessEffect::ShowWindow]
    } else {
        Vec::new()
    };
    let all = env.scanner().scan();
    let orphans = all.iter().filter(|p| p.orphan).count();
    let shown: Vec<Value> = all
        .iter()
        .filter(|p| req.param("orphans") != Some("1") || p.orphan)
        .map(|p| p.json(now))
        .collect();
    let reply = RouteReply::ok(json!({
        "ok": true,
        "owned": all.len() - orphans,
        "orphans": orphans,
        "processes": shown,
    }));
    (reply, effects)
}
