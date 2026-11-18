//! Dono: `cli`. Liga ao ator processos e apps abertos (US-303) e as rotas /apps e /processes*, com o tique da limpeza.
//!
//! O core mantém a assinatura destas funções, que o `actor.rs` chama; o
//! corpo é do dono. A leitura do kernel e os sinais bloqueiam: saem do ator
//! por `spawn_blocking` e voltam por `Msg::Run`, como o `project_new` do org.
//! Só o `/apps`, que lê a memória, responde dentro do ator.

use std::collections::{BTreeMap, BTreeSet, HashSet, VecDeque};
use std::time::{Duration, SystemTime};

use super::{Actor, Msg, Replier, not_ported};
use crate::commons::clock::local_offset_secs;
use crate::commons::paths::{Flavor, Paths};
use crate::features::path_text::expand_tilde;
use crate::features::processes::keeper::{AppKeeper, Drivers as KeeperDrivers, QUIT_WATCH};
use crate::features::processes::policy_file;
use crate::features::processes::reaper::{OrphanReaper, reap};
use crate::features::processes::routes::{self, ProcessEffect, ProcessEnv};
use crate::features::processes::scanner::{ProcessScanner, ScanContext};
use crate::features::processes::view::{ProcessesView, view};
use crate::protocol::app::{AppEffect, ReaperView};
use crate::protocol::handler::{RouteReply, RouteRequest};
use crate::protocol::routes::FeatureRoute;

/// O que a janela "Processos" da UI pede (decisão do /ui: comandos
/// `processes`, `processes_reap` e `processes_kill`).
#[derive(Debug, Clone, PartialEq, Eq)]
#[allow(dead_code)] // até o core ligar os comandos
pub(super) enum Panel {
    /// Só ler.
    List,
    /// "Encerrar órfãos": SIGTERM em TODOS os órfãos, sem a idade mínima da
    /// limpeza periódica — o `ProcessScanner.terminate(nil)` do botão. Não
    /// conta como "última limpeza".
    KillOrphans,
    /// "Encerrar selecionados": só os pids que a leitura de agora confirma.
    Kill(HashSet<u32>),
}

/// O Swift relê a lista meio segundo depois de mandar o SIGTERM, para o
/// processo ter tempo de sair; no teste não há processo de verdade.
const SETTLE_AFTER_KILL: Duration = if cfg!(test) {
    Duration::ZERO
} else {
    Duration::from_millis(500)
};

/// O estado de processos e apps dentro do ator. Nasce vazio e se completa na
/// primeira vez que alguém precisa dele, a partir da `Config`.
#[derive(Default)]
pub(super) struct ProcessesState {
    inner: Option<Inner>,
}

struct Inner {
    keeper: AppKeeper,
    reaper: OrphanReaper,
    context: ScanContext,
    /// Quando a limpeza periódica roda de novo; `None` até o primeiro tique
    /// ou com a limpeza desligada.
    next_reap: Option<SystemTime>,
    /// Há uma limpeza fora do ator: não começa outra por cima.
    reaping: bool,
    /// Os fechamentos de app esperando a vez. Um de cada vez, na ordem: o
    /// segundo precisa enxergar o que o primeiro gravou (o Swift os
    /// serializava na fila do `AppKeeper`).
    releases: VecDeque<(BTreeSet<String>, BTreeSet<String>)>,
    /// Um fechamento está rodando fora do ator.
    releasing: bool,
}

impl Inner {
    fn new(paths: &Paths, flavor: Flavor) -> Self {
        Inner {
            keeper: AppKeeper::new(paths.config(crate::features::processes::claims::FILE)),
            reaper: OrphanReaper::new(paths.config(policy_file::FILE)),
            context: ScanContext {
                app_pid: std::process::id(),
                // O `EGEON_DECK` que o core carimba: é por ele que o scanner
                // reconhece o que é nosso e não do Swift em uso.
                deck: flavor.identifier().to_owned(),
            },
            next_reap: None,
            reaping: false,
            releases: VecDeque::new(),
            releasing: false,
        }
    }
}

impl Actor {
    fn processes_inner(&mut self) -> &mut Inner {
        let (paths, flavor) = (&self.config.paths, self.config.flavor);
        self.processes
            .inner
            .get_or_insert_with(|| Inner::new(paths, flavor))
    }

    pub(super) fn processes_route(
        &mut self,
        route: FeatureRoute,
        request: RouteRequest,
        reply: Replier,
    ) {
        let now = SystemTime::now();
        if route == FeatureRoute::Apps {
            let answer = routes::apps(&self.processes_inner().keeper, &request, now);
            let _ = reply.send(answer);
            return;
        }
        if !matches!(
            route,
            FeatureRoute::Processes | FeatureRoute::ProcessesKill | FeatureRoute::ProcessesReap
        ) {
            return not_ported(route, reply);
        }
        let (context, policy) = {
            let inner = self.processes_inner();
            (inner.context.clone(), inner.reaper.policy().clone())
        };
        let procs = self.drivers.procs.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let done = tokio::task::spawn_blocking(move || {
                let env = ProcessEnv {
                    procs: procs.as_ref(),
                    context: &context,
                };
                match route {
                    FeatureRoute::ProcessesKill => {
                        (routes::kill(&env, &request, now), None, Vec::new())
                    }
                    FeatureRoute::ProcessesReap => {
                        let (answer, killed) = routes::reap_route(&env, &policy, &request, now);
                        (answer, killed, Vec::new())
                    }
                    _ => {
                        let (answer, effects) = routes::processes(&env, &request, now);
                        (answer, None, effects)
                    }
                }
            })
            .await;
            let Ok((answer, killed, effects)) = done else {
                let _ = reply.send(RouteReply::err(500, "a leitura dos processos não terminou"));
                return;
            };
            let job = move |actor: &mut Actor| {
                if let Some(killed) = killed {
                    actor.processes_inner().reaper.record(now, killed);
                }
                // A janela "Processos" é da UI: o `show=1` vira efeito no tópico `app`.
                if effects.contains(&ProcessEffect::ShowWindow) {
                    actor.app_effect(AppEffect::ShowProcesses);
                }
                let _ = reply.send(answer);
            };
            let _ = inbox.send(Msg::Run(Box::new(job))).await;
        });
    }

    /// A limpeza automática de órfãos para o tópico `app`.
    pub(super) fn reaper_view(&mut self) -> ReaperView {
        ReaperView {
            enabled: self.processes_inner().reaper.policy().enabled,
        }
    }

    /// O item de menu "Limpar órfãos automaticamente". Zera o relógio: ligar
    /// de novo espera um intervalo inteiro, como o `Timer` que o Swift recria.
    pub(super) fn reaper_set_enabled(&mut self, on: bool) {
        let inner = self.processes_inner();
        inner.reaper.set_enabled(on);
        inner.next_reap = None;
    }

    /// A janela "Processos" para a UI: lê (e, se pedido, encerra) fora do ator
    /// e volta com a lista nova, no texto da janela do Swift. `done` roda no
    /// ator, com a lista pronta, e é quem responde ao comando. Leitura que não
    /// terminou chega como erro: lista vazia diria "0 no app", que é mentira.
    #[allow(dead_code)] // até o core ligar os comandos
    pub(super) fn processes_panel(
        &mut self,
        action: Panel,
        done: impl FnOnce(&mut Actor, Result<ProcessesView, &'static str>) + Send + 'static,
    ) {
        let context = self.processes_inner().context.clone();
        let procs = self.drivers.procs.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let read = tokio::task::spawn_blocking(move || {
                let scanner = ProcessScanner::new(procs.as_ref(), &context);
                let killed = match &action {
                    Panel::List => 0,
                    Panel::KillOrphans => scanner.terminate(None).len(),
                    Panel::Kill(pids) => scanner.terminate(Some(pids)).len(),
                };
                if killed > 0 {
                    std::thread::sleep(SETTLE_AFTER_KILL);
                }
                scanner.scan()
            })
            .await;
            let job = move |actor: &mut Actor| {
                let panel = read
                    .map(|found| {
                        let now = SystemTime::now();
                        let offset = local_offset_secs(now);
                        view(found, &actor.processes_inner().reaper, now, offset)
                    })
                    .map_err(|_| "a leitura dos processos não terminou");
                done(actor, panel);
            };
            let _ = inbox.send(Msg::Run(Box::new(job))).await;
        });
    }

    /// Bancada → pastas, para o `AppKeeper` dizer de quem é cada container: a
    /// raiz da bancada e a pasta de cada nó que tem a sua (worktree própria).
    fn bench_paths(&self) -> BTreeMap<String, Vec<String>> {
        let home = self.org.home.as_str();
        let mut paths: BTreeMap<String, Vec<String>> = BTreeMap::new();
        for bench in &self.org.state.workbenches {
            let root = expand_tilde(&bench.path, home);
            let own = bench
                .nodes
                .iter()
                .filter_map(|n| n.cwd.as_deref())
                .map(|cwd| {
                    let path = expand_tilde(cwd, home);
                    if path.starts_with('/') {
                        path
                    } else {
                        format!("{root}/{path}")
                    }
                });
            let list = paths.entry(bench.name.clone()).or_default();
            list.push(root.clone());
            list.extend(own);
        }
        paths
    }

    /// Um nó saiu de verdade (depois de sair do Dispatcher: reiniciar o
    /// agente não larga app nenhum): fecha o app que o Egeon abriu e que ele
    /// era o último a usar (ADR-084). `leaving` são os endereços que saem e
    /// `live` os que seguem de pé. O core chama na remoção do nó e da bancada.
    #[allow(dead_code)]
    pub(super) fn processes_release_apps(
        &mut self,
        leaving: BTreeSet<String>,
        live: BTreeSet<String>,
    ) {
        if leaving.is_empty() {
            return;
        }
        self.processes_inner().releases.push_back((leaving, live));
        self.processes_release_next();
    }

    /// Começa o próximo fechamento da fila, se não há um em curso. Ao voltar,
    /// cada um instala o keeper novo e chama este de novo.
    fn processes_release_next(&mut self) {
        let paths = self.bench_paths();
        let inner = self.processes_inner();
        if inner.releasing {
            return;
        }
        let Some((leaving, live)) = inner.releases.pop_front() else {
            return;
        };
        inner.releasing = true;
        let mut keeper = inner.keeper.clone();
        let context = inner.context.clone();
        let (procs, apps) = (self.drivers.procs.clone(), self.drivers.apps.clone());
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let done = tokio::task::spawn_blocking(move || {
                let drivers = KeeperDrivers {
                    apps: apps.as_ref(),
                    procs: procs.as_ref(),
                    context: &context,
                };
                let closing = keeper.release(&leaving, &live, &paths, &drivers);
                (keeper, closing, procs)
            })
            .await;
            let (keeper, closing, procs) = match done {
                Ok(done) => (Some(done.0), done.1, Some(done.2)),
                Err(_) => (None, Vec::new(), None),
            };
            let job = move |actor: &mut Actor| {
                let inner = actor.processes_inner();
                if let Some(keeper) = keeper {
                    inner.keeper = keeper;
                }
                inner.releasing = false;
                actor.processes_release_next();
            };
            let _ = inbox.send(Msg::Run(Box::new(job))).await;
            let Some(procs) = procs.filter(|_| !closing.is_empty()) else {
                return;
            };
            // O app que ainda não saiu depois do prazo vai para o log.
            tokio::time::sleep(QUIT_WATCH).await;
            let _ = tokio::task::spawn_blocking(move || {
                for app in &closing {
                    AppKeeper::still_open(app, procs.as_ref());
                }
            })
            .await;
        });
    }

    /// A limpeza periódica dos órfãos (ADR-083), de quanto em quanto a política
    /// manda. Rede de segurança: o grosso morre junto com o nó.
    pub(super) fn processes_tick(&mut self, now: SystemTime) {
        let inner = self.processes_inner();
        let Some(every) = inner.reaper.start() else {
            inner.next_reap = None;
            return;
        };
        let due = match inner.next_reap {
            None => {
                // Como o `Timer` do Swift: a primeira limpeza é depois de um
                // intervalo inteiro, não na partida.
                inner.next_reap = Some(now + every);
                false
            }
            Some(at) => now >= at,
        };
        if !due || inner.reaping {
            return;
        }
        inner.next_reap = Some(now + every.max(Duration::from_secs(1)));
        inner.reaping = true;
        let (context, policy) = (inner.context.clone(), inner.reaper.policy().clone());
        let procs = self.drivers.procs.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let killed = tokio::task::spawn_blocking(move || {
                let scanner = ProcessScanner::new(procs.as_ref(), &context);
                reap(&policy, &scanner, now, false).len()
            })
            .await;
            let job = move |actor: &mut Actor| {
                let inner = actor.processes_inner();
                inner.reaping = false;
                if let Ok(killed) = killed {
                    inner.reaper.record(now, killed);
                }
            };
            let _ = inbox.send(Msg::Run(Box::new(job))).await;
        });
    }
}

/// O ator de verdade, com o sistema de mentira, para os testes das rotas dos
/// arquivos `cli` (processos, trilha, fila, atualização).
#[cfg(test)]
pub(super) mod support {
    use std::path::PathBuf;
    use std::sync::Arc;
    use std::time::Duration;

    use tokio::sync::{mpsc, oneshot};

    use super::super::{Actor, HttpReply, Msg};
    use crate::commons::paths::{Flavor, Paths};
    use crate::ports::procs::AppDriver;
    use crate::protocol::handler::RouteRequest;
    use crate::protocol::routes::FeatureRoute;
    use crate::runtime::fakes::{
        FakeApps, FakeCloner, FakeFolders, FakeLinks, FakeLocal, FakeNotifier, FakeOpener,
        FakeProcs, FakePty, FakeScreens, fake_executable,
    };
    use crate::runtime::{Config, Drivers};

    /// Como o teste monta o `AppDriver`, a partir da pasta de dados.
    type AppsMaker = Box<dyn FnOnce(&std::path::Path) -> Arc<dyn AppDriver>>;

    pub struct Rig {
        pub actor: Actor,
        pub rx: mpsc::Receiver<Msg>,
        pub procs: Arc<FakeProcs>,
        pub data: PathBuf,
        pub dir: tempfile::TempDir,
    }

    impl Rig {
        pub fn new() -> Rig {
            Self::with_flavor(Flavor::Stable)
        }

        pub fn with_flavor(flavor: Flavor) -> Rig {
            Self::build(flavor, None)
        }

        /// Com um `AppDriver` do teste no lugar do que não tem app nenhum; ele
        /// recebe o caminho da pasta de dados para poder conferir os arquivos.
        pub fn with_apps(
            make: impl FnOnce(&std::path::Path) -> Arc<dyn AppDriver> + 'static,
        ) -> Rig {
            Self::build(Flavor::Stable, Some(Box::new(make)))
        }

        fn build(flavor: Flavor, apps: Option<AppsMaker>) -> Rig {
            let dir = tempfile::tempdir().unwrap();
            let data = dir.path().join("data");
            std::fs::create_dir_all(&data).unwrap();
            let pty = Arc::new(FakePty::default());
            let procs = Arc::new(FakeProcs::sharing(pty.journal.clone()));
            let apps: Arc<dyn AppDriver> = match apps {
                Some(make) => make(&data),
                None => Arc::new(FakeApps),
            };
            let drivers = Drivers {
                pty: pty.clone(),
                screens: Arc::new(FakeScreens),
                local: Arc::new(FakeLocal::default()),
                procs: procs.clone(),
                notifier: Arc::new(FakeNotifier::default()),
                apps,
                installer: Arc::new(FakeApps),
                opener: Arc::new(FakeOpener::default()),
                cloner: Arc::new(FakeCloner),
                links: Arc::new(FakeLinks),
                is_executable: fake_executable,
                folders: Arc::new(FakeFolders::default()),
            };
            let config = Config {
                paths: Paths::new(data.clone()),
                default_cwd: dir.path().to_owned(),
                flavor,
                cli_binary: None,
                ui_parent: false,
                version: "9.9.9".into(),
                build: "42".into(),
            };
            let (tx, rx) = mpsc::channel(64);
            Rig {
                actor: Actor::new(config, drivers, tx),
                rx,
                procs,
                data,
                dir,
            }
        }

        /// Entrega a rota ao ator e atende o que ele mandar de volta
        /// (`Msg::Run`) até a resposta sair.
        pub async fn call(&mut self, route: FeatureRoute, request: RouteRequest) -> HttpReply {
            let (reply, mut answer) = oneshot::channel();
            self.actor.feature_route(route, request, reply);
            self.pump(&mut answer).await
        }

        pub async fn pump(&mut self, answer: &mut oneshot::Receiver<HttpReply>) -> HttpReply {
            loop {
                tokio::select! {
                    reply = &mut *answer => return reply.expect("a rota não respondeu"),
                    msg = self.rx.recv() => {
                        let msg = msg.expect("a fila do ator fechou");
                        self.actor.handle(msg);
                    }
                    () = tokio::time::sleep(Duration::from_secs(10)) => panic!("a rota demorou demais"),
                }
            }
        }

        /// Atende a fila do ator até `done` ser verdade (no máximo 10 s).
        pub async fn pump_until(&mut self, mut done: impl FnMut(&mut Actor) -> bool) {
            let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
            while !done(&mut self.actor) {
                let left = deadline.saturating_duration_since(tokio::time::Instant::now());
                match tokio::time::timeout(left, self.rx.recv()).await {
                    Ok(Some(msg)) => {
                        self.actor.handle(msg);
                    }
                    _ => panic!("a condição não chegou a tempo"),
                }
            }
        }

        /// Atende o que já está na fila do ator, sem esperar resposta.
        pub async fn settle(&mut self) {
            loop {
                match tokio::time::timeout(Duration::from_millis(300), self.rx.recv()).await {
                    Ok(Some(msg)) => {
                        self.actor.handle(msg);
                    }
                    _ => return,
                }
            }
        }
    }

    /// Um cliente do `/ui` ligado ao ator, para os testes de ponta a ponta.
    pub struct Ui {
        pub id: super::super::ClientId,
        pub lines: mpsc::Receiver<super::super::WireLine>,
        /// A ponta que a conexão esperaria para fechar; segurá-la mantém o
        /// cliente vivo.
        _closed: oneshot::Receiver<()>,
    }

    pub async fn ui(rig: &mut Rig) -> Ui {
        let (queue, lines) = mpsc::channel(64);
        let (alive, closed) = oneshot::channel();
        let (reply, got) = oneshot::channel();
        rig.actor.handle(Msg::UiOpen {
            queue,
            alive,
            reply,
        });
        Ui {
            id: got.await.unwrap(),
            lines,
            _closed: closed,
        }
    }

    /// Manda um comando como o `/ui` o mandaria, em JSON.
    pub fn send(rig: &mut Rig, ui: &Ui, command: serde_json::Value) {
        let command = crate::protocol::message::parse_command(&command.to_string()).unwrap();
        rig.actor.handle(Msg::UiCommand {
            client: ui.id,
            command,
        });
    }

    /// Tudo o que já chegou ao cliente.
    pub fn drain(ui: &mut Ui) -> Vec<serde_json::Value> {
        let mut out = Vec::new();
        while let Ok(line) = ui.lines.try_recv() {
            out.push(serde_json::from_slice(&line).unwrap());
        }
        out
    }

    pub fn request(method: &str, target: &str, origin: Option<&str>) -> RouteRequest {
        let (path, query) = target.split_once('?').unwrap_or((target, ""));
        RouteRequest {
            method: method.into(),
            target: target.into(),
            path: path.into(),
            query: query
                .split('&')
                .filter_map(|p| p.split_once('='))
                .map(|(k, v)| (k.to_owned(), v.to_owned()))
                .collect(),
            body: Vec::new(),
            origin: origin.map(str::to_owned),
        }
    }
}

#[cfg(test)]
mod tests {
    use std::collections::{HashMap, HashSet};
    use std::sync::{Arc, Mutex};
    use std::time::{Duration, SystemTime, UNIX_EPOCH};

    use serde_json::json;

    use super::support::{Rig, request};
    use super::{Panel, ProcessesView};
    use crate::features::processes::mark;
    use crate::ports::procs::{ProcessSignal, RawProcess};
    use crate::protocol::routes::FeatureRoute;

    fn raw(pid: u32, ppid: u32, name: &str, started: u64, env: &[(&str, &str)]) -> RawProcess {
        RawProcess {
            pid,
            ppid,
            started: UNIX_EPOCH + Duration::from_secs(started),
            name: name.to_owned(),
            command: name.to_owned(),
            environment: env
                .iter()
                .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
                .collect::<HashMap<_, _>>(),
        }
    }

    /// O app (este processo de teste), um shell de nó debaixo dele e um órfão
    /// marcado, solto do pai desde o começo dos tempos.
    fn table() -> Vec<RawProcess> {
        let app = std::process::id();
        vec![
            raw(1, 0, "launchd", 0, &[]),
            raw(app, 1, "egeon-app", 0, &[]),
            raw(
                9001,
                app,
                "zsh",
                10,
                &[(mark::NODE, "deck/claude"), (mark::DECK, "egeon-next")],
            ),
            raw(
                9100,
                1,
                "node",
                0,
                &[(mark::NODE, "deck/claude"), (mark::DECK, "egeon-next")],
            ),
        ]
    }

    fn signaled(rig: &Rig) -> Vec<u32> {
        let mut pids: Vec<u32> = rig
            .procs
            .signals
            .lock()
            .unwrap()
            .iter()
            .map(|s| s.0)
            .collect();
        pids.sort_unstable();
        pids
    }

    #[tokio::test]
    async fn apps_responde_vazio_sem_arquivo() {
        let mut rig = Rig::new();
        let reply = rig
            .call(FeatureRoute::Apps, request("GET", "/apps", None))
            .await;
        assert_eq!((reply.status, reply.json), (200, json!({"apps": {}})));
    }

    #[tokio::test]
    async fn processes_lista_os_do_egeon_e_conta_os_orfaos() {
        let mut rig = Rig::new();
        *rig.procs.table.lock().unwrap() = table();
        let reply = rig
            .call(FeatureRoute::Processes, request("GET", "/processes", None))
            .await;
        assert_eq!(reply.status, 200);
        assert_eq!(reply.json["owned"], 1);
        assert_eq!(reply.json["orphans"], 1);
        let only = rig
            .call(
                FeatureRoute::Processes,
                request("GET", "/processes?orphans=1", None),
            )
            .await;
        let list = only.json["processes"].as_array().unwrap();
        assert_eq!(list.len(), 1);
        assert_eq!(list[0]["pid"], 9100);
        assert_eq!(list[0]["node"], "deck/claude");
        assert_eq!(list[0]["orphan"], true);
    }

    /// Chama o painel e espera a lista que volta ao ator.
    async fn panel(rig: &mut Rig, action: Panel) -> ProcessesView {
        let slot = Arc::new(Mutex::new(None));
        let sink = slot.clone();
        rig.actor.processes_panel(action, move |_, view| {
            *sink.lock().unwrap() = Some(view.unwrap());
        });
        let watched = slot.clone();
        rig.pump_until(move |_| watched.lock().unwrap().is_some())
            .await;
        slot.lock().unwrap().take().unwrap()
    }

    #[tokio::test]
    async fn o_painel_lista_no_texto_da_janela_sem_encerrar_ninguem() {
        let mut rig = Rig::new();
        *rig.procs.table.lock().unwrap() = table();
        let view = panel(&mut rig, Panel::List).await;
        let pids: Vec<u32> = view.processes.iter().map(|p| p.pid).collect();
        assert_eq!(pids, [9100, 9001], "o órfão primeiro");
        assert_eq!(view.processes[0].node.as_deref(), Some("deck/claude"));
        assert!(view.processes[0].orphan);
        assert!(!view.processes[1].orphan);
        assert_eq!(view.orphans, 1);
        assert!(view.enabled);
        assert_eq!(view.summary, "1 no app · 1 órfão · limpeza a cada 10 min");
        assert!(signaled(&rig).is_empty());
    }

    #[tokio::test]
    async fn o_painel_encerra_todos_os_orfaos_sem_olhar_a_idade_e_nao_conta_como_limpeza() {
        let mut rig = Rig::new();
        // Um órfão velho e um que acabou de se soltar: o botão leva os dois,
        // a limpeza periódica só levaria o velho.
        let young = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let mut all = table();
        all.push(raw(
            9101,
            1,
            "node",
            young,
            &[(mark::NODE, "deck/claude"), (mark::DECK, "egeon-next")],
        ));
        *rig.procs.table.lock().unwrap() = all;
        let view = panel(&mut rig, Panel::KillOrphans).await;
        assert_eq!(signaled(&rig), [9100, 9101]);
        // Quem não é órfão não leva sinal.
        assert!(!signaled(&rig).contains(&9001));
        assert!(
            view.summary.ends_with("limpeza a cada 10 min"),
            "{}",
            view.summary
        );
    }

    #[tokio::test]
    async fn o_painel_encerra_so_os_pids_que_a_leitura_confirma() {
        let mut rig = Rig::new();
        *rig.procs.table.lock().unwrap() = table();
        let pids: HashSet<u32> = [9001, 1, 4242].into();
        let view = panel(&mut rig, Panel::Kill(pids)).await;
        // 1 (launchd) e 4242 não são do Egeon: só o shell do nó leva.
        assert_eq!(signaled(&rig), [9001]);
        assert_eq!(view.processes.len(), 2);
    }

    #[tokio::test]
    async fn kill_so_leva_o_que_a_leitura_confirma() {
        let mut rig = Rig::new();
        *rig.procs.table.lock().unwrap() = table();
        let none = rig
            .call(
                FeatureRoute::ProcessesKill,
                request("POST", "/processes/kill?pid=1,4242", None),
            )
            .await;
        assert_eq!(none.json, json!({"ok": true, "killed": []}));
        assert!(signaled(&rig).is_empty());

        let orphan = rig
            .call(
                FeatureRoute::ProcessesKill,
                request("POST", "/processes/kill?pid=9100,9001", None),
            )
            .await;
        // Os dois são do Egeon (o shell e o órfão): ambos levam SIGTERM.
        assert_eq!(orphan.json["killed"].as_array().unwrap().len(), 2);
        assert_eq!(signaled(&rig), [9001, 9100]);
        assert!(
            rig.procs
                .signals
                .lock()
                .unwrap()
                .iter()
                .all(|s| s.1 == ProcessSignal::Terminate)
        );
    }

    #[tokio::test]
    async fn reap_a_seco_nao_leva_e_de_verdade_leva_so_o_orfao_velho() {
        let mut rig = Rig::new();
        *rig.procs.table.lock().unwrap() = table();
        let dry = rig
            .call(
                FeatureRoute::ProcessesReap,
                request("POST", "/processes/reap?dry=1", None),
            )
            .await;
        assert_eq!(dry.json["wouldKill"].as_array().unwrap().len(), 1);
        assert!(signaled(&rig).is_empty());
        assert_eq!(rig.actor.processes_inner().reaper.last(), None);

        let real = rig
            .call(
                FeatureRoute::ProcessesReap,
                request("POST", "/processes/reap", None),
            )
            .await;
        assert_eq!(real.json["killed"][0]["pid"], 9100);
        assert_eq!(signaled(&rig), [9100]);
        // A limpeza foi anotada no ator, de volta do trabalho fora dele.
        assert_eq!(
            rig.actor.processes_inner().reaper.last().map(|l| l.1),
            Some(1)
        );
    }

    #[tokio::test]
    async fn o_tique_limpa_depois_de_um_intervalo_inteiro_e_nao_por_cima() {
        let mut rig = Rig::new();
        *rig.procs.table.lock().unwrap() = table();
        let t0 = SystemTime::now();
        // Primeiro tique: só arma o relógio, como o `Timer` do Swift.
        rig.actor.processes_tick(t0);
        rig.settle().await;
        assert!(signaled(&rig).is_empty());
        // Antes do intervalo (10 min): nada.
        rig.actor.processes_tick(t0 + Duration::from_secs(300));
        rig.settle().await;
        assert!(signaled(&rig).is_empty());
        // Passado o intervalo: limpa o órfão velho, uma vez só.
        rig.actor.processes_tick(t0 + Duration::from_secs(601));
        rig.actor.processes_tick(t0 + Duration::from_secs(602));
        rig.settle().await;
        assert_eq!(signaled(&rig), [9100]);
        assert_eq!(
            rig.actor.processes_inner().reaper.last().map(|l| l.1),
            Some(1)
        );
    }

    #[tokio::test]
    async fn limpeza_desligada_no_arquivo_nao_roda() {
        let mut rig = Rig::new();
        std::fs::write(rig.data.join("processes.json"), r#"{"enabled": false}"#).unwrap();
        *rig.procs.table.lock().unwrap() = table();
        let t0 = SystemTime::now();
        rig.actor.processes_tick(t0);
        rig.actor.processes_tick(t0 + Duration::from_secs(3600));
        rig.settle().await;
        assert!(signaled(&rig).is_empty());
    }

    #[tokio::test]
    async fn sair_um_no_calcula_as_pastas_da_bancada_e_grava_o_registro_dos_apps() {
        use crate::features::node::model::{NodeConfig, NodeKind};
        use crate::features::workbench::model::WorkbenchConfig;
        use std::collections::BTreeSet;

        let mut rig = Rig::new();
        rig.actor.org.home = "/Users/x".into();
        let mut own = NodeConfig::new(NodeKind::Shell, "wt");
        own.cwd = Some("worktrees/wt".into());
        let mut abs = NodeConfig::new(NodeKind::Shell, "abs");
        abs.cwd = Some("/abs/dir".into());
        let plain = NodeConfig::new(NodeKind::Shell, "plain");
        rig.actor.org.state.workbenches.push(WorkbenchConfig::new(
            "deck",
            "~/proj",
            vec![own, abs, plain],
        ));
        assert_eq!(
            rig.actor.bench_paths(),
            std::collections::BTreeMap::from([(
                "deck".to_owned(),
                vec![
                    "/Users/x/proj".to_owned(),
                    "/Users/x/proj/worktrees/wt".to_owned(),
                    "/abs/dir".to_owned(),
                ]
            )])
        );

        // Sem apps abertos pelo Egeon nada fecha, mas o registro é regravado.
        assert!(!rig.data.join("apps.json").exists());
        rig.actor
            .processes_release_apps(BTreeSet::from(["deck/wt".to_owned()]), BTreeSet::new());
        rig.settle().await;
        let saved = std::fs::read_to_string(rig.data.join("apps.json")).unwrap();
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&saved).unwrap(),
            json!({"apps": {}})
        );
    }

    /// Um `AppDriver` que deixa o Chrome aberto, anota o que o `apps.json` dizia
    /// a cada leitura e segura a primeira para os fechamentos se sobreporem.
    struct SlowApps {
        file: std::path::PathBuf,
        seen: std::sync::Mutex<Vec<String>>,
        quits: std::sync::Mutex<Vec<u32>>,
    }

    impl crate::ports::procs::AppDriver for SlowApps {
        fn running_apps(&self) -> Vec<crate::ports::procs::RunningApp> {
            let first = {
                let mut seen = self.seen.lock().unwrap();
                seen.push(std::fs::read_to_string(&self.file).unwrap_or_default());
                seen.len() == 1
            };
            if first {
                std::thread::sleep(Duration::from_millis(300));
            }
            vec![crate::ports::procs::RunningApp {
                bundle: "com.google.Chrome".into(),
                pid: 500,
            }]
        }
        fn request_quit(&self, pid: u32) {
            self.quits.lock().unwrap().push(pid);
        }
        fn socket_links(&self) -> Option<crate::ports::procs::SocketLinks> {
            None
        }
        fn container_working_dirs(&self) -> Option<Vec<String>> {
            None
        }
    }

    // Duas remoções em seguida: a segunda tem de partir do que a primeira
    // gravou, e não do mesmo `apps.json` de antes — senão a última a voltar
    // desfaz a outra e o app que devia fechar fica aberto.
    #[tokio::test]
    async fn fechamentos_de_apps_seguidos_rodam_um_de_cada_vez() {
        use std::collections::BTreeSet;
        use std::sync::Arc;

        let slow: Arc<std::sync::OnceLock<Arc<SlowApps>>> = Arc::default();
        let handle = slow.clone();
        let mut rig = Rig::with_apps(move |data| {
            let apps = Arc::new(SlowApps {
                file: data.join("apps.json"),
                seen: Default::default(),
                quits: Default::default(),
            });
            let _ = handle.set(apps.clone());
            apps
        });
        let apps = slow.get().unwrap().clone();
        std::fs::write(
            rig.data.join("apps.json"),
            r#"{"apps":{"com.google.Chrome":{"launched":true,"users":["a/1","a/2"]}}}"#,
        )
        .unwrap();
        let set = |items: &[&str]| {
            items
                .iter()
                .map(|s| (*s).to_owned())
                .collect::<BTreeSet<_>>()
        };

        rig.actor
            .processes_release_apps(set(&["a/1"]), set(&["a/2"]));
        rig.actor.processes_release_apps(set(&["a/2"]), set(&[]));
        // Os dois já foram pedidos; só um roda por vez.
        assert!(rig.actor.processes_inner().releasing);
        assert_eq!(rig.actor.processes_inner().releases.len(), 1);
        rig.pump_until(|actor| {
            let inner = actor.processes_inner();
            !inner.releasing && inner.releases.is_empty()
        })
        .await;

        let seen = apps.seen.lock().unwrap().clone();
        assert_eq!(seen.len(), 2, "cada fechamento leu os apps uma vez");
        // O segundo enxergou o efeito do primeiro: só `a/2` seguia usando.
        let second: serde_json::Value = serde_json::from_str(&seen[1]).unwrap();
        assert_eq!(
            second,
            json!({"apps": {"com.google.Chrome": {"launched": true, "users": ["a/2"]}}})
        );
        // E fechou o Chrome uma vez só, com o registro limpo no fim.
        assert_eq!(*apps.quits.lock().unwrap(), [500]);
        let saved = std::fs::read_to_string(rig.data.join("apps.json")).unwrap();
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&saved).unwrap(),
            json!({"apps": {}})
        );
        assert!(!rig.actor.processes_inner().releasing);
    }
}
