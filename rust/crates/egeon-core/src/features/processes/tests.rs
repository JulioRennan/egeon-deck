//! Porte de `AppClaimsTests.swift` e do que falta de `ProcessTableTests.swift`
//! (o resto vive em `model.rs`; o `ProcessArguments` é do driver e o
//! `testCLIOffersPs`, do `egeon-cli`), mais o `AppKeeper`, o scanner, o
//! reaper e as rotas contra um sistema de mentira: nenhum teste lê o kernel
//! nem manda sinal.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde_json::json;

use super::claims::{AppClaims, Entry};
use super::containers::ContainerOwners;
use super::keeper::{AppKeeper, Closing, Drivers};
use super::mark;
use super::model::ReapPolicy;
use super::policy_file::{load_policy, save_policy};
use super::reaper::OrphanReaper;
use super::routes::{self, ProcessEffect, ProcessEnv};
use super::scanner::{ProcessScanner, ScanContext};
use crate::ports::procs::{
    AppDriver, ProcessDetail, ProcessDriver, ProcessError, ProcessSignal, RawProcess, RunningApp,
    SocketLinks,
};
use crate::protocol::handler::RouteRequest;

fn set(items: &[&str]) -> BTreeSet<String> {
    items.iter().map(|s| (*s).to_owned()).collect()
}

fn map(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
    pairs
        .iter()
        .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
        .collect()
}

fn env(pairs: &[(&str, &str)]) -> HashMap<String, String> {
    pairs
        .iter()
        .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
        .collect()
}

// ---- AppClaimsTests

#[test]
fn app_sem_marca_nunca_e_fechado() {
    // Aberto por você: nenhum terminal do Egeon é o dono dele.
    let mut claims = AppClaims::default();
    assert!(
        claims
            .release(&set(&["a/claude"]), &set(&[]), &map(&[]))
            .is_empty()
    );
}

#[test]
fn quem_abriu_saindo_fecha_o_app() {
    let mut claims = AppClaims::default();
    let launchers = map(&[("com.docker.docker", "a/back")]);
    assert!(
        claims
            .release(&set(&["outra/x"]), &set(&["a/back"]), &launchers)
            .is_empty()
    );
    assert_eq!(
        claims.release(&set(&["a/back"]), &set(&["b/y"]), &launchers),
        ["com.docker.docker"]
    );
}

fn docker_entry(users: &[&str]) -> AppClaims {
    AppClaims {
        apps: BTreeMap::from([(
            "com.docker.docker".to_owned(),
            Entry {
                launched: true,
                users: set(users),
            },
        )]),
    }
}

#[test]
fn o_herdeiro_e_o_ultimo_a_usar() {
    // Quem abriu saiu, mas `b/back` ainda usava: ficou como herdeiro.
    let mut claims = docker_entry(&["b/back"]);
    let launchers = map(&[("com.docker.docker", "a/back")]);
    assert!(
        claims
            .release(&set(&["c/z"]), &set(&["b/back"]), &launchers)
            .is_empty()
    );
    assert_eq!(
        claims.release(&set(&["b/back"]), &set(&[]), &launchers),
        ["com.docker.docker"]
    );
    assert!(!claims.apps.contains_key("com.docker.docker"));
}

#[test]
fn herdeiro_morto_nao_segura_o_app() {
    let mut claims = docker_entry(&["a/back", "velha/x"]);
    assert_eq!(
        claims.release(&set(&["a/back"]), &set(&["c/y"]), &map(&[])),
        ["com.docker.docker"]
    );
}

#[test]
fn o_opener_e_so_o_app_que_o_launchd_abriu() {
    let engine = env(&[
        ("__CFBundleIdentifier", "com.docker.docker"),
        ("EGEON_NODE", "a/back"),
    ]);
    assert_eq!(
        AppClaims::opener("com.docker.docker", &engine).as_deref(),
        Some("a/back")
    );
    // A janela do Docker Desktop: outro bundle, com o ambiente do motor.
    assert_eq!(
        AppClaims::opener("com.electron.dockerdesktop", &engine),
        None
    );
    assert_eq!(
        AppClaims::opener(
            "com.google.Chrome",
            &env(&[("__CFBundleIdentifier", "com.google.Chrome")])
        ),
        None
    );
}

#[test]
fn donos_dos_containers() {
    let paths: BTreeMap<String, Vec<String>> = BTreeMap::from([
        ("main".into(), vec!["/w/proj".into()]),
        ("feat".into(), vec!["/w/proj/worktrees/feat".into()]),
        ("solta".into(), vec!["/w/outra".into(), "/w/wt/x".into()]),
    ]);
    let dirs = |items: &[&str]| items.iter().map(|s| (*s).to_owned()).collect::<Vec<_>>();
    let owners = ContainerOwners::new(
        &dirs(&["/w/proj/api", "/w/proj/worktrees/feat", "/w/wt/x/db"]),
        &paths,
    );
    assert_eq!(owners.benches, set(&["main", "feat", "solta"]));
    assert!(!owners.unknown);
    // Sem rótulo de compose, ou de pasta de bancada nenhuma.
    assert!(ContainerOwners::new(&dirs(&[""]), &paths).unknown);
    assert!(ContainerOwners::new(&dirs(&["/w/projeto"]), &paths).unknown);
    assert_eq!(
        ContainerOwners::new(&[], &paths),
        ContainerOwners::new(&[], &BTreeMap::new())
    );
    // Espaço em volta do rótulo não conta.
    assert!(!ContainerOwners::new(&dirs(&["  /w/proj/api\t"]), &paths).unknown);
}

#[test]
fn apps_json_do_swift_abre_e_o_que_se_grava_tem_a_mesma_forma() {
    // `JSONEncoder` com `.prettyPrinted` e `.sortedKeys`.
    let swift = r#"{
  "apps" : {
    "com.docker.docker" : {
      "launched" : true,
      "users" : [
        "b/back",
        "a/back"
      ]
    }
  }
}"#;
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join("apps.json");
    std::fs::write(&file, swift).unwrap();
    let claims = AppClaims::load(&file);
    assert!(claims.apps["com.docker.docker"].launched);
    assert_eq!(
        claims.apps["com.docker.docker"].users,
        set(&["a/back", "b/back"])
    );
    claims.save(&file);
    let saved: serde_json::Value = serde_json::from_slice(&std::fs::read(&file).unwrap()).unwrap();
    assert_eq!(
        saved,
        json!({"apps": {"com.docker.docker": {"launched": true, "users": ["a/back", "b/back"]}}})
    );
    // Sem as chaves, como o `Codable` sintetizado: abre vazio.
    std::fs::write(&file, r#"{"apps":{"x":{"launched":true}}}"#).unwrap();
    assert_eq!(AppClaims::load(&file), AppClaims::default());
    std::fs::write(&file, "lixo").unwrap();
    assert_eq!(AppClaims::load(&file), AppClaims::default());
}

// ---- Um sistema de mentira

const T0: u64 = 1_787_678_363;
const DECK: &str = "egeon-next";

fn at(offset: u64) -> SystemTime {
    UNIX_EPOCH + Duration::from_secs(T0 + offset)
}

fn raw(pid: u32, ppid: u32, name: &str, offset: u64, environment: &[(&str, &str)]) -> RawProcess {
    RawProcess {
        pid,
        ppid,
        started: at(offset),
        name: name.to_owned(),
        command: name.to_owned(),
        environment: env(environment),
    }
}

#[derive(Default)]
struct FakeProcs {
    all: Mutex<Vec<RawProcess>>,
    signals: Mutex<Vec<(u32, ProcessSignal)>>,
}

impl FakeProcs {
    fn with(all: Vec<RawProcess>) -> Arc<Self> {
        Arc::new(FakeProcs {
            all: Mutex::new(all),
            ..Default::default()
        })
    }

    fn signaled(&self) -> Vec<u32> {
        let mut pids: Vec<u32> = self.signals.lock().unwrap().iter().map(|s| s.0).collect();
        pids.sort_unstable();
        pids
    }
}

impl ProcessDriver for FakeProcs {
    fn list(&self, detail: ProcessDetail) -> Result<Vec<RawProcess>, ProcessError> {
        let mut all = self.all.lock().unwrap().clone();
        if detail == ProcessDetail::Tree {
            for p in &mut all {
                p.environment.clear();
            }
        }
        Ok(all)
    }

    fn environment_of(&self, pid: u32) -> Option<HashMap<String, String>> {
        let all = self.all.lock().unwrap();
        all.iter()
            .find(|p| p.pid == pid)
            .map(|p| p.environment.clone())
    }

    fn parent_of(&self, pid: u32) -> Option<u32> {
        let all = self.all.lock().unwrap();
        all.iter().find(|p| p.pid == pid).map(|p| p.ppid)
    }

    fn signal(&self, pid: u32, signal: ProcessSignal) -> Result<(), ProcessError> {
        self.signals.lock().unwrap().push((pid, signal));
        Ok(())
    }
}

#[derive(Default)]
struct FakeApps {
    running: Vec<RunningApp>,
    links: Option<SocketLinks>,
    dirs: Option<Vec<String>>,
    quits: Mutex<Vec<u32>>,
}

impl FakeApps {
    fn quit_pids(&self) -> Vec<u32> {
        let mut pids = self.quits.lock().unwrap().clone();
        pids.sort_unstable();
        pids
    }
}

impl AppDriver for FakeApps {
    fn running_apps(&self) -> Vec<RunningApp> {
        self.running.clone()
    }

    fn request_quit(&self, pid: u32) {
        self.quits.lock().unwrap().push(pid);
    }

    fn socket_links(&self) -> Option<SocketLinks> {
        self.links.clone()
    }

    fn container_working_dirs(&self) -> Option<Vec<String>> {
        self.dirs.clone()
    }
}

fn app(bundle: &str, pid: u32) -> RunningApp {
    RunningApp {
        bundle: bundle.to_owned(),
        pid,
    }
}

fn context() -> ScanContext {
    ScanContext {
        app_pid: 100,
        deck: DECK.to_owned(),
    }
}

/// O Egeon (pid 100) com o shell do nó `a/back`, mais o que `extra` trouxer.
fn table(extra: Vec<RawProcess>) -> Vec<RawProcess> {
    let mut all = vec![
        raw(1, 0, "launchd", 0, &[]),
        raw(100, 1, "egeon-app", 0, &[]),
        raw(
            101,
            100,
            "zsh",
            1,
            &[(mark::NODE, "a/back"), (mark::DECK, DECK)],
        ),
    ];
    all.extend(extra);
    all
}

fn orphan(pid: u32, offset: u64, command: &str) -> RawProcess {
    let mut p = raw(
        pid,
        1,
        "node",
        offset,
        &[(mark::NODE, "a/back"), (mark::DECK, DECK)],
    );
    p.command = command.to_owned();
    p
}

// ---- Scanner e reaper

#[test]
fn o_scanner_so_encerra_o_que_a_leitura_de_agora_confirma() {
    let procs = FakeProcs::with(table(vec![
        orphan(300, 5, "servidor"),
        raw(400, 1, "alheio", 5, &[]),
    ]));
    let ctx = context();
    let scanner = ProcessScanner::new(procs.as_ref(), &ctx);
    // Pid que veio de fora e não é do Egeon (400) não leva sinal.
    let killed = scanner.terminate(Some(&HashSet::from([300, 400])));
    assert_eq!(killed.iter().map(|p| p.pid).collect::<Vec<_>>(), [300]);
    assert_eq!(procs.signaled(), [300]);
    // Sem pids: os órfãos todos, e só eles (o shell 101 é do app).
    let procs = FakeProcs::with(table(vec![orphan(300, 5, "a"), orphan(301, 6, "b")]));
    let scanner = ProcessScanner::new(procs.as_ref(), &ctx);
    scanner.terminate(None);
    assert_eq!(procs.signaled(), [300, 301]);
    assert!(
        procs
            .signals
            .lock()
            .unwrap()
            .iter()
            .all(|s| s.1 == ProcessSignal::Terminate)
    );
}

#[test]
fn o_reaper_leva_orfao_velho_poupa_o_daemon_e_o_dry_so_conta() {
    let dir = tempfile::tempdir().unwrap();
    let procs = FakeProcs::with(table(vec![
        orphan(300, 0, "servidor velho"),
        orphan(301, 7000, "servidor novo"),
        orphan(302, 0, "claude daemon run"),
    ]));
    let ctx = context();
    let scanner = ProcessScanner::new(procs.as_ref(), &ctx);
    let mut reaper = OrphanReaper::new(dir.path().join("processes.json"));
    let now = at(2 * 3600);

    // Uma hora de idade mínima: o de 300 passou, o de 301 ainda não, e o
    // daemon do Claude nunca entra.
    let dry = reaper.reap_now(&scanner, now, true);
    assert_eq!(dry.iter().map(|p| p.pid).collect::<Vec<_>>(), [300]);
    assert!(procs.signaled().is_empty(), "dry não manda sinal");
    assert_eq!(reaper.last(), None);

    let killed = reaper.reap_now(&scanner, now, false);
    assert_eq!(killed.iter().map(|p| p.pid).collect::<Vec<_>>(), [300]);
    assert_eq!(procs.signaled(), [300]);
    assert_eq!(reaper.last(), Some((now, 1)));

    // Nada a levar: não manda sinal e registra zero.
    let procs = FakeProcs::with(table(vec![]));
    let scanner = ProcessScanner::new(procs.as_ref(), &ctx);
    assert!(reaper.reap_now(&scanner, now, false).is_empty());
    assert!(procs.signaled().is_empty());
    assert_eq!(reaper.last(), Some((now, 0)));
}

#[test]
fn a_politica_do_arquivo_liga_desliga_e_define_a_batida() {
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join("processes.json");
    let mut reaper = OrphanReaper::new(file.clone());
    // Padrão: ligada, de 10 em 10 minutos.
    assert_eq!(reaper.start(), Some(Duration::from_secs(600)));
    // Editado à mão: o `set_enabled` relê antes de gravar.
    std::fs::write(&file, r#"{"intervalMinutes": 30, "minAgeMinutes": 5}"#).unwrap();
    assert_eq!(reaper.set_enabled(true), Some(Duration::from_secs(1800)));
    assert_eq!(reaper.set_enabled(false), None);
    assert!(!reaper.policy().enabled);
    let saved: serde_json::Value = serde_json::from_slice(&std::fs::read(&file).unwrap()).unwrap();
    assert_eq!(
        saved,
        json!({"enabled": false, "intervalMinutes": 30, "minAgeMinutes": 5})
    );
    assert_eq!(load_policy(&file), *reaper.policy());
    // Arquivo estragado ou ausente: o padrão.
    std::fs::write(&file, "lixo").unwrap();
    assert_eq!(load_policy(&file), ReapPolicy::default());
    save_policy(&file, &ReapPolicy::default());
    assert_eq!(load_policy(&file), ReapPolicy::default());
}

// ---- AppKeeper

struct Bench {
    dir: tempfile::TempDir,
    procs: Arc<FakeProcs>,
    apps: FakeApps,
    ctx: ScanContext,
}

impl Bench {
    fn new(procs: Vec<RawProcess>, apps: FakeApps) -> Self {
        Bench {
            dir: tempfile::tempdir().unwrap(),
            procs: FakeProcs::with(procs),
            apps,
            ctx: context(),
        }
    }

    fn keeper(&self) -> AppKeeper {
        AppKeeper::new(self.dir.path().join("apps.json"))
    }

    fn release(
        &self,
        keeper: &mut AppKeeper,
        leaving: &[&str],
        live: &[&str],
        paths: &BTreeMap<String, Vec<String>>,
    ) -> Vec<Closing> {
        let drivers = Drivers {
            apps: &self.apps,
            procs: self.procs.as_ref(),
            context: &self.ctx,
        };
        keeper.release(&set(leaving), &set(live), paths, &drivers)
    }
}

const CHROME: &str = "com.google.Chrome";
const DOCKER: &str = "com.docker.docker";

fn chrome_opened_by(node: &str, pid: u32) -> RawProcess {
    raw(
        pid,
        1,
        "Chrome",
        2,
        &[(mark::BUNDLE_VARIABLE, CHROME), (mark::NODE, node)],
    )
}

#[test]
fn quem_abriu_o_app_saindo_fecha_o_app_e_o_registro_some() {
    let b = Bench::new(
        table(vec![chrome_opened_by("a/back", 500)]),
        FakeApps {
            running: vec![app(CHROME, 500), app("dev.duckcoder.egeondeck.next", 100)],
            ..Default::default()
        },
    );
    let mut keeper = b.keeper();
    // Outro nó saindo não toca no app.
    assert!(
        b.release(&mut keeper, &["x/outro"], &["a/back"], &BTreeMap::new())
            .is_empty()
    );
    assert!(b.apps.quit_pids().is_empty());

    let closing = b.release(&mut keeper, &["a/back"], &["b/y"], &BTreeMap::new());
    assert_eq!(
        closing,
        [Closing {
            bundle: CHROME.into(),
            pid: 500
        }]
    );
    // O pedido vai só para o Chrome: o próprio Egeon nunca é fechado por aqui.
    assert_eq!(b.apps.quit_pids(), [500]);
    assert_eq!(keeper.snapshot(), json!({"apps": {}}));
    assert_eq!(AppClaims::load(keeper.file()), AppClaims::default());
}

#[test]
fn sem_ninguem_saindo_nao_olha_o_sistema() {
    let b = Bench::new(table(vec![]), FakeApps::default());
    let mut keeper = b.keeper();
    assert!(
        b.release(&mut keeper, &[], &["a/back"], &BTreeMap::new())
            .is_empty()
    );
}

#[test]
fn app_com_conexao_viva_de_outro_no_segue_aberto_e_o_no_vira_herdeiro() {
    // O `docker compose up` de `b/front` fala com o Chrome por socket.
    let mut compose = raw(
        600,
        1,
        "compose",
        3,
        &[(mark::NODE, "b/front"), (mark::DECK, DECK)],
    );
    compose.ppid = 100;
    let links = SocketLinks {
        own: HashMap::from([(500, HashSet::from(["0xaaa".to_owned()]))]),
        peers: HashMap::from([(600, HashSet::from(["0xaaa".to_owned()]))]),
    };
    let b = Bench::new(
        table(vec![chrome_opened_by("a/back", 500), compose]),
        FakeApps {
            running: vec![app(CHROME, 500)],
            links: Some(links),
            ..Default::default()
        },
    );
    let mut keeper = b.keeper();
    let closing = b.release(&mut keeper, &["a/back"], &["b/front"], &BTreeMap::new());
    assert!(closing.is_empty());
    assert!(b.apps.quit_pids().is_empty());
    assert_eq!(
        keeper.snapshot(),
        json!({"apps": {CHROME: {"launched": true, "users": ["b/front"]}}})
    );
    // Persistiu: o herdeiro sobrevive ao reinício.
    assert_eq!(
        AppClaims::load(keeper.file()).apps[CHROME].users,
        set(&["b/front"])
    );

    // O herdeiro sai: agora fecha.
    let closing = b.release(&mut keeper, &["b/front"], &[], &BTreeMap::new());
    assert_eq!(closing.len(), 1);
    assert_eq!(b.apps.quit_pids(), [500]);
}

fn docker_world(dirs: Option<Vec<&str>>) -> Bench {
    // O motor (500) abriu pelo launchd; a janela (501) é outro bundle com a
    // marca do motor no ambiente.
    let engine = raw(
        500,
        1,
        "Docker",
        2,
        &[(mark::BUNDLE_VARIABLE, DOCKER), (mark::NODE, "a/back")],
    );
    let window = raw(
        501,
        1,
        "Docker Desktop",
        2,
        &[(mark::BUNDLE_VARIABLE, DOCKER), (mark::NODE, "a/back")],
    );
    Bench::new(
        table(vec![engine, window]),
        FakeApps {
            running: vec![app(DOCKER, 500), app("com.electron.dockerdesktop", 501)],
            dirs: dirs.map(|d| d.into_iter().map(str::to_owned).collect()),
            ..Default::default()
        },
    )
}

fn benches() -> BTreeMap<String, Vec<String>> {
    BTreeMap::from([
        ("a".to_owned(), vec!["/w/a".to_owned()]),
        ("b".to_owned(), vec!["/w/b".to_owned()]),
    ])
}

#[test]
fn docker_sem_container_fecha_com_a_janela_junto() {
    let b = docker_world(Some(vec![]));
    let mut keeper = b.keeper();
    let closing = b.release(&mut keeper, &["a/back"], &[], &benches());
    assert_eq!(
        closing,
        [Closing {
            bundle: DOCKER.into(),
            pid: 500
        }]
    );
    // O motor ignora o pedido; a janela, que é do mesmo lançamento, o leva.
    assert_eq!(b.apps.quit_pids(), [500, 501]);
}

#[test]
fn docker_com_container_sem_dono_ou_ilegivel_segue_aberto() {
    for (dirs, reason) in [
        (None, "não deu para listar os containers"),
        (Some(vec![""]), "há container de fora das bancadas"),
        (Some(vec!["/w/outra"]), "há container de fora das bancadas"),
    ] {
        let b = docker_world(dirs);
        let mut keeper = b.keeper();
        assert!(
            b.release(&mut keeper, &["a/back"], &[], &benches())
                .is_empty(),
            "{reason}"
        );
        assert!(b.apps.quit_pids().is_empty(), "{reason}");
        // Fica registrado como aberto pelo Egeon, sem herdeiro.
        assert_eq!(
            keeper.snapshot(),
            json!({"apps": {DOCKER: {"launched": true, "users": []}}}),
            "{reason}"
        );
    }
}

#[test]
fn docker_com_container_de_bancada_parada_segue_aberto_e_o_de_bancada_viva_vira_herdeiro() {
    // Container de `b`, que está parada: o banco dela tem de estar lá quando voltar.
    let b = docker_world(Some(vec!["/w/b/api"]));
    let mut keeper = b.keeper();
    assert!(
        b.release(&mut keeper, &["a/back"], &[], &benches())
            .is_empty()
    );
    assert!(b.apps.quit_pids().is_empty());

    // Com `b/front` de pé, o uso é dela: vira herdeira.
    let b = docker_world(Some(vec!["/w/b/api"]));
    let mut keeper = b.keeper();
    assert!(
        b.release(&mut keeper, &["a/back"], &["b/front"], &benches())
            .is_empty()
    );
    assert_eq!(
        keeper.snapshot(),
        json!({"apps": {DOCKER: {"launched": true, "users": ["b/front"]}}})
    );

    // Container só da própria bancada que sai não segura o Docker.
    let b = docker_world(Some(vec!["/w/a/api"]));
    let mut keeper = b.keeper();
    assert_eq!(
        b.release(&mut keeper, &["a/back"], &[], &benches()).len(),
        1
    );
}

#[test]
fn tmp_e_private_tmp_sao_o_mesmo_lugar() {
    // O compose grava um, a bancada pode ter o outro.
    let paths = BTreeMap::from([(
        "a".to_owned(),
        vec!["/private/tmp/egeon-teste-a".to_owned()],
    )]);
    let b = docker_world(Some(vec!["/tmp/egeon-teste-a/api"]));
    let mut keeper = b.keeper();
    // `a` está saindo e é a dona do container: nada de bancada parada nem de fora.
    assert_eq!(b.release(&mut keeper, &["a/back"], &[], &paths).len(), 1);
}

#[test]
fn depois_do_prazo_o_keeper_diz_se_o_app_seguiu_aberto() {
    let b = Bench::new(
        table(vec![chrome_opened_by("a/back", 500)]),
        FakeApps::default(),
    );
    let closing = Closing {
        bundle: CHROME.into(),
        pid: 500,
    };
    assert!(AppKeeper::still_open(&closing, b.procs.as_ref()));
    let gone = Closing {
        bundle: CHROME.into(),
        pid: 999,
    };
    assert!(!AppKeeper::still_open(&gone, b.procs.as_ref()));
}

// ---- Rotas

fn request(method: &str, target: &str) -> RouteRequest {
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
        origin: None,
    }
}

fn world_with(procs: Vec<RawProcess>) -> (Arc<FakeProcs>, ScanContext) {
    (FakeProcs::with(procs), context())
}

#[test]
fn rota_apps_mostra_quem_usa_cada_app() {
    let dir = tempfile::tempdir().unwrap();
    AppClaims {
        apps: BTreeMap::from([(
            CHROME.to_owned(),
            Entry {
                launched: true,
                users: set(&["b/front", "a/back"]),
            },
        )]),
    }
    .save(&dir.path().join("apps.json"));
    let keeper = AppKeeper::new(dir.path().join("apps.json"));
    let reply = routes::apps(&keeper, &request("GET", "/apps"), at(0));
    assert_eq!(reply.status, 200);
    assert_eq!(
        reply.json,
        json!({"apps": {CHROME: {"launched": true, "users": ["a/back", "b/front"]}}})
    );
}

#[test]
fn rota_processes_conta_e_filtra_os_orfaos() {
    let (procs, ctx) = world_with(table(vec![orphan(300, 5, "servidor")]));
    let env = ProcessEnv {
        procs: procs.as_ref(),
        context: &ctx,
    };
    let now = at(65);
    let (all, effects) = routes::processes(&env, &request("GET", "/processes"), now);
    assert!(effects.is_empty());
    assert_eq!(all.status, 200);
    assert_eq!(all.json["ok"], true);
    assert_eq!(all.json["owned"], 1);
    assert_eq!(all.json["orphans"], 1);
    assert_eq!(all.json["processes"].as_array().unwrap().len(), 2);

    let (only, _) = routes::processes(&env, &request("GET", "/processes?orphans=1"), now);
    assert_eq!(only.json["owned"], 1, "a contagem não depende do filtro");
    assert_eq!(
        only.json["processes"],
        json!([{"pid": 300, "ppid": 1, "node": "a/back", "orphan": true, "age": 60, "command": "servidor"}])
    );
}

#[test]
fn rota_processes_show_pede_a_janela() {
    let (procs, ctx) = world_with(table(vec![]));
    let env = ProcessEnv {
        procs: procs.as_ref(),
        context: &ctx,
    };
    let (_, effects) = routes::processes(&env, &request("GET", "/processes?show=1"), at(0));
    assert_eq!(effects, [ProcessEffect::ShowWindow]);
}

#[test]
fn rota_kill_leva_os_orfaos_ou_so_os_pids_confirmados() {
    let world = || {
        table(vec![
            orphan(300, 5, "a"),
            orphan(301, 6, "b"),
            raw(400, 1, "alheio", 5, &[]),
        ])
    };
    let kill = |query: &str| {
        let (procs, ctx) = world_with(world());
        let env = ProcessEnv {
            procs: procs.as_ref(),
            context: &ctx,
        };
        let reply = routes::kill(
            &env,
            &request("POST", &format!("/processes/kill{query}")),
            at(60),
        );
        (reply, procs.signaled())
    };
    let (all, signaled) = kill("");
    assert_eq!(all.json["ok"], true);
    assert_eq!(all.json["killed"].as_array().unwrap().len(), 2);
    assert_eq!(signaled, [300, 301]);

    let (some, signaled) = kill("?pid=301,400,xx");
    assert_eq!(some.json["killed"].as_array().unwrap().len(), 1);
    assert_eq!(some.json["killed"][0]["pid"], 301);
    assert_eq!(signaled, [301], "400 não é do Egeon");

    // `pid=` só com lixo não vira "todos os órfãos".
    let (none, signaled) = kill("?pid=xx");
    assert_eq!(none.json["killed"], json!([]));
    assert!(signaled.is_empty());
}

#[test]
fn rota_reap_diz_quem_levaria_ou_quem_levou_e_quantos_anotar() {
    let world = || table(vec![orphan(300, 0, "velho"), orphan(301, 7000, "novo")]);
    let now = at(2 * 3600);
    let policy = ReapPolicy::default();
    let (procs, ctx) = world_with(world());
    let env = ProcessEnv {
        procs: procs.as_ref(),
        context: &ctx,
    };
    let (dry, count) = routes::reap_route(
        &env,
        &policy,
        &request("POST", "/processes/reap?dry=1"),
        now,
    );
    assert_eq!(dry.json["ok"], true);
    assert_eq!(dry.json["wouldKill"].as_array().unwrap().len(), 1);
    assert!(dry.json.get("killed").is_none());
    assert_eq!(count, None, "dry não é uma limpeza");
    assert!(procs.signaled().is_empty());

    let (real, count) = routes::reap_route(&env, &policy, &request("POST", "/processes/reap"), now);
    assert!(real.json.get("wouldKill").is_none());
    assert_eq!(real.json["killed"][0]["pid"], 300);
    assert_eq!(count, Some(1));
    assert_eq!(procs.signaled(), [300]);
}
