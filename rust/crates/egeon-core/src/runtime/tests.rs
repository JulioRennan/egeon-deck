use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::Ordering;
use std::time::Duration;

use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader, DuplexStream};
use tokio::sync::{mpsc, oneshot};

use super::actor::{Actor, Msg};
use super::fakes::{
    FakeApps, FakeCloner, FakeFolders, FakeLinks, FakeLocal, FakeNotifier, FakeOpener, FakeProcs,
    FakePty, FakeScreens, fake_executable, process,
};
use super::{Config, Drivers, RuntimeError, serve};
use crate::commons::paths::{Flavor, Paths};
use crate::ports::local_conn::Probe;
use crate::ports::notifier::NoticeClick;
use crate::ports::procs::ProcessSignal;
use crate::ports::pty::{PtyEvent, PtyExit, PtySignal, PtySize};
use crate::protocol::message::{Command, CommandKind, NodeId, Topic};

struct Harness {
    pty: Arc<FakePty>,
    notifier: Arc<FakeNotifier>,
    procs: Arc<FakeProcs>,
    local: Arc<FakeLocal>,
    stop: Option<oneshot::Sender<()>>,
    task: tokio::task::JoinHandle<Result<(), RuntimeError>>,
    _home: TempHome,
}

/// Pasta temporária feita à mão: o core só precisa que ela exista.
struct TempHome(PathBuf);

impl TempHome {
    fn new() -> Self {
        use std::sync::atomic::AtomicU64;
        static N: AtomicU64 = AtomicU64::new(0);
        let dir = std::env::temp_dir().join(format!(
            "egeon-core-test-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        std::fs::create_dir_all(&dir).unwrap();
        Self(dir)
    }
}

impl Drop for TempHome {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn config(home: &TempHome) -> Config {
    Config {
        paths: Paths::new(home.0.join("data")),
        default_cwd: home.0.clone(),
        flavor: Flavor::Stable,
        cli_binary: None,
        ui_parent: false,
        version: "9.9.9".into(),
        build: "42".into(),
    }
}

impl Harness {
    async fn start() -> Self {
        Self::start_with(Arc::new(FakeLocal::default())).await
    }

    async fn start_with(local: Arc<FakeLocal>) -> Self {
        Self::start_full(local, &[]).await
    }

    /// Com arquivos já na pasta de dados, como um `~/.egeon-next` de verdade.
    async fn start_with_files(files: &[(&str, String)]) -> Self {
        Self::start_full(Arc::new(FakeLocal::default()), files).await
    }

    async fn start_full(local: Arc<FakeLocal>, files: &[(&str, String)]) -> Self {
        Self::start_config(local, files, false).await
    }

    /// Como lançado pela UI (`--exit-with-stdin`).
    async fn start_ui_parent() -> Self {
        Self::start_config(Arc::new(FakeLocal::default()), &[], true).await
    }

    async fn start_config(
        local: Arc<FakeLocal>,
        files: &[(&str, String)],
        ui_parent: bool,
    ) -> Self {
        let files: Vec<(String, String)> = files
            .iter()
            .map(|(name, text)| ((*name).to_owned(), text.clone()))
            .collect();
        Self::start_built(local, ui_parent, move |_| files).await
    }

    /// Com os arquivos montados a partir da pasta de dados — para o teste que
    /// precisa apontar um nó para dentro dela.
    async fn start_with_data(
        build: impl FnOnce(&std::path::Path) -> Vec<(String, String)>,
    ) -> Self {
        Self::start_built(Arc::new(FakeLocal::default()), false, build).await
    }

    async fn start_built(
        local: Arc<FakeLocal>,
        ui_parent: bool,
        build: impl FnOnce(&std::path::Path) -> Vec<(String, String)>,
    ) -> Self {
        let home = TempHome::new();
        let data = home.0.join("data");
        std::fs::create_dir_all(&data).unwrap();
        let files = build(&data);
        for (name, text) in &files {
            let file = data.join(name);
            if let Some(parent) = file.parent() {
                std::fs::create_dir_all(parent).unwrap();
            }
            std::fs::write(&file, text).unwrap();
            // O que mora em `bin/` é programa: o catálogo só vale para um
            // `claude` que o PATH do filho acha e que roda.
            if name.starts_with("bin/") {
                use std::os::unix::fs::PermissionsExt;
                std::fs::set_permissions(&file, std::fs::Permissions::from_mode(0o755)).unwrap();
            }
        }
        let notifier = Arc::new(FakeNotifier::default());
        let pty = Arc::new(FakePty::default());
        let procs = Arc::new(FakeProcs::sharing(pty.journal.clone()));
        let drivers = Drivers {
            pty: pty.clone(),
            screens: Arc::new(FakeScreens),
            local: local.clone(),
            procs: procs.clone(),
            notifier: notifier.clone(),
            apps: Arc::new(FakeApps),
            installer: Arc::new(FakeApps),
            opener: Arc::new(FakeOpener::default()),
            cloner: Arc::new(FakeCloner),
            links: Arc::new(FakeLinks),
            is_executable: fake_executable,
            folders: Arc::new(FakeFolders::default()),
        };
        let (stop, stopped) = oneshot::channel::<()>();
        let config = Config {
            ui_parent,
            ..config(&home)
        };
        let task = tokio::spawn(serve(config, drivers, async {
            let _ = stopped.await;
        }));
        Self {
            pty,
            notifier,
            procs,
            local,
            stop: Some(stop),
            task,
            _home: home,
        }
    }

    async fn http(&self, raw: &str) -> (u16, Value) {
        let mut s = self.local.connect().await;
        s.write_all(raw.as_bytes()).await.unwrap();
        let mut out = Vec::new();
        s.read_to_end(&mut out).await.unwrap();
        let text = String::from_utf8(out).unwrap();
        let status = text[9..12].parse().unwrap();
        let (head, body) = text.split_once("\r\n\r\n").unwrap();
        assert!(head.contains("Content-Type: application/json"), "{head}");
        (status, serde_json::from_str(body).unwrap())
    }

    async fn get(&self, path: &str) -> (u16, Value) {
        self.http(&format!("GET {path} HTTP/1.1\r\nHost: x\r\n\r\n"))
            .await
    }

    async fn post(&self, path: &str, body: &str) -> (u16, Value) {
        self.http(&format!(
            "POST {path} HTTP/1.1\r\nHost: x\r\nContent-Length: {}\r\n\r\n{body}",
            body.len()
        ))
        .await
    }

    async fn ui(&self) -> Ui {
        let mut s = self.local.connect().await;
        s.write_all(b"GET /ui HTTP/1.1\r\nConnection: Upgrade\r\nUpgrade: egeon-ndjson\r\n\r\n")
            .await
            .unwrap();
        let mut reader = BufReader::new(s);
        let mut status = String::new();
        reader.read_line(&mut status).await.unwrap();
        assert!(status.starts_with("HTTP/1.1 101"), "{status}");
        loop {
            let mut line = String::new();
            reader.read_line(&mut line).await.unwrap();
            if line == "\r\n" {
                break;
            }
        }
        Ui { reader }
    }

    async fn stop(mut self) -> Result<(), RuntimeError> {
        if let Some(stop) = self.stop.take() {
            let _ = stop.send(());
        }
        self.task.await.unwrap()
    }
}

struct Ui {
    reader: BufReader<DuplexStream>,
}

impl Ui {
    async fn send(&mut self, msg: Value) {
        let mut line = serde_json::to_vec(&msg).unwrap();
        line.push(b'\n');
        self.reader.get_mut().write_all(&line).await.unwrap();
    }

    async fn recv(&mut self) -> Value {
        let mut line = String::new();
        tokio::time::timeout(Duration::from_secs(5), self.reader.read_line(&mut line))
            .await
            .expect("nada chegou no /ui")
            .unwrap();
        assert!(line.ends_with('\n'), "linha sem quebra: {line:?}");
        serde_json::from_str(&line).unwrap()
    }

    /// Lê até chegar a linha que `wanted` aceita; as outras (eventos de
    /// outros tópicos, a resposta antes do evento) passam.
    async fn until(&mut self, wanted: impl Fn(&Value) -> bool) -> Value {
        for _ in 0..50 {
            let line = self.recv().await;
            if wanted(&line) {
                return line;
            }
        }
        panic!("a linha esperada não chegou");
    }

    async fn reply(&mut self, re: u64) -> Value {
        self.until(|v| v["re"] == re).await
    }
}

/// Repete a consulta até o ator ter processado o que veio do pty.
async fn eventually<F, Fut>(mut check: F)
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = bool>,
{
    for _ in 0..500 {
        if check().await {
            return;
        }
        tokio::time::sleep(Duration::from_millis(2)).await;
    }
    panic!("a condição não chegou a valer");
}

fn t(id: &str) -> NodeId {
    NodeId::new(id).unwrap()
}

#[tokio::test]
async fn about_devolve_versao_e_build() {
    let h = Harness::start().await;
    let (status, body) = h.get("/about").await;
    assert_eq!(status, 200);
    assert_eq!(body, json!({"ok": true, "version": "9.9.9", "build": "42"}));
    h.stop().await.unwrap();
}

#[tokio::test]
async fn rota_desconhecida_e_requisicao_ruim() {
    let h = Harness::start().await;
    let (status, body) = h.get("/nada").await;
    assert_eq!(status, 404);
    assert_eq!(body["ok"], false);
    // Cabeçalho sem `:` é ignorado, como no Swift.
    let (status, _) = h
        .http("GET /about HTTP/1.1\r\nsem dois pontos\r\n\r\n")
        .await;
    assert_eq!(status, 200);
    // Corpo acima do teto: a única recusa que diverge do Swift.
    let raw = format!(
        "POST /terminal HTTP/1.1\r\nContent-Length: {}\r\n\r\n",
        crate::protocol::http::MAX_BODY + 1
    );
    let (status, _) = h.http(&raw).await;
    assert_eq!(status, 413);
    h.stop().await.unwrap();
}

#[tokio::test]
async fn cria_terminal_com_shell_de_login_na_pasta() {
    let h = Harness::start().await;
    let cwd = h._home.0.to_string_lossy().into_owned();
    let (status, body) = h
        .post(
            "/terminal",
            &json!({"cwd": cwd, "cmd": "htop", "cols": 100, "rows": 30}).to_string(),
        )
        .await;
    assert_eq!(status, 200, "{body}");
    assert_eq!(body["ok"], true);
    assert_eq!(body["id"], "t1");
    assert_eq!(body["pid"], 1000);
    assert_eq!(body["cols"], 100);
    assert_eq!(body["alive"], true);
    assert_eq!(body["command"], "htop");

    let (_, _, spec) = h.pty.child(0);
    assert_eq!(spec.program, PathBuf::from("/bin/zsh"));
    assert_eq!(
        spec.args,
        vec!["-lc".to_owned(), format!("cd '{cwd}'; clear; htop")]
    );
    assert_eq!(spec.cwd, None, "o cd vai só na linha");
    assert_eq!(
        spec.size,
        PtySize {
            cols: 100,
            rows: 30
        }
    );
    // O TERM do core vence o que vier do ambiente, e só aparece uma vez.
    let terms: Vec<_> = spec.env.iter().filter(|(k, _)| k == "TERM").collect();
    assert_eq!(
        terms,
        vec![&("TERM".to_owned(), "xterm-256color".to_owned())]
    );
    // O `egeon` mora na pasta de dados, como `Flavor.config("bin")`.
    let bin = h._home.0.join("data/bin").to_string_lossy().into_owned();
    assert!(
        spec.env
            .iter()
            .any(|(k, v)| k == "PATH" && v.starts_with(&bin))
    );
    // O ambiente do filho não leva as `CLAUDE_CODE*` nem a procedência
    // herdada (quem marca é o terminal que lança), seja o que o teste herdou.
    let leaked: Vec<_> = spec
        .env
        .iter()
        .map(|(k, _)| k.as_str())
        .filter(|k| {
            k.starts_with("CLAUDE_CODE")
                || *k == "CLAUDECODE"
                || ["EGEON_NODE", "EGEON_DECK", "EGEON_TARGET"].contains(k)
        })
        .collect();
    assert!(leaked.is_empty(), "vazou {leaked:?}");

    let (status, list) = h.get("/terminals").await;
    assert_eq!(status, 200);
    assert_eq!(list["terminals"][0]["id"], "t1");
    h.stop().await.unwrap();
}

#[tokio::test]
async fn cria_terminal_sem_corpo_abre_o_shell_na_pasta_padrao() {
    let h = Harness::start().await;
    let (status, body) = h.post("/terminal", "").await;
    assert_eq!(status, 200, "{body}");
    assert_eq!(body["cols"], 80);
    assert_eq!(body["rows"], 24);
    let (_, _, spec) = h.pty.child(0);
    assert!(spec.args[1].ends_with("; clear; exec /bin/zsh -l"));
    // Pasta que sumiu não impede o nó de subir, como no Swift.
    let (status, _) = h.post("/terminal", r#"{"cwd":"/nao/existe/mesmo"}"#).await;
    assert_eq!(status, 200);
    let (_, _, spec) = h.pty.child(1);
    assert!(spec.args[1].starts_with("cd '/nao/existe/mesmo'; clear; "));
    let (status, _) = h.post("/terminal", r#"{"cols":0}"#).await;
    assert_eq!(status, 400);
    h.stop().await.unwrap();
}

#[tokio::test]
async fn input_escreve_no_pty() {
    let h = Harness::start().await;
    h.post("/terminal", "").await;
    let (status, body) = h.post("/terminal/t1/input", "echo egeon-ok\n").await;
    assert_eq!((status, body), (200, json!({"ok": true})));
    let (log, _, _) = h.pty.child(0);
    assert_eq!(&*log.writes.lock().unwrap(), b"echo egeon-ok\n");

    let (status, body) = h.post("/terminal/t9/input", "x").await;
    assert_eq!(status, 404);
    assert_eq!(body["error"], "terminal desconhecido 't9'");
    h.stop().await.unwrap();
}

#[tokio::test]
async fn peek_mostra_o_texto_da_tela() {
    let h = Harness::start().await;
    h.post("/terminal", "").await;
    let (_, events, _) = h.pty.child(0);
    events
        .send(PtyEvent::Output(
            b"$ echo egeon-ok\r\negeon-ok\r\n\r\n$ ".to_vec(),
        ))
        .await
        .unwrap();
    eventually(|| async {
        let (_, body) = h.get("/peek?id=t1&lines=5").await;
        body["lines"] == json!(["$ echo egeon-ok", "egeon-ok", "$"])
    })
    .await;
    let (_, body) = h.get("/peek?target=t1&lines=1").await;
    assert_eq!(body, json!({"target": "t1", "lines": ["$"]}));
    let (status, body) = h.get("/peek?target=deck/t1").await;
    assert_eq!(status, 404);
    assert_eq!(body["error"], "alvo desconhecido 'deck/t1'");
    h.stop().await.unwrap();
}

#[tokio::test]
async fn resposta_da_tela_volta_ao_programa() {
    let h = Harness::start().await;
    h.post("/terminal", "").await;
    let (log, events, _) = h.pty.child(0);
    events
        .send(PtyEvent::Output(b"\x1b[6n".to_vec()))
        .await
        .unwrap();
    eventually(|| async { log.writes.lock().unwrap().as_slice() == b"\x1b[1;1R" }).await;
    h.stop().await.unwrap();
}

#[tokio::test]
async fn fim_do_processo_aparece_na_lista() {
    let h = Harness::start().await;
    h.post("/terminal", "").await;
    let (_, events, _) = h.pty.child(0);
    events
        .send(PtyEvent::Exited(PtyExit::Signal(9)))
        .await
        .unwrap();
    eventually(|| async {
        let (_, list) = h.get("/terminals").await;
        list["terminals"][0]["alive"] == false && list["terminals"][0]["exit_code"] == 137
    })
    .await;
    let (status, _) = h.post("/terminal/t1/input", "x").await;
    assert_eq!(status, 409);
    h.stop().await.unwrap();
}

#[tokio::test]
async fn segunda_instancia_nao_sobe_nem_mexe_na_primeira() {
    let local = Arc::new(FakeLocal::default());
    *local.probe.lock().unwrap() = Probe::Alive { pid: Some(77) };
    let h = Harness::start_with(local.clone()).await;
    let err = (&mut { h.task }).await.unwrap().unwrap_err();
    assert!(
        matches!(err, RuntimeError::AlreadyRunning { pid: Some(77), .. }),
        "{err}"
    );
    assert_eq!(
        local.listens.load(Ordering::SeqCst),
        0,
        "não pode abrir a escuta"
    );
}

#[tokio::test(start_paused = true)]
async fn vigia_religa_quando_o_arquivo_deixa_de_ser_nosso() {
    let h = Harness::start().await;
    eventually(|| async { h.local.listens.load(Ordering::SeqCst) == 1 }).await;
    h.local.current.store(false, Ordering::SeqCst);
    tokio::time::sleep(super::WATCH_EVERY + Duration::from_millis(10)).await;
    eventually(|| async { h.local.listens.load(Ordering::SeqCst) == 2 }).await;
    let (status, _) = h.get("/about").await;
    assert_eq!(status, 200);
    h.stop().await.unwrap();
}

#[tokio::test]
async fn encerrar_manda_hup_e_depois_kill_a_todos() {
    let h = Harness::start().await;
    h.post("/terminal", "").await;
    h.post("/terminal", "").await;
    let pty = h.pty.clone();
    h.stop().await.unwrap();
    for i in 0..2 {
        let (log, _, _) = pty.child(i);
        assert_eq!(
            *log.signals.lock().unwrap(),
            vec![PtySignal::Hangup, PtySignal::Terminate, PtySignal::Kill],
            "terminal {i}"
        );
    }
}

/// A árvore é lida e recebe o SIGTERM antes do HUP no shell, como em
/// `TerminalNode.prepareForRemoval`; o SIGKILL dos teimosos sai de uma thread,
/// depois de 2 s.
#[tokio::test]
async fn remover_o_no_mata_a_arvore_antes_do_shell() {
    let h = Harness::start().await;
    *h.procs.table.lock().unwrap() = vec![process(1000, 1, 4), process(2000, 1000, 5)];
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "create_terminal"})).await;
    assert_eq!(ui.recv().await["ok"], true);
    ui.send(json!({"id": 2, "cmd": "close_terminal", "node": "t1"}))
        .await;
    assert_eq!(ui.recv().await["ok"], true);

    let journal = h.pty.journal.clone();
    eventually(|| {
        let journal = journal.clone();
        async move { journal.lock().unwrap().len() == 4 }
    })
    .await;
    assert_eq!(
        *journal.lock().unwrap(),
        [
            "procs 2000 Terminate",
            "pty 1000 Hangup",
            "pty 1000 Terminate",
            "pty 1000 Kill"
        ]
    );
    h.stop().await.unwrap();
}

/// No encerramento o SIGKILL não fica para a thread de `terminate_tree`: ela
/// morreria com o processo. Sai daqui, depois do HUP, e só em quem ainda é o
/// mesmo processo (a conferência de pid e início está em `processes::tree`).
#[tokio::test]
async fn encerrar_mata_as_arvores_e_depois_quem_ignorou_o_sigterm() {
    let h = Harness::start().await;
    h.post("/terminal", "").await;
    h.post("/terminal", "").await;
    // 2000 e 2001 são do terminal 1000; os dois ignoram o SIGTERM (a tabela
    // não muda) e levam o SIGKILL.
    *h.procs.table.lock().unwrap() = vec![
        process(1000, 1, 4),
        process(2000, 1000, 5),
        process(2001, 2000, 6),
        process(1001, 1, 7),
    ];
    let (pty, procs) = (h.pty.clone(), h.procs.clone());
    h.stop().await.unwrap();

    let mut signals = procs.signals.lock().unwrap().clone();
    signals.sort_by_key(|(pid, signal)| (*pid, format!("{signal:?}")));
    assert_eq!(
        signals,
        [
            (2000, ProcessSignal::Kill),
            (2000, ProcessSignal::Terminate),
            (2001, ProcessSignal::Kill),
            (2001, ProcessSignal::Terminate),
        ]
    );
    let journal = pty.journal.lock().unwrap().clone();
    let at = |entry: &str| journal.iter().position(|e| e == entry).unwrap();
    assert!(
        at("procs 2000 Terminate") < at("pty 1000 Hangup"),
        "{journal:?}"
    );
    assert!(at("pty 1000 Kill") < at("procs 2000 Kill"), "{journal:?}");
    assert!(at("pty 1000 Kill") < at("procs 2001 Kill"), "{journal:?}");
}

#[tokio::test]
async fn ui_assina_a_tela_recebe_o_estado_e_depois_so_o_que_muda() {
    let h = Harness::start().await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "create_terminal", "cols": 20, "rows": 3}))
        .await;
    let created = ui.recv().await;
    assert_eq!(created["re"], 1);
    assert_eq!(created["ok"], true);
    assert_eq!(created["id"], "t1");

    let (_, events, _) = h.pty.child(0);
    // Saída antes de alguém assinar: vem dentro do quadro inteiro.
    events
        .send(PtyEvent::Output(b"antes\r\n".to_vec()))
        .await
        .unwrap();
    eventually(|| async {
        let (_, body) = h.get("/peek?id=t1").await;
        body["lines"] == json!(["antes"])
    })
    .await;

    ui.send(json!({"id": 2, "cmd": "subscribe", "topic": "screen/t1"}))
        .await;
    assert_eq!(ui.recv().await, json!({"re": 2, "ok": true}));
    let full = ui.recv().await;
    assert_eq!(full["topic"], "screen/t1");
    assert_eq!(full["kind"], "full");
    assert_eq!(full["cols"], 20);
    assert_eq!(full["lines"].as_array().unwrap().len(), 3);
    assert_eq!(full["lines"][0]["spans"][0]["text"], "antes");

    events
        .send(PtyEvent::Output(b"depois".to_vec()))
        .await
        .unwrap();
    let delta = ui.recv().await;
    assert_eq!(delta["kind"], "delta");
    assert_eq!(
        delta["lines"],
        json!([{"row": 1, "spans": [{"col": 0, "cells": 6, "text": "depois"}]}])
    );
    assert_eq!(delta["cursor"]["row"], 1);
    assert_eq!(delta["cursor"]["col"], 6);

    ui.send(json!({"id": 3, "cmd": "unsubscribe", "topic": "screen/t1"}))
        .await;
    assert_eq!(ui.recv().await, json!({"re": 3, "ok": true}));
    events.send(PtyEvent::Output(b"!".to_vec())).await.unwrap();
    ui.send(json!({"id": 4, "cmd": "list_terminals"})).await;
    // Sem assinatura, o próximo a chegar é a resposta, não um quadro.
    let list = ui.recv().await;
    assert_eq!(list["re"], 4);
    assert_eq!(list["terminals"][0]["id"], "t1");
    h.stop().await.unwrap();
}

#[tokio::test]
async fn ui_tecla_redimensiona_e_fecha() {
    let h = Harness::start().await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "create_terminal"})).await;
    ui.recv().await;
    let (log, _, _) = h.pty.child(0);

    ui.send(json!({"id": 2, "cmd": "key", "node": "t1", "key": "c", "mods": {"ctrl": true}}))
        .await;
    assert_eq!(ui.recv().await, json!({"re": 2, "ok": true}));
    ui.send(json!({"id": 3, "cmd": "key", "node": "t1", "key": "enter"}))
        .await;
    ui.recv().await;
    ui.send(json!({"id": 4, "cmd": "input", "node": "t1", "text": "ls"}))
        .await;
    ui.recv().await;
    assert_eq!(&*log.writes.lock().unwrap(), b"\x03\rls");

    ui.send(json!({"id": 5, "cmd": "resize", "node": "t1", "cols": 120, "rows": 40}))
        .await;
    assert_eq!(ui.recv().await, json!({"re": 5, "ok": true}));
    assert_eq!(
        *log.sizes.lock().unwrap(),
        vec![PtySize {
            cols: 120,
            rows: 40
        }]
    );
    ui.send(json!({"id": 6, "cmd": "resize", "node": "t1", "cols": 0, "rows": 40}))
        .await;
    assert_eq!(ui.recv().await["ok"], false);

    ui.send(json!({"id": 7, "cmd": "close_terminal", "node": "t1"}))
        .await;
    assert_eq!(ui.recv().await, json!({"re": 7, "ok": true}));
    eventually(|| async { log.signals.lock().unwrap().first() == Some(&PtySignal::Hangup) }).await;
    let (_, list) = h.get("/terminals").await;
    assert_eq!(list["terminals"], json!([]));
    h.stop().await.unwrap();
}

#[tokio::test]
async fn ui_erros_voltam_enderecados() {
    let h = Harness::start().await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "voar"})).await;
    let r = ui.recv().await;
    assert_eq!((r["re"].clone(), r["ok"].clone()), (json!(1), json!(false)));
    ui.reader.get_mut().write_all(b"{quebrado\n").await.unwrap();
    let r = ui.recv().await;
    assert_eq!((r["re"].clone(), r["ok"].clone()), (json!(0), json!(false)));
    ui.send(json!({"id": 2, "cmd": "subscribe", "topic": "screen/t9"}))
        .await;
    assert_eq!(
        ui.recv().await,
        json!({"re": 2, "ok": false, "error": "terminal desconhecido 't9'"})
    );
    ui.send(json!({"id": 3, "cmd": "input", "node": "t9", "text": "x"}))
        .await;
    assert_eq!(ui.recv().await["ok"], false);
    // Linha em branco não é comando e não ganha resposta.
    ui.reader.get_mut().write_all(b"\n\n").await.unwrap();
    ui.send(json!({"id": 4, "cmd": "list_terminals"})).await;
    assert_eq!(ui.recv().await["re"], 4);
    h.stop().await.unwrap();
}

#[tokio::test]
async fn ui_comandos_que_chegam_junto_do_upgrade() {
    let h = Harness::start().await;
    let mut s = h.local.connect().await;
    s.write_all(
        b"GET /ui HTTP/1.1\r\nUpgrade: egeon-ndjson\r\n\r\n{\"id\":1,\"cmd\":\"list_terminals\"}\n",
    )
    .await
    .unwrap();
    let mut reader = BufReader::new(s);
    let mut line = String::new();
    loop {
        line.clear();
        reader.read_line(&mut line).await.unwrap();
        if line == "\r\n" {
            break;
        }
    }
    line.clear();
    reader.read_line(&mut line).await.unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&line).unwrap(),
        json!({"re":1,"ok":true,"terminals":[]})
    );
    h.stop().await.unwrap();
}

#[tokio::test]
async fn ui_terminals_avisa_criacao_e_fim() {
    let h = Harness::start().await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "terminals"}))
        .await;
    assert_eq!(ui.recv().await, json!({"re": 1, "ok": true}));
    assert_eq!(
        ui.recv().await,
        json!({"topic": "terminals", "terminals": []})
    );
    h.post("/terminal", "").await;
    let ev = ui.recv().await;
    assert_eq!(ev["topic"], "terminals");
    assert_eq!(ev["terminals"][0]["alive"], true);
    let (_, events, _) = h.pty.child(0);
    events
        .send(PtyEvent::Exited(PtyExit::Code(3)))
        .await
        .unwrap();
    let ev = ui.recv().await;
    assert_eq!(ev["terminals"][0]["alive"], false);
    assert_eq!(ev["terminals"][0]["exit_code"], 3);
    h.stop().await.unwrap();
}

#[tokio::test]
async fn dois_clientes_veem_a_mesma_tela() {
    let h = Harness::start().await;
    h.post("/terminal", "").await;
    let mut a = h.ui().await;
    let mut b = h.ui().await;
    for ui in [&mut a, &mut b] {
        ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "screen/t1"}))
            .await;
        ui.recv().await;
        assert_eq!(ui.recv().await["kind"], "full");
    }
    let (_, events, _) = h.pty.child(0);
    events.send(PtyEvent::Output(b"oi".to_vec())).await.unwrap();
    for ui in [&mut a, &mut b] {
        let delta = ui.recv().await;
        assert_eq!(delta["lines"][0]["spans"][0]["text"], "oi");
    }
    h.stop().await.unwrap();
}

/// Cliente que não lê: os deltas que não cabem não travam o ator, e quando
/// houver espaço ele recebe a tela inteira. Chama o ator direto, um lote por
/// vez, para cada saída virar exatamente um quadro.
#[tokio::test]
async fn cliente_lento_perde_deltas_e_recebe_a_tela_inteira() {
    let home = TempHome::new();
    let drivers = Drivers {
        pty: Arc::new(FakePty::default()),
        screens: Arc::new(FakeScreens),
        local: Arc::new(FakeLocal::default()),
        procs: Arc::new(FakeProcs::default()),
        notifier: Arc::new(FakeNotifier::default()),
        apps: Arc::new(FakeApps),
        installer: Arc::new(FakeApps),
        opener: Arc::new(FakeOpener::default()),
        cloner: Arc::new(FakeCloner),
        links: Arc::new(FakeLinks),
        is_executable: fake_executable,
        folders: Arc::new(FakeFolders::default()),
    };
    let (inbox, _rx) = mpsc::channel(64);
    let mut actor = Actor::new(config(&home), drivers, inbox);

    let (queue, mut outbox) = mpsc::channel(2);
    let (tx, mut id) = oneshot::channel();
    let (alive, _hung_up) = oneshot::channel();
    actor.handle(Msg::UiOpen {
        queue,
        alive,
        reply: tx,
    });
    let client = id.try_recv().unwrap();
    let cmd = |id, kind| Msg::UiCommand {
        client,
        command: Command { id, kind },
    };
    actor.handle(cmd(1, CommandKind::CreateTerminal(Default::default())));
    outbox.try_recv().unwrap();
    actor.handle(cmd(
        2,
        CommandKind::Subscribe {
            topic: Topic::Screen(t("t1")),
        },
    ));
    outbox.try_recv().unwrap();
    outbox.try_recv().unwrap();

    let output = |text: &str| Msg::Pty {
        node: t("t1"),
        generation: 1,
        event: PtyEvent::Output(text.as_bytes().to_vec()),
    };
    // Fila de 2: o terceiro delta em diante não cabe, e o ator segue.
    for i in 0..6 {
        actor.handle(output(&format!("{i}\n")));
        actor.flush();
    }
    let kind = |line: Arc<[u8]>| serde_json::from_slice::<Value>(&line).unwrap()["kind"].clone();
    assert_eq!(kind(outbox.try_recv().unwrap()), "delta");
    assert_eq!(kind(outbox.try_recv().unwrap()), "delta");
    assert!(outbox.try_recv().is_err());

    // Com espaço, a próxima mudança chega como a tela inteira, já com tudo.
    actor.handle(output("fim"));
    actor.flush();
    let resync: Value = serde_json::from_slice(&outbox.try_recv().unwrap()).unwrap();
    assert_eq!(resync["kind"], "full");
    let text: Vec<&str> = resync["lines"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|l| l["spans"][0]["text"].as_str())
        .collect();
    assert_eq!(text.last(), Some(&"fim"));
    actor.handle(output("!"));
    actor.flush();
    assert_eq!(kind(outbox.try_recv().unwrap()), "delta");
}

/// O cliente que não lê a fila é desligado pelo ator, e a conexão fecha: ele
/// recebe EOF em vez de ficar mudo. Ao reconectar, assina de novo e recebe a
/// tela inteira.
#[tokio::test]
async fn cliente_derrubado_por_fila_cheia_recebe_eof_e_reconecta() {
    let h = Harness::start().await;
    h.post("/terminal", "").await;
    let mut slow = h.ui().await;
    slow.send(json!({"id": 1, "cmd": "subscribe", "topic": "terminals"}))
        .await;
    assert_eq!(slow.recv().await["ok"], true);
    slow.recv().await;

    flood_terminals(&h).await;

    let eof = tokio::time::timeout(Duration::from_secs(10), async {
        let mut line = String::new();
        loop {
            line.clear();
            if slow.reader.read_line(&mut line).await.unwrap() == 0 {
                return;
            }
        }
    })
    .await;
    assert!(eof.is_ok(), "o cliente desligado não recebeu EOF");

    let mut again = h.ui().await;
    again
        .send(json!({"id": 1, "cmd": "subscribe", "topic": "screen/t1"}))
        .await;
    assert_eq!(again.recv().await, json!({"re": 1, "ok": true}));
    assert_eq!(again.recv().await["kind"], "full");
    h.stop().await.unwrap();
}

/// Cliente que nunca lê: o escritor fica preso num `write`, e mesmo assim o
/// desligamento fecha a conexão — o que ele escreve depois dá cano quebrado.
#[tokio::test]
async fn cliente_que_nunca_le_e_desconectado() {
    let h = Harness::start().await;
    let mut slow = h.ui().await;
    slow.send(json!({"id": 1, "cmd": "subscribe", "topic": "terminals"}))
        .await;
    flood_terminals(&h).await;
    let closed = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            if slow.reader.get_mut().write_all(b"\n").await.is_err() {
                return;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await;
    assert!(closed.is_ok(), "a conexão do cliente desligado não fechou");
    h.stop().await.unwrap();
}

#[tokio::test]
async fn encerrar_fecha_as_conexoes_do_ui() {
    let h = Harness::start().await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "list_terminals"})).await;
    ui.recv().await;
    h.stop().await.unwrap();
    let mut line = String::new();
    let n = tokio::time::timeout(Duration::from_secs(5), ui.reader.read_line(&mut line))
        .await
        .expect("a conexão não fechou")
        .unwrap();
    assert_eq!(n, 0);
}

#[tokio::test]
async fn cabecalho_que_nao_termina_fecha_sem_resposta() {
    let h = Harness::start().await;
    let mut s = h.local.connect().await;
    s.write_all(b"GET /about HTTP/1.1\r\nHost: x")
        .await
        .unwrap();
    s.shutdown().await.unwrap();
    let mut out = Vec::new();
    s.read_to_end(&mut out).await.unwrap();
    assert!(out.is_empty(), "o Swift fechava sem responder");
    h.stop().await.unwrap();
}

#[tokio::test]
async fn ui_colagem_embrulha_so_com_o_bracketed_paste_ligado() {
    let h = Harness::start().await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "create_terminal"})).await;
    ui.recv().await;
    let (log, events, _) = h.pty.child(0);

    ui.send(json!({"id": 2, "cmd": "paste", "node": "t1", "text": "a\nb"}))
        .await;
    assert_eq!(ui.recv().await, json!({"re": 2, "ok": true}));
    assert_eq!(&*log.writes.lock().unwrap(), b"a\nb", "modo desligado: cru");
    log.writes.lock().unwrap().clear();

    // O programa liga o modo 2004; repete a colagem até o ator ter lido a
    // saída.
    events
        .send(PtyEvent::Output(b"\x1b[?2004h".to_vec()))
        .await
        .unwrap();
    assert!(paste_until(&mut ui, &log, "x", b"\x1b[200~x\x1b[201~").await);
    events
        .send(PtyEvent::Output(b"\x1b[?2004l".to_vec()))
        .await
        .unwrap();
    assert!(paste_until(&mut ui, &log, "y", b"y").await);

    ui.send(json!({"id": 5, "cmd": "paste", "node": "t9", "text": "z"}))
        .await;
    assert_eq!(ui.recv().await["ok"], false);
    h.stop().await.unwrap();
}

async fn paste_until(ui: &mut Ui, log: &super::fakes::ChildLog, text: &str, want: &[u8]) -> bool {
    for id in 100..400 {
        ui.send(json!({"id": id, "cmd": "paste", "node": "t1", "text": text}))
            .await;
        assert_eq!(ui.recv().await["re"], id);
        let got = std::mem::take(&mut *log.writes.lock().unwrap());
        if got == want {
            return true;
        }
        tokio::time::sleep(Duration::from_millis(2)).await;
    }
    false
}

/// Cada terminal novo empurra a lista inteira a quem assina `terminals`, e
/// isso não se descarta: com um cliente sem ler, o cano e a fila enchem e o
/// ator o desliga.
async fn flood_terminals(h: &Harness) {
    for _ in 0..300 {
        let (status, _) = h.post("/terminal", "").await;
        assert_eq!(status, 200);
    }
}

fn data_file(h: &Harness, name: &str) -> Value {
    serde_json::from_str(&std::fs::read_to_string(h._home.0.join("data").join(name)).unwrap())
        .unwrap()
}

fn deck_files(h_path: &std::path::Path) -> Vec<(&'static str, String)> {
    let benches = json!([{
        "id": "1a2b3c4d",
        "name": "deck",
        "path": h_path.to_string_lossy(),
        "nodes": [
            {"type": "shell", "id": "sh"},
            {"type": "agent", "id": "claude", "agent": "claude", "cwd": "nao-existe",
             "x": 10.0, "y": 20.0, "w": 300.0, "h": 200.0},
            {"type": "editor", "id": "code"}
        ],
        "edges": [{"from": "claude", "to": "sh"}],
        "tabOrder": 0,
        "tabActive": true
    }]);
    vec![("workbenches.json", benches.to_string())]
}

fn git_ok(args: &[&str], dir: &std::path::Path) -> bool {
    std::process::Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(args)
        .output()
        .is_ok_and(|o| o.status.success())
}

/// US-202: o clique na notificação ativa a bancada, foca o terminal no chat
/// e traz o app para a frente (main.swift:590).
#[tokio::test]
async fn clique_na_notificacao_ativa_a_bancada_e_foca_o_no() {
    let project = TempHome::new();
    let benches = json!([
        {"id": "1a2b3c4d", "name": "deck", "path": project.0.to_string_lossy(),
         "nodes": [{"type": "agent", "id": "claude", "agent": "claude"},
                   {"type": "shell", "id": "sh"}],
         "tabOrder": 0},
        {"id": "5e6f7a8b", "name": "outra", "path": project.0.to_string_lossy(),
         "nodes": [], "tabOrder": 1, "tabActive": true}
    ]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "app"}))
        .await;
    assert_eq!(ui.reply(1).await["ok"], true);
    // O foco é do chat da bancada, que existe quando alguém o abre.
    ui.send(json!({"id": 2, "cmd": "subscribe", "topic": "chat/1a2b3c4d"}))
        .await;
    assert_eq!(ui.reply(2).await["ok"], true);
    let click = h.notifier.clicks.lock().unwrap().clone().unwrap();
    click
        .send(NoticeClick {
            workbench: "deck".into(),
            node: "sh".into(),
        })
        .await
        .unwrap();
    ui.until(|v| v["topic"] == "app" && v["effect"] == "activate")
        .await;
    let (_, tabs) = h.get("/tabs").await;
    assert_eq!(tabs["active"], "deck", "{tabs}");
    let (_, chat) = h.get("/chat?target=deck").await;
    assert_eq!(chat["focus"], "sh", "{chat}");

    // Bancada fora da faixa: nada muda.
    click
        .send(NoticeClick {
            workbench: "sumiu".into(),
            node: "x".into(),
        })
        .await
        .unwrap();
    let (_, tabs) = h.get("/tabs").await;
    assert_eq!(tabs["active"], "deck");
    h.stop().await.unwrap();
}

/// US-301: a resposta de permissão do `/ui` vai pelo caminho do `POST
/// /permission/answer`. As três formas das fixtures chegam ao dispatch, que
/// recusa pedido que não existe com o texto da rota.
#[tokio::test]
async fn resposta_de_permissao_do_ui_vai_ao_dispatch() {
    let h = Harness::start().await;
    let mut ui = h.ui().await;
    let fixtures: Value =
        serde_json::from_str(include_str!("../../fixtures/protocol/commands.json")).unwrap();
    for (name, request) in [
        ("permission_answer", "p7"),
        ("permission_answer_escolha", "p8"),
        ("permission_answer_varias", "p9"),
    ] {
        let command = fixtures[name].clone();
        let id = command["id"].as_u64().unwrap();
        ui.send(command).await;
        let reply = ui.reply(id).await;
        assert_eq!(reply["ok"], false, "{name}: {reply}");
        assert_eq!(
            reply["error"],
            format!("pedido {request} já acabou, ou escolha fora das opções"),
            "{name}"
        );
    }
}

/// "+ Nova fila" (ADR-088): a fila nasce ligada ao agente pedido; agente que
/// não é da bancada é recusado; sem agente, a fila fica solta, como o Swift.
#[tokio::test]
async fn nova_fila_do_chat_nasce_ligada_ao_agente() {
    let project = TempHome::new();
    let benches = json!([{"id": "1a2b3c4d", "name": "deck", "path": project.0.to_string_lossy(),
                          "nodes": [{"type": "agent", "id": "claude", "agent": "claude"},
                                    {"type": "shell", "id": "sh"}]}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "chat_new_queue", "workbench": "1a2b3c4d", "agent": "sh"}))
        .await;
    assert_eq!(
        ui.reply(1).await["error"],
        "'sh' não é agente desta bancada"
    );
    ui.send(json!({"id": 2, "cmd": "chat_new_queue", "workbench": "1a2b3c4d", "agent": "claude"}))
        .await;
    let reply = ui.reply(2).await;
    let queue = reply["node"].as_str().unwrap().to_owned();
    let saved = saved_eventually(&h, |v| {
        v[0]["edges"].as_array().is_some_and(|e| !e.is_empty())
    })
    .await;
    assert_eq!(saved[0]["edges"][0]["from"], queue.as_str(), "{saved}");
    assert_eq!(saved[0]["edges"][0]["to"], "claude");

    // A rota de fora: mais uma fila, também ligada ao agente.
    // O agente em foco é do chat: com ele aberto, como no Swift.
    ui.send(json!({"id": 3, "cmd": "subscribe", "topic": "chat/1a2b3c4d"}))
        .await;
    assert_eq!(ui.reply(3).await["ok"], true);
    let (status, _) = h.get("/chat?target=deck&newqueue=1").await;
    assert_eq!(status, 200);
    let saved = saved_eventually(&h, |v| {
        v[0]["edges"].as_array().is_some_and(|e| e.len() == 2)
    })
    .await;
    assert_eq!(saved[0]["edges"][1]["to"], "claude", "{saved}");
    h.stop().await.unwrap();
}

/// Decisão 39: a bancada que abre empilha os nós sem frame com o tamanho do
/// canvas que a UI mandou no `ui_focus`, como o `defaultFrames` do Swift.
#[tokio::test]
async fn nos_sem_frame_usam_a_janela_da_ui_ao_abrir() {
    let project = TempHome::new();
    let benches = json!([{"id": "1a2b3c4d", "name": "deck", "path": project.0.to_string_lossy(),
                          "nodes": [{"type": "shell", "id": "a"}, {"type": "shell", "id": "b"}]}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "ui_focus", "app_active": true,
                   "window": {"w": 1440.0, "h": 1000.0}}))
        .await;
    assert_eq!(ui.reply(1).await["ok"], true);
    ui.send(json!({"id": 2, "cmd": "open_workbench", "workbench": "1a2b3c4d"}))
        .await;
    assert_eq!(ui.reply(2).await["ok"], true);
    ui.send(json!({"id": 3, "cmd": "subscribe", "topic": "workbench/1a2b3c4d/nodes"}))
        .await;
    let state = ui
        .until(|v| v["topic"] == "workbench/1a2b3c4d/nodes" && v["nodes"][1]["frame"].is_object())
        .await;
    // Largura 1440 − 80; altura (1000 − 80 − 16) / 2.
    assert_eq!(
        state["nodes"][1]["frame"],
        json!({"x": 40.0, "y": 508.0, "w": 1360.0, "h": 452.0}),
        "{state}"
    );
}

/// Decisão 39: a pasta que o sistema não deixa ler trava a bancada; "pedir
/// de novo" confere outra vez; liberada, a cortina sai na releitura. Os
/// botões não abrem nada na tela (o `FakeOpener` só anota).
#[tokio::test]
async fn cortina_sem_acesso_trava_e_destrava_a_bancada() {
    use std::os::unix::fs::PermissionsExt;
    let dir = TempHome::new();
    let folder = dir.0.join("fechada");
    std::fs::create_dir_all(&folder).unwrap();
    std::fs::set_permissions(&folder, std::fs::Permissions::from_mode(0o000)).unwrap();
    let benches = json!([{"id": "1a2b3c4d", "name": "deck", "path": folder.to_string_lossy(),
                          "nodes": []}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "workspaces"}))
        .await;
    let tree = ui.until(|v| v["topic"] == "workspaces").await;
    assert!(
        bench(&tree, "1a2b3c4d")["access"]["message"]
            .as_str()
            .unwrap()
            .starts_with("Sem acesso a esta pasta"),
        "{tree}"
    );
    ui.send(json!({"id": 2, "cmd": "access_ask_again", "workbench": "1a2b3c4d"}))
        .await;
    let again = ui.reply(2).await;
    assert_eq!(again["access"], "denied", "{again}");
    ui.send(json!({"id": 3, "cmd": "access_open_settings", "workbench": "1a2b3c4d"}))
        .await;
    assert_eq!(ui.reply(3).await["ok"], true);

    std::fs::set_permissions(&folder, std::fs::Permissions::from_mode(0o755)).unwrap();
    let freed = ui
        .until(|v| v["topic"] == "workspaces" && bench(v, "1a2b3c4d")["access"].is_null())
        .await;
    assert!(bench(&freed, "1a2b3c4d")["access"].is_null());
    h.stop().await.unwrap();
}

/// O `restartAgents` do Swift ao destravar: liberada a pasta, todo agente
/// da bancada sobe de novo (o que subiu com ela negada estava fora dela), e
/// o shell fica como estava.
#[tokio::test]
async fn destravar_reergue_os_agentes_e_nao_os_shells() {
    use std::os::unix::fs::PermissionsExt;
    let dir = TempHome::new();
    let folder = dir.0.join("fechada");
    std::fs::create_dir_all(&folder).unwrap();
    std::fs::set_permissions(&folder, std::fs::Permissions::from_mode(0o000)).unwrap();
    let benches = json!([{"id": "1a2b3c4d", "name": "deck", "path": folder.to_string_lossy(),
                          "nodes": [{"type": "agent", "id": "a", "agent": "claude"},
                                    {"type": "shell", "id": "s"}],
                          "tabOrder": 0, "tabActive": true}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let spawns = |pty: &FakePty, address: &str| {
        pty.spawned
            .lock()
            .unwrap()
            .iter()
            .filter(|s| {
                s.spec
                    .env
                    .iter()
                    .any(|(k, v)| k == "EGEON_NODE" && v == address)
            })
            .count()
    };
    let pty = h.pty.clone();
    eventually(|| {
        let pty = pty.clone();
        async move { spawns(&pty, "deck/a") == 1 && spawns(&pty, "deck/s") == 1 }
    })
    .await;

    std::fs::set_permissions(&folder, std::fs::Permissions::from_mode(0o755)).unwrap();
    // A releitura de acesso é a cada 2 s: espera mais que o `eventually`.
    let deadline = std::time::Instant::now() + Duration::from_secs(8);
    while spawns(&h.pty, "deck/a") < 2 {
        assert!(
            std::time::Instant::now() < deadline,
            "o agente não subiu de novo"
        );
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    assert_eq!(spawns(&h.pty, "deck/s"), 1, "o shell não sobe de novo");
    h.stop().await.unwrap();
}

/// A seção FILAS do chat: quem assina `chat/<bancada>` recebe as filas da
/// bancada, com o resumo pronto, no reset.
#[tokio::test]
async fn o_chat_lista_as_filas_da_bancada_no_reset() {
    let project = TempHome::new();
    let benches = json!([{
        "id": "1a2b3c4d",
        "name": "deck",
        "path": project.0.to_string_lossy(),
        "nodes": [
            {"type": "agent", "id": "claude", "agent": "claude"},
            {"type": "queue", "id": "fila1"}
        ],
        "tabOrder": 0,
        "tabActive": true
    }]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "chat/1a2b3c4d"}))
        .await;
    let reset = ui
        .until(|v| v["topic"] == "chat/1a2b3c4d" && v["ops"][0]["op"] == "reset")
        .await;
    let queues = reset["ops"]
        .as_array()
        .unwrap()
        .iter()
        .find(|op| op["op"] == "queues")
        .expect("o reset leva as filas");
    assert_eq!(
        queues["list"],
        json!([{"id": "fila1", "summary": "nada pendente", "asking": false}])
    );
    h.stop().await.unwrap();
}

/// A herança de confiança do Claude (ADR-071) corre antes de o terminal subir e
/// só grava num `.claude.json` de dentro da pasta de dados enquanto o app é o
/// novo (decisão 36): a worktree com a origem aceita herda no config de dentro
/// e o de fora, que seria o `~/.claude*` do usuário, fica como estava.
#[tokio::test]
async fn heranca_de_confianca_grava_so_dentro_da_pasta_de_dados() {
    use crate::features::agent::claude::trust_seeder::real;
    let project = TempHome::new();
    let repo = project.0.join("app");
    std::fs::create_dir_all(&repo).unwrap();
    if !git_ok(&["init", "-q"], &repo) {
        return; // sem git na máquina não há o que provar
    }
    assert!(git_ok(
        &[
            "-c",
            "user.email=a@b",
            "-c",
            "user.name=a",
            "commit",
            "-q",
            "--allow-empty",
            "-m",
            "x"
        ],
        &repo
    ));
    let worktree = project.0.join("wt");
    assert!(git_ok(
        &[
            "worktree",
            "add",
            "-q",
            "-b",
            "b1",
            worktree.to_str().unwrap()
        ],
        &repo
    ));
    let accepted = json!({"projects": {real(&repo): {"hasTrustDialogAccepted": true}}}).to_string();
    let outside = project.0.join("claude-out");
    std::fs::create_dir_all(&outside).unwrap();
    std::fs::write(outside.join(".claude.json"), &accepted).unwrap();
    let h = Harness::start_with_data(|data| {
        let inside = data.join("claude-in");
        let benches = json!([{
            "id": "1a2b3c4d",
            "name": "deck",
            "path": worktree.to_string_lossy(),
            "nodes": [
                {"type": "agent", "id": "in", "agent": "claude",
                 "cwd": worktree.to_string_lossy(), "config": inside.to_string_lossy()},
                {"type": "agent", "id": "out", "agent": "claude",
                 "cwd": worktree.to_string_lossy(), "config": outside.to_string_lossy()}
            ],
            "tabOrder": 0,
            "tabActive": true
        }]);
        vec![
            ("workbenches.json".to_owned(), benches.to_string()),
            ("claude-in/.claude.json".to_owned(), accepted.clone()),
        ]
    })
    .await;
    let inside = h._home.0.join("data/claude-in");
    let pty = h.pty.clone();
    eventually(|| {
        let pty = pty.clone();
        async move { pty.spawned.lock().unwrap().len() == 2 }
    })
    .await;

    let read = |dir: &std::path::Path| -> Value {
        serde_json::from_str(&std::fs::read_to_string(dir.join(".claude.json")).unwrap()).unwrap()
    };
    let key = real(&worktree);
    assert_eq!(
        read(&inside)["projects"][&key]["hasTrustDialogAccepted"],
        true,
        "dentro da pasta de dados: herdou"
    );
    assert!(
        read(&outside)["projects"].get(&key).is_none(),
        "fora dela: não toca"
    );
    h.stop().await.unwrap();
}

/// A partida carrega o `workbenches.json`, concilia (sem workspaces, nasce o
/// "Geral") e grava de volta o que a carga decidiu — a cor, o projeto.
#[tokio::test]
async fn partida_carrega_concilia_e_grava_as_bancadas() {
    let project = TempHome::new();
    let h = Harness::start_with_files(&deck_files(&project.0)).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "workspaces"}))
        .await;
    assert_eq!(ui.recv().await["ok"], true);
    let tree = ui.recv().await;
    assert_eq!(tree["topic"], "workspaces");
    let bench = &tree["workbenches"][0];
    assert_eq!(bench["id"], "1a2b3c4d");
    assert_eq!(bench["name"], "deck");
    assert_eq!(bench["tab_order"], 0);
    assert_eq!(bench["tab_active"], true);
    assert_eq!(bench["exists"], true);
    assert_eq!(bench["agents"], 1);
    assert!(bench["color"].is_string(), "{bench}");
    let spaces = tree["workspaces"].as_array().unwrap();
    assert_eq!(spaces.len(), 1, "{tree}");
    let owned: Vec<&Value> = spaces[0]["projects"]
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|p| p["workbenches"].as_array().unwrap())
        .collect();
    assert_eq!(owned, [&json!("1a2b3c4d")], "{tree}");

    // O que a carga decidiu foi para o disco: sem isso a cor e o projeto
    // mudariam a cada partida.
    let saved = data_file(&h, "workbenches.json");
    assert_eq!(saved[0]["color"], bench["color"]);
    assert!(saved[0]["project"].is_string(), "{saved}");
    assert_eq!(
        data_file(&h, "workspaces.json")[0]["projects"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    h.stop().await.unwrap();
}

/// O canvas de uma bancada: o editor retirado some (RetiredNode), o `cwd`
/// que não existe aparece marcado, e as arestas chegam colapsadas por par.
#[tokio::test]
async fn nos_da_bancada_com_cwd_inexistente_e_ligacoes_colapsadas() {
    let project = TempHome::new();
    let h = Harness::start_with_files(&deck_files(&project.0)).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "workbench/1a2b3c4d/nodes"}))
        .await;
    assert_eq!(ui.recv().await["ok"], true);
    // O agente sobe depois de gravar a confiança (ADR-071), fora do ator: o
    // retrato vivo pode vir no segundo envio.
    let state = ui
        .until(|v| v["topic"] == "workbench/1a2b3c4d/nodes" && v["nodes"][1]["alive"] == true)
        .await;
    let ids: Vec<&Value> = state["nodes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|n| &n["id"])
        .collect();
    assert_eq!(ids, [&json!("sh"), &json!("claude")]);
    let claude = &state["nodes"][1];
    assert_eq!(claude["type"], "agent");
    assert_eq!(claude["exists"], false);
    // A bancada estava na frente: os terminais dela subiram na partida.
    assert_eq!(claude["alive"], true);
    assert_eq!(claude["screen"], "1a2b3c4d.claude");
    assert_eq!(
        claude["frame"],
        json!({"x": 10.0, "y": 20.0, "w": 300.0, "h": 200.0})
    );
    assert_eq!(state["nodes"][0]["exists"], true);
    assert_eq!(
        state["links"],
        // Aresta gravada sem `maxSends` ganha o limite padrão da casa, como no
        // Swift.
        json!([{"a": "claude", "b": "sh", "a_to_b": true, "b_to_a": false, "max_sends": 2}])
    );

    ui.send(json!({"id": 2, "cmd": "subscribe", "topic": "workbench/ffffffff/nodes"}))
        .await;
    let refused = ui.reply(2).await;
    assert_eq!(refused["ok"], false);
    assert_eq!(refused["error"], "bancada desconhecida 'ffffffff'");
    h.stop().await.unwrap();
}

/// Sem arquivo nenhum o core sobe vazio, com o "Geral", e não inventa
/// bancada.
#[tokio::test]
async fn sem_arquivos_sobe_so_com_o_geral() {
    let h = Harness::start().await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "workspaces"}))
        .await;
    ui.recv().await;
    let tree = ui.recv().await;
    assert_eq!(tree["workbenches"], json!([]));
    assert_eq!(tree["workspaces"].as_array().unwrap().len(), 1);
    h.stop().await.unwrap();
}

fn two_benches(dir: &std::path::Path) -> Vec<(&'static str, String)> {
    let benches = json!([
        {"id": "1a2b3c4d", "name": "deck", "path": dir.to_string_lossy(),
         "nodes": [{"type": "shell", "id": "sh"}, {"type": "agent", "id": "claude", "agent": "claude"}],
         "tabOrder": 0, "tabActive": true},
        {"id": "5e6f7a8b", "name": "outra", "path": dir.to_string_lossy(), "nodes": []}
    ]);
    vec![("workbenches.json", benches.to_string())]
}

async fn saved_eventually(h: &Harness, check: impl Fn(&Value) -> bool) -> Value {
    let path = h._home.0.join("data/workbenches.json");
    for _ in 0..500 {
        if let Ok(text) = std::fs::read_to_string(&path)
            && let Ok(value) = serde_json::from_str::<Value>(&text)
            && check(&value)
        {
            return value;
        }
        tokio::time::sleep(Duration::from_millis(4)).await;
    }
    panic!("a gravação esperada não chegou ao disco");
}

fn bench<'a>(tree: &'a Value, id: &str) -> &'a Value {
    tree["workbenches"]
        .as_array()
        .unwrap()
        .iter()
        .find(|b| b["id"] == id)
        .unwrap()
}

/// O ator não pergunta ao disco ao montar a árvore: a pasta apagada com o
/// app de pé aparece na próxima releitura, feita fora dele.
#[tokio::test]
async fn pasta_apagada_aparece_na_arvore_sem_o_ator_ler_o_disco() {
    let dir = TempHome::new();
    let folder = dir.0.join("projeto");
    std::fs::create_dir_all(&folder).unwrap();
    let benches = json!([{"id": "1a2b3c4d", "name": "deck", "path": folder.to_string_lossy(),
                          "nodes": [{"type": "shell", "id": "sh"}]}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "workspaces"}))
        .await;
    let tree = ui.until(|v| v["topic"] == "workspaces").await;
    assert_eq!(bench(&tree, "1a2b3c4d")["exists"], true);
    std::fs::remove_dir_all(&folder).unwrap();
    let gone = ui
        .until(|v| v["topic"] == "workspaces" && bench(v, "1a2b3c4d")["exists"] == false)
        .await;
    assert_eq!(bench(&gone, "1a2b3c4d")["exists"], false);
    h.stop().await.unwrap();
}

/// Abrir põe a aba no fim e na frente; fechar devolve a frente à vizinha; a
/// faixa vai para o disco como `tabOrder`/`tabActive`, para reabrir igual.
#[tokio::test]
async fn abas_abrem_fecham_e_voltam_ao_disco() {
    let dir = TempHome::new();
    let h = Harness::start_with_files(&two_benches(&dir.0)).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "workspaces"}))
        .await;
    ui.until(|v| v["topic"] == "workspaces").await;

    ui.send(json!({"id": 2, "cmd": "activate_workbench", "workbench": "5e6f7a8b"}))
        .await;
    assert_eq!(ui.reply(2).await["error"], "'outra' não está na faixa");

    ui.send(json!({"id": 3, "cmd": "open_workbench", "workbench": "5e6f7a8b"}))
        .await;
    let tree = ui
        .until(|v| v["topic"] == "workspaces" && bench(v, "5e6f7a8b")["tab_active"] == true)
        .await;
    assert_eq!(bench(&tree, "5e6f7a8b")["tab_order"], 1);
    assert_eq!(bench(&tree, "5e6f7a8b")["tab_active"], true);
    assert_eq!(bench(&tree, "1a2b3c4d")["tab_active"], false);
    assert_eq!(ui.reply(3).await["ok"], true);
    saved_eventually(&h, |v| v[1]["tabOrder"] == 1 && v[1]["tabActive"] == true).await;

    ui.send(json!({"id": 4, "cmd": "move_tab", "workbench": "5e6f7a8b", "to": 0}))
        .await;
    let tree = ui
        .until(|v| v["topic"] == "workspaces" && bench(v, "5e6f7a8b")["tab_order"] == 0)
        .await;
    assert_eq!(bench(&tree, "5e6f7a8b")["tab_order"], 0);
    assert_eq!(bench(&tree, "1a2b3c4d")["tab_order"], 1);

    ui.send(json!({"id": 5, "cmd": "close_workbench", "workbench": "5e6f7a8b"}))
        .await;
    let tree = ui
        .until(|v| v["topic"] == "workspaces" && bench(v, "5e6f7a8b").get("tab_order").is_none())
        .await;
    assert!(
        bench(&tree, "5e6f7a8b").get("tab_order").is_none(),
        "{tree}"
    );
    assert_eq!(bench(&tree, "1a2b3c4d")["tab_active"], true);
    assert_eq!(ui.reply(5).await["ok"], true);
    let saved = saved_eventually(&h, |v| v[1].get("tabOrder").is_none()).await;
    assert_eq!(saved[0]["tabOrder"], 0);
    assert_eq!(saved[0]["tabActive"], true);
    h.stop().await.unwrap();
}

/// Renomear passa pelo nome livre, como no Swift; cor e modo vão juntos.
#[tokio::test]
async fn renomear_usa_o_nome_livre_e_grava() {
    let dir = TempHome::new();
    let h = Harness::start_with_files(&two_benches(&dir.0)).await;
    let mut ui = h.ui().await;
    ui.send(
        json!({"id": 1, "cmd": "set_workbench", "workbench": "5e6f7a8b",
                   "name": " deck ", "color": "teal", "view": "chat"}),
    )
    .await;
    assert_eq!(ui.reply(1).await["ok"], true);
    let saved = saved_eventually(&h, |v| v[1]["name"] == "deck-2").await;
    assert_eq!(saved[1]["color"], "teal");
    assert_eq!(saved[1]["view"], "chat");

    ui.send(
        json!({"id": 2, "cmd": "set_workbench", "workbench": "5e6f7a8b", "color": "roxo-neon"}),
    )
    .await;
    let refused = ui.reply(2).await;
    assert_eq!(refused["ok"], false);
    assert_eq!(refused["error"], "cor desconhecida 'roxo-neon'");
    assert!(refused["palette"].is_array());

    ui.send(json!({"id": 3, "cmd": "set_workbench_rules", "workbench": "1a2b3c4d", "rules": "  "}))
        .await;
    assert_eq!(ui.reply(3).await["ok"], true);
    ui.send(json!({"id": 4, "cmd": "set_workbench", "workbench": "ffffffff", "name": "x"}))
        .await;
    assert_eq!(
        ui.reply(4).await["error"],
        "bancada desconhecida 'ffffffff'"
    );
    h.stop().await.unwrap();
}

/// O canvas: o card gravado onde foi solto, e a ligação criada, com limite e
/// direção trocados, refletida no tópico e no disco.
#[tokio::test]
async fn cards_e_ligacoes_mudam_no_topico_e_no_disco() {
    let dir = TempHome::new();
    let h = Harness::start_with_files(&two_benches(&dir.0)).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "workbench/1a2b3c4d/nodes"}))
        .await;
    ui.until(|v| v["topic"] == "workbench/1a2b3c4d/nodes").await;

    ui.send(
        json!({"id": 2, "cmd": "move_node", "workbench": "1a2b3c4d", "node": "sh",
                   "frame": {"x": 10.4, "y": 20.0, "w": 300.0, "h": 200.0}}),
    )
    .await;
    // O agente que sobe depois da confiança também republica: espera a
    // mudança, não o primeiro envio.
    let state = ui
        .until(|v| v["topic"] == "workbench/1a2b3c4d/nodes" && v["nodes"][0]["frame"]["x"] == 10.0)
        .await;
    // O Swift grava arredondado.
    assert_eq!(
        state["nodes"][0]["frame"],
        json!({"x": 10.0, "y": 20.0, "w": 300.0, "h": 200.0})
    );

    ui.send(json!({"id": 3, "cmd": "link", "workbench": "1a2b3c4d", "from": "claude", "to": "sh"}))
        .await;
    let state = ui
        .until(|v| {
            v["topic"] == "workbench/1a2b3c4d/nodes"
                && v["links"].as_array().is_some_and(|l| !l.is_empty())
        })
        .await;
    assert_eq!(
        state["links"],
        json!([{"a": "claude", "b": "sh", "a_to_b": true, "b_to_a": false, "max_sends": 2}])
    );
    ui.send(
        json!({"id": 4, "cmd": "set_edge", "workbench": "1a2b3c4d", "from": "claude",
                   "to": "sh", "direction": "<->", "max_sends": 5}),
    )
    .await;
    let reply = ui.reply(4).await;
    assert_eq!(reply["ok"], true, "{reply}");
    ui.send(json!({"id": 5, "cmd": "subscribe", "topic": "workbench/1a2b3c4d/nodes"}))
        .await;
    let state = ui.until(|v| v["topic"] == "workbench/1a2b3c4d/nodes").await;
    assert_eq!(state["links"][0]["a_to_b"], true);
    assert_eq!(state["links"][0]["b_to_a"], true);
    assert_eq!(state["links"][0]["max_sends"], 5);

    ui.send(json!({"id": 6, "cmd": "link", "workbench": "1a2b3c4d", "from": "sh", "to": "sh"}))
        .await;
    assert_eq!(ui.reply(6).await["error"], "um nó não liga a si mesmo");

    ui.send(
        json!({"id": 7, "cmd": "unlink", "workbench": "1a2b3c4d", "from": "claude",
                   "to": "sh", "both": true}),
    )
    .await;
    assert_eq!(ui.reply(7).await["ok"], true);
    let saved = saved_eventually(&h, |v| {
        v[0]["edges"].as_array().is_some_and(|e| e.is_empty())
    })
    .await;
    assert_eq!(saved[0]["nodes"][0]["x"], 10.0);
    h.stop().await.unwrap();
}

/// Mover na árvore: o pedido inválido volta com o erro do Swift, e o
/// `plan_move` responde sem mexer em nada.
#[tokio::test]
async fn mover_na_arvore_e_planejar_sem_mexer() {
    let dir = TempHome::new();
    let h = Harness::start_with_files(&two_benches(&dir.0)).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "move", "kind": "teleporte", "item": "x", "to": 0}))
        .await;
    let refused = ui.reply(1).await;
    assert_eq!(refused["ok"], false, "{refused}");

    ui.send(json!({"id": 2, "cmd": "subscribe", "topic": "workspaces"}))
        .await;
    let tree = ui.until(|v| v["topic"] == "workspaces").await;
    let space = tree["workspaces"][0]["id"].as_str().unwrap().to_owned();
    ui.send(json!({"id": 3, "cmd": "plan_move", "kind": "drawer", "item": space, "to": 0}))
        .await;
    let plan = ui.reply(3).await;
    assert_eq!(plan["ok"], true, "{plan}");
    assert_eq!(plan["lands"]["to"], 0);
    ui.send(json!({"id": 4, "cmd": "subscribe", "topic": "workspaces"}))
        .await;
    let after = ui.until(|v| v["topic"] == "workspaces").await;
    assert_eq!(
        after["workspaces"][0]["stored_open"],
        tree["workspaces"][0]["stored_open"]
    );

    ui.send(json!({"id": 5, "cmd": "move", "kind": "drawer", "item": space, "to": 0}))
        .await;
    let before = tree["workspaces"][0]["stored_open"].clone();
    let toggled = ui
        .until(|v| v["topic"] == "workspaces" && v["workspaces"][0]["stored_open"] != before)
        .await;
    assert_ne!(
        toggled["workspaces"][0]["stored_open"],
        tree["workspaces"][0]["stored_open"]
    );
    h.stop().await.unwrap();
}

/// Erro quer dizer que nada mudou: a cor recusada não deixa o modo entrar, e
/// nome em branco é ignorado sem erro, como o `renameWorkbench` do Swift.
#[tokio::test]
async fn set_workbench_valida_tudo_antes_de_mexer() {
    let dir = TempHome::new();
    let h = Harness::start_with_files(&two_benches(&dir.0)).await;
    let mut ui = h.ui().await;
    ui.send(
        json!({"id": 1, "cmd": "set_workbench", "workbench": "5e6f7a8b",
                   "color": "roxo-neon", "view": "chat", "name": "nova"}),
    )
    .await;
    assert_eq!(ui.reply(1).await["ok"], false);
    ui.send(json!({"id": 2, "cmd": "subscribe", "topic": "workspaces"}))
        .await;
    let tree = ui.until(|v| v["topic"] == "workspaces").await;
    assert_eq!(bench(&tree, "5e6f7a8b")["view"], "canvas", "{tree}");
    assert_eq!(bench(&tree, "5e6f7a8b")["name"], "outra");

    ui.send(
        json!({"id": 3, "cmd": "set_workbench", "workbench": "5e6f7a8b",
                   "name": "   ", "view": "chat"}),
    )
    .await;
    assert_eq!(ui.reply(3).await["ok"], true);
    let saved = saved_eventually(&h, |v| v[1]["view"] == "chat").await;
    assert_eq!(saved[1]["name"], "outra");
    h.stop().await.unwrap();
}

fn env_of<'a>(spec: &'a crate::ports::pty::PtySpec, key: &str) -> Option<&'a str> {
    spec.env
        .iter()
        .find(|(k, _)| k == key)
        .map(|(_, v)| v.as_str())
}

/// A bancada da frente sobe os terminais dos nós na partida, com a linha e o
/// ambiente do Swift: procedência em todo nó, `ZDOTDIR` no shell, o alvo dos
/// ganchos no agente; e o gancho do zsh escrito na pasta de dados.
#[tokio::test]
async fn terminais_dos_nos_sobem_com_o_ambiente_do_swift() {
    let project = TempHome::new();
    let h = Harness::start_with_files(&deck_files(&project.0)).await;
    let pty = h.pty.clone();
    eventually(|| {
        let pty = pty.clone();
        async move { pty.spawned.lock().unwrap().len() == 2 }
    })
    .await;
    let (_, _, shell) = h.pty.child(0);
    let (_, _, agent) = h.pty.child(1);
    let dir = project.0.to_string_lossy().into_owned();
    assert_eq!(shell.program, PathBuf::from("/bin/zsh"));
    assert!(
        shell.args[1].starts_with(&format!("cd '{dir}'; clear; ")),
        "{:?}",
        shell.args
    );
    assert_eq!(env_of(&shell, "EGEON_NODE"), Some("deck/sh"));
    assert_eq!(env_of(&shell, "EGEON_DECK"), Some("egeon-next"));
    // O sabor estável não exporta `EGEON_FLAVOR`, nem vazio.
    assert_eq!(env_of(&shell, "EGEON_FLAVOR"), None);
    let zsh = h._home.0.join("data/zsh");
    assert_eq!(
        env_of(&shell, "ZDOTDIR"),
        Some(zsh.to_string_lossy().as_ref())
    );
    assert!(zsh.join(".zshrc").exists());
    // O `--settings` do agente aponta para os ganchos, escritos na partida.
    let hooks = h._home.0.join("data/claude-hooks.json");
    assert!(hooks.exists(), "claude-hooks.json não foi escrito");
    assert_eq!(
        env_of(&shell, "EGEON_TARGET"),
        None,
        "shell não tem conversa"
    );

    assert_eq!(env_of(&agent, "EGEON_NODE"), Some("deck/claude"));
    assert_eq!(env_of(&agent, "EGEON_TARGET"), Some("deck/claude"));
    assert_eq!(env_of(&agent, "ZDOTDIR"), None);
    // O cwd que não existe cai na raiz da bancada, falando no log.
    assert!(
        agent.args[1].starts_with(&format!("cd '{dir}'; clear; ")),
        "{:?}",
        agent.args
    );

    let (_, list) = h.get("/terminals").await;
    let ids: Vec<&Value> = list["terminals"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| &t["id"])
        .collect();
    assert_eq!(ids, [&json!("1a2b3c4d.claude"), &json!("1a2b3c4d.sh")]);

    // Reabrir a aba não relança ninguém.
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "open_workbench", "workbench": "1a2b3c4d"}))
        .await;
    assert_eq!(ui.reply(1).await["ok"], true);
    assert_eq!(h.pty.spawned.lock().unwrap().len(), 2);
    h.stop().await.unwrap();
}

/// `egeon peek bancada/nó`: de fora (um `curl`, você), o endereço resolve e
/// a tela volta; alvo que não existe é 404, como o ControlSocket.swift:744.
#[tokio::test]
async fn peek_por_endereco_de_fora() {
    let project = TempHome::new();
    let h = Harness::start_with_files(&deck_files(&project.0)).await;
    let pty = h.pty.clone();
    eventually(|| {
        let pty = pty.clone();
        async move { pty.spawned.lock().unwrap().len() == 2 }
    })
    .await;
    let (_, events, _) = h.pty.child(0);
    events
        .send(PtyEvent::Output(b"pronto\r\n".to_vec()))
        .await
        .unwrap();
    eventually(|| async {
        let (status, body) = h.get("/peek?target=deck/sh&lines=5").await;
        status == 200 && body["lines"] == json!(["pronto"])
    })
    .await;
    let (status, body) = h.get("/peek?target=deck/fantasma").await;
    assert_eq!(status, 404, "{body}");
    assert_eq!(body["error"], "alvo desconhecido 'deck/fantasma'");
    h.stop().await.unwrap();
}

/// CLI sem flag de system prompt: o papel não se perde — entra pela fila do
/// dispatch como primeira mensagem (TerminalNode.swift:326).
#[tokio::test]
async fn papel_de_cli_sem_flag_de_system_prompt_vai_pela_fila() {
    let project = TempHome::new();
    let benches = json!([{
        "id": "1a2b3c4d", "name": "deck", "path": project.0.to_string_lossy(),
        "nodes": [{"type": "agent", "id": "rev", "agent": "simples", "prompt": "você revisa o core"}],
        "tabOrder": 0, "tabActive": true
    }]);
    // Silêncio curto e sem aquecimento: o teste não espera os 5,5 s do
    // perfil padrão.
    let agents = json!({"simples": {
        "displayName": "Simples", "command": ["simples-cli"],
        "idle": {"ms": 100, "warmupMs": 0}
    }});
    let h = Harness::start_with_files(&[
        ("workbenches.json", benches.to_string()),
        ("agents.json", agents.to_string()),
    ])
    .await;
    let pty = h.pty.clone();
    eventually(|| {
        let pty = pty.clone();
        async move { pty.spawned.lock().unwrap().len() == 1 }
    })
    .await;
    let (log, events, spec) = h.pty.child(0);
    assert!(spec.args[1].ends_with("simples-cli"), "{:?}", spec.args);
    // A entrega espera ver a TUI desenhar (ADR-008).
    events
        .send(PtyEvent::Output(b"simples> ".to_vec()))
        .await
        .unwrap();
    // A injeção espera a TUI quieta; o relógio do dispatch anda de 250 em 250 ms.
    let mut delivered = false;
    for _ in 0..60 {
        let written = String::from_utf8_lossy(&log.writes.lock().unwrap()).into_owned();
        if written.contains("você revisa o core") {
            delivered = true;
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert!(delivered, "o papel não chegou ao terminal");
    h.stop().await.unwrap();
}

// ── Criar, configurar e remover nó (org, `node_commands.rs`) ───────────────

/// O nó novo ganha id livre, o web nasce na página inicial, e a bancada é
/// gravada; o componente entra pelo nome e o desconhecido é recusado.
#[tokio::test]
async fn criar_no_da_id_livre_e_grava() {
    let dir = TempHome::new();
    let mut files = two_benches(&dir.0);
    files.push((
        "components.json",
        json!({"Revisor": {"name": "Revisor", "kind": "shell", "cmd": "make"}}).to_string(),
    ));
    let h = Harness::start_with_files(&files).await;
    let mut ui = h.ui().await;

    ui.send(json!({"id": 1, "cmd": "create_node", "workbench": "1a2b3c4d", "type": "shell"}))
        .await;
    assert_eq!(ui.reply(1).await["node"], "sh-2");
    ui.send(json!({"id": 2, "cmd": "create_node", "workbench": "1a2b3c4d", "type": "web"}))
        .await;
    assert_eq!(ui.reply(2).await["node"], "web");
    ui.send(
        json!({"id": 3, "cmd": "create_node", "workbench": "1a2b3c4d", "type": "queue",
                   "frame": {"x": 5.0, "y": 6.0, "w": 540.0, "h": 700.0}}),
    )
    .await;
    assert_eq!(ui.reply(3).await["node"], "fila");
    ui.send(
        json!({"id": 4, "cmd": "create_node", "workbench": "1a2b3c4d", "type": "shell",
                   "component": "Revisor"}),
    )
    .await;
    assert_eq!(ui.reply(4).await["node"], "revisor");
    ui.send(
        json!({"id": 5, "cmd": "create_node", "workbench": "1a2b3c4d", "type": "shell",
                   "component": "nada"}),
    )
    .await;
    assert_eq!(ui.reply(5).await["error"], "componente desconhecido 'nada'");
    ui.send(json!({"id": 6, "cmd": "create_node", "workbench": "ffffffff", "type": "shell"}))
        .await;
    assert_eq!(
        ui.reply(6).await["error"],
        "bancada desconhecida 'ffffffff'"
    );

    let saved = saved_eventually(&h, |v| {
        v[0]["nodes"].as_array().is_some_and(|n| n.len() == 6)
    })
    .await;
    let nodes = saved[0]["nodes"].as_array().unwrap();
    let ids: Vec<_> = nodes.iter().map(|n| n["id"].as_str().unwrap()).collect();
    assert_eq!(ids, ["sh", "claude", "sh-2", "web", "fila", "revisor"]);
    assert_eq!(nodes[3]["url"], "https://www.google.com");
    assert_eq!(nodes[3]["profile"], "pessoal");
    assert_eq!(nodes[4]["w"], 540.0);
    assert_eq!(nodes[5]["cmd"], "make");
    assert_eq!(nodes[5]["component"], "Revisor");
    h.stop().await.unwrap();
}

#[tokio::test]
async fn configurar_o_no_aplica_o_formulario_e_remover_leva_as_ligacoes() {
    let dir = TempHome::new();
    let h = Harness::start_with_files(&two_benches(&dir.0)).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "link", "workbench": "1a2b3c4d", "from": "claude", "to": "sh"}))
        .await;
    assert_eq!(ui.reply(1).await["ok"], true);

    ui.send(
        json!({"id": 2, "cmd": "set_node", "workbench": "1a2b3c4d", "node": "claude",
                   "model": "opus", "effort": "high", "role": "revise", "cwd": "api"}),
    )
    .await;
    assert_eq!(ui.reply(2).await["ok"], true);
    let saved = saved_eventually(&h, |v| v[0]["nodes"][1]["model"] == "opus").await;
    let claude = &saved[0]["nodes"][1];
    assert_eq!(claude["effort"], "high");
    assert_eq!(claude["prompt"], "revise");
    assert_eq!(claude["cwd"], "api");

    // `null` volta ao padrão: some do arquivo.
    ui.send(
        json!({"id": 3, "cmd": "set_node", "workbench": "1a2b3c4d", "node": "claude",
                   "model": null, "role": null}),
    )
    .await;
    assert_eq!(ui.reply(3).await["ok"], true);
    let saved = saved_eventually(&h, |v| v[0]["nodes"][1].get("model").is_none()).await;
    assert!(saved[0]["nodes"][1].get("prompt").is_none());
    ui.send(
        json!({"id": 4, "cmd": "set_node", "workbench": "1a2b3c4d", "node": "nada", "model": "x"}),
    )
    .await;
    assert_eq!(ui.reply(4).await["error"], "nó desconhecido 'nada'");

    ui.send(json!({"id": 5, "cmd": "remove_node", "workbench": "1a2b3c4d", "node": "claude"}))
        .await;
    assert_eq!(ui.reply(5).await["ok"], true);
    let saved = saved_eventually(&h, |v| {
        v[0]["nodes"].as_array().is_some_and(|n| n.len() == 1)
    })
    .await;
    assert_eq!(saved[0]["nodes"][0]["id"], "sh");
    assert_eq!(saved[0]["edges"], json!([]), "a ligação foi junto");
    ui.send(json!({"id": 6, "cmd": "remove_node", "workbench": "1a2b3c4d", "node": "claude"}))
        .await;
    assert_eq!(ui.reply(6).await["error"], "nó desconhecido 'claude'");
    h.stop().await.unwrap();
}

// ── Criar e remover bancada (org, `node_commands.rs`) ──────────────────────

#[tokio::test]
async fn criar_bancada_da_nome_livre_projeto_template_e_ativa() {
    let dir = TempHome::new();
    let folder = dir.0.join("meu-projeto");
    std::fs::create_dir_all(&folder).unwrap();
    let mut files = two_benches(&dir.0);
    files.push((
        "templates.json",
        json!({"duo": {"view": "chat", "nodes": [{"type": "shell", "id": "a",
                                                  "conversationId": "VELHA"}]}})
        .to_string(),
    ));
    let h = Harness::start_with_files(&files).await;
    let mut ui = h.ui().await;

    ui.send(json!({"id": 1, "cmd": "create_workbench", "path": folder.to_string_lossy()}))
        .await;
    let first = ui.reply(1).await;
    assert_eq!(first["ok"], true, "{first}");
    let first_id = first["workbench"].as_str().unwrap().to_owned();
    assert_eq!(first_id.len(), 8);

    // Mesmo nome sugerido: ganha `-2`; o template traz nós e modo.
    ui.send(
        json!({"id": 2, "cmd": "create_workbench", "path": folder.to_string_lossy(),
                   "template": "duo", "color": "Areia"}),
    )
    .await;
    assert_eq!(ui.reply(2).await["ok"], true);
    ui.send(
        json!({"id": 3, "cmd": "create_workbench", "path": folder.to_string_lossy(),
                   "template": "nada"}),
    )
    .await;
    assert_eq!(ui.reply(3).await["error"], "template desconhecido 'nada'");
    ui.send(
        json!({"id": 4, "cmd": "create_workbench", "path": folder.to_string_lossy(),
                   "color": "roxo-neon"}),
    )
    .await;
    assert_eq!(ui.reply(4).await["error"], "cor desconhecida 'roxo-neon'");

    let saved = saved_eventually(&h, |v| v.as_array().is_some_and(|l| l.len() == 4)).await;
    let list = saved.as_array().unwrap();
    assert_eq!(list[2]["name"], "meu-projeto");
    assert_eq!(list[3]["name"], "meu-projeto-2");
    assert_eq!(list[3]["template"], "duo");
    assert_eq!(list[3]["view"], "chat");
    assert_eq!(list[3]["color"], "sand");
    assert_eq!(list[3]["nodes"][0]["id"], "a");
    assert!(
        list[3]["nodes"][0].get("conversationId").is_none(),
        "molde não leva conversa"
    );
    // Conciliada: as duas bancadas da mesma pasta são do mesmo projeto.
    assert_eq!(list[2]["project"], list[3]["project"]);
    assert!(list[2]["project"].is_string());
    h.stop().await.unwrap();
}

#[tokio::test]
async fn remover_bancada_planeja_apaga_da_lista_e_responde_pela_rota() {
    let dir = TempHome::new();
    let h = Harness::start_with_files(&two_benches(&dir.0)).await;
    let mut ui = h.ui().await;

    ui.send(json!({"id": 1, "cmd": "plan_remove_workbench", "workbench": "5e6f7a8b"}))
        .await;
    let plan = ui.reply(1).await;
    assert_eq!(plan["live"], false);
    assert_eq!(plan["worktrees"], json!([]));
    ui.send(json!({"id": 2, "cmd": "plan_remove_workbench", "workbench": "ffffffff"}))
        .await;
    assert_eq!(
        ui.reply(2).await["error"],
        "bancada desconhecida 'ffffffff'"
    );

    ui.send(json!({"id": 3, "cmd": "remove_workbench", "workbench": "5e6f7a8b"}))
        .await;
    let done = ui.reply(3).await;
    assert_eq!(done["ok"], true, "{done}");
    assert_eq!(done["workbench"], "outra");
    assert_eq!(done["removed"], json!([]));
    let saved = saved_eventually(&h, |v| v.as_array().is_some_and(|l| l.len() == 1)).await;
    assert_eq!(saved[0]["id"], "1a2b3c4d");

    // A rota do Swift: GET /remove?target=… responde com as mesmas chaves.
    let (status, body) = h.get("/remove?target=nada").await;
    assert_eq!(status, 400);
    assert_eq!(
        body,
        json!({"ok": false, "error": "bancada desconhecida 'nada'"})
    );
    let (status, body) = h.get("/remove?target=deck").await;
    assert_eq!(status, 200, "{body}");
    assert_eq!(body["workbench"], "deck");
    assert_eq!(body["ok"], true);
    for key in ["removed", "sweeping", "kept", "worktrees"] {
        assert!(body[key].is_array(), "{key}");
    }
    let saved = saved_eventually(&h, |v| v.as_array().is_some_and(|l| l.is_empty())).await;
    assert_eq!(saved, json!([]));
    h.stop().await.unwrap();
}

// ── Workspaces e projetos (org, `node_commands.rs`) ────────────────────────

fn workspaces_on_disk(h: &Harness) -> Value {
    let text = std::fs::read_to_string(h._home.0.join("data/workspaces.json")).unwrap_or_default();
    serde_json::from_str(&text).unwrap_or(Value::Null)
}

async fn spaces_eventually(h: &Harness, check: impl Fn(&Value) -> bool) -> Value {
    for _ in 0..500 {
        let v = workspaces_on_disk(h);
        if check(&v) {
            return v;
        }
        tokio::time::sleep(Duration::from_millis(4)).await;
    }
    panic!("a gravação dos workspaces não chegou");
}

#[tokio::test]
async fn criar_salvar_e_remover_workspace() {
    let dir = TempHome::new();
    let pasta = dir.0.join("repos/api");
    std::fs::create_dir_all(&pasta).unwrap();
    let h = Harness::start_with_files(&two_benches(&dir.0)).await;
    let mut ui = h.ui().await;

    ui.send(json!({"id": 1, "cmd": "create_workspace", "name": "  "}))
        .await;
    assert_eq!(ui.reply(1).await["error"], "Dê um nome ao workspace.");
    ui.send(json!({"id": 2, "cmd": "create_workspace", "name": " Agro "}))
        .await;
    let created = ui.reply(2).await;
    assert_eq!(created["ok"], true, "{created}");
    let id = created["workspace"].as_str().unwrap().to_owned();
    spaces_eventually(&h, |v| {
        v.as_array()
            .is_some_and(|l| l.iter().any(|w| w["name"] == "Agro"))
    })
    .await;

    // O formulário: nome novo, uma pasta, um multi-projeto com ela.
    ui.send(
        json!({"id": 3, "cmd": "save_workspace", "workspace": id, "name": "Agro 2",
                   "folders": [pasta.to_string_lossy()],
                   "multis": [{"name": "", "folders": [pasta.to_string_lossy()]}]}),
    )
    .await;
    let saved = ui.reply(3).await;
    assert_eq!(saved["ok"], true, "{saved}");
    assert_eq!(saved["refused"], json!([]));
    let on_disk = spaces_eventually(&h, |v| {
        v.as_array().is_some_and(|l| {
            l.iter().any(|w| {
                w["name"] == "Agro 2" && w["projects"].as_array().is_some_and(|p| p.len() == 2)
            })
        })
    })
    .await;
    let space = on_disk
        .as_array()
        .unwrap()
        .iter()
        .find(|w| w["name"] == "Agro 2")
        .unwrap();
    let folder = space["projects"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p.get("members").is_none())
        .unwrap();
    let multi = space["projects"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p.get("members").is_some())
        .unwrap();
    assert_eq!(folder["name"], "api");
    assert_eq!(multi["name"], "api", "multi sem nome leva o das pastas");
    assert_eq!(multi["members"], json!([folder["id"]]));

    ui.send(
        json!({"id": 4, "cmd": "save_workspace", "workspace": "ffffffff", "name": "x",
                   "folders": []}),
    )
    .await;
    assert_eq!(
        ui.reply(4).await["error"],
        "workspace desconhecido 'ffffffff'"
    );

    // Remover: dry_run só confere, e some de verdade depois.
    ui.send(json!({"id": 5, "cmd": "remove_workspace", "workspace": id, "dry_run": true}))
        .await;
    assert_eq!(ui.reply(5).await["ok"], true);
    assert!(
        workspaces_on_disk(&h)
            .as_array()
            .unwrap()
            .iter()
            .any(|w| w["id"] == id.as_str())
    );
    ui.send(json!({"id": 6, "cmd": "remove_workspace", "workspace": id}))
        .await;
    assert_eq!(ui.reply(6).await["ok"], true);
    spaces_eventually(&h, |v| {
        v.as_array()
            .is_some_and(|l| !l.iter().any(|w| w["id"] == id.as_str()))
    })
    .await;
    h.stop().await.unwrap();
}

#[tokio::test]
async fn projetos_entram_saem_e_bancada_segura_o_projeto() {
    let dir = TempHome::new();
    let pasta = dir.0.join("repos/web");
    std::fs::create_dir_all(&pasta).unwrap();
    let h = Harness::start_with_files(&two_benches(&dir.0)).await;
    let mut ui = h.ui().await;
    // As bancadas do arquivo foram conciliadas para um projeto do "Geral".
    let tree = h.get("/workspaces").await.1;
    let geral = tree["workspaces"][0]["id"].as_str().unwrap().to_owned();
    let project = tree["workspaces"][0]["projects"][0]["id"]
        .as_str()
        .unwrap()
        .to_owned();

    ui.send(
        json!({"id": 1, "cmd": "add_project", "workspace": geral, "path": pasta.to_string_lossy(),
                   "name": "Web"}),
    )
    .await;
    let added = ui.reply(1).await;
    assert_eq!(added["ok"], true, "{added}");
    let web = added["project"].as_str().unwrap().to_owned();
    ui.send(
        json!({"id": 2, "cmd": "add_project", "workspace": geral, "path": pasta.to_string_lossy()}),
    )
    .await;
    assert_eq!(
        ui.reply(2).await["error"],
        "Essa pasta já é o projeto \"Web\" deste workspace."
    );
    ui.send(json!({"id": 3, "cmd": "add_project", "workspace": geral, "path": "/nao/existe"}))
        .await;
    assert!(
        ui.reply(3).await["error"]
            .as_str()
            .unwrap()
            .starts_with("A pasta /nao/existe não existe")
    );

    // O projeto com bancada não sai; o sem bancada sai.
    ui.send(json!({"id": 4, "cmd": "remove_project", "project": project}))
        .await;
    assert!(
        ui.reply(4).await["error"]
            .as_str()
            .unwrap()
            .contains("ainda tem 2 bancada(s)")
    );
    ui.send(json!({"id": 5, "cmd": "remove_project", "project": web, "dry_run": true}))
        .await;
    assert_eq!(ui.reply(5).await["ok"], true);
    ui.send(json!({"id": 6, "cmd": "remove_project", "project": web}))
        .await;
    assert_eq!(ui.reply(6).await["ok"], true);
    ui.send(json!({"id": 7, "cmd": "remove_project", "project": web}))
        .await;
    assert_eq!(
        ui.reply(7).await["error"],
        format!("projeto desconhecido '{web}'")
    );

    // Multi-projeto de projetos de pasta; membro desconhecido é recusado.
    ui.send(
        json!({"id": 8, "cmd": "multi_project", "workspace": geral, "name": "Junto",
                   "members": [project]}),
    )
    .await;
    assert_eq!(ui.reply(8).await["ok"], true);
    ui.send(json!({"id": 9, "cmd": "multi_project", "workspace": geral, "name": "x", "members": ["ffffffff"]})).await;
    assert_eq!(
        ui.reply(9).await["error"],
        "projeto de pasta desconhecido 'ffffffff'"
    );
    spaces_eventually(&h, |v| {
        v[0]["projects"].as_array().is_some_and(|p| {
            p.iter()
                .any(|x| x["name"] == "Junto" && x["members"] == json!([project]))
        })
    })
    .await;
    h.stop().await.unwrap();
}

#[tokio::test]
async fn criar_projeto_pelo_comando_cria_a_pasta_e_o_git() {
    let dir = TempHome::new();
    let parent = dir.0.join("repos");
    std::fs::create_dir_all(&parent).unwrap();
    let h = Harness::start_with_files(&two_benches(&dir.0)).await;
    let mut ui = h.ui().await;
    let geral = h.get("/workspaces").await.1["workspaces"][0]["id"]
        .as_str()
        .unwrap()
        .to_owned();
    ui.send(
        json!({"id": 1, "cmd": "create_project", "workspace": geral, "name": "novo",
                   "parent": parent.to_string_lossy(), "git": false}),
    )
    .await;
    let reply = ui.reply(1).await;
    assert_eq!(reply["ok"], true, "{reply}");
    assert_eq!(reply["created"], true);
    assert!(reply.get("tree").is_none());
    assert!(parent.join("novo").is_dir() && !parent.join("novo/.git").exists());
    ui.send(json!({"id": 2, "cmd": "create_project", "workspace": geral, "name": "a/b"}))
        .await;
    assert_eq!(
        ui.reply(2).await["error"],
        "O nome não pode ter \"/\" nem \":\", nem começar com ponto."
    );
    h.stop().await.unwrap();
}

// ── Worktree: a rota, o comando e a cópia do não versionado ────────────────

fn git_in(dir: &std::path::Path, args: &[&str]) {
    let out = std::process::Command::new("git")
        .args(args)
        .current_dir(dir)
        .env_clear()
        .env("PATH", "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin")
        .env("HOME", dir)
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&out.stderr)
    );
}

/// Repositório com um commit e um `.env` que o git não versiona, numa pasta
/// canônica (o git devolve o caminho real).
fn repo_with_env(home: &TempHome) -> PathBuf {
    let repo = std::fs::canonicalize(&home.0).unwrap().join("repo");
    std::fs::create_dir_all(&repo).unwrap();
    git_in(&repo, &["init", "-q", "-b", "main", "."]);
    git_in(&repo, &["config", "user.email", "t@e"]);
    git_in(&repo, &["config", "user.name", "t"]);
    std::fs::write(repo.join("a.txt"), "a").unwrap();
    std::fs::write(repo.join(".gitignore"), ".env\n").unwrap();
    git_in(&repo, &["add", "-A"]);
    git_in(&repo, &["commit", "-qm", "init"]);
    std::fs::write(repo.join(".env"), "SEGREDO=1").unwrap();
    repo
}

#[tokio::test]
async fn worktree_abre_bancada_nova_ativa_e_copia_o_nao_versionado() {
    let dir = TempHome::new();
    let repo = repo_with_env(&dir);
    let benches = json!([{"id": "1a2b3c4d", "name": "deck", "path": repo.to_string_lossy(),
                          "nodes": [{"type": "shell", "id": "sh"}], "tabOrder": 0, "tabActive": true}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;

    let (status, body) = h.get("/worktree?target=deck&branch=feature%2Fx").await;
    assert_eq!(status, 200, "{body}");
    assert_eq!(body["ok"], true);
    assert_eq!(body["workbench"], "feature-x");
    assert_eq!(body["branch"], "feature/x");
    let wt = std::fs::canonicalize(&dir.0)
        .unwrap()
        .join("worktrees/repo/feature-x");
    assert_eq!(body["path"], wt.to_string_lossy().as_ref());
    assert!(wt.join("a.txt").exists());

    let saved = saved_eventually(&h, |v| v.as_array().is_some_and(|l| l.len() == 2)).await;
    assert_eq!(saved[1]["name"], "feature-x");
    assert!(
        saved[1]["nodes"][0].get("cwd").is_none(),
        "nó dentro vai junto, sem cwd"
    );
    // A cópia do que o git não versiona chega depois, em segundo plano.
    for _ in 0..500 {
        if wt.join(".env").exists() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    assert_eq!(
        std::fs::read_to_string(wt.join(".env")).unwrap(),
        "SEGREDO=1"
    );

    // O comando do /ui é a mesma rota por dentro.
    ui.send(json!({"id": 1, "cmd": "worktree", "workbench": "1a2b3c4d", "branch": "fix/y"}))
        .await;
    let done = ui.reply(1).await;
    assert_eq!(done["ok"], true, "{done}");
    // O comando fala o id da bancada nova (decisão 37); a rota HTTP, o nome.
    let saved = saved_eventually(&h, |v| v.as_array().is_some_and(|l| l.len() == 3)).await;
    assert_eq!(saved[2]["name"], "fix-y");
    assert_eq!(done["workbench"], saved[2]["id"]);
    ui.send(json!({"id": 2, "cmd": "worktree", "workbench": "ffffffff", "branch": "x"}))
        .await;
    assert_eq!(
        ui.reply(2).await["error"],
        "bancada desconhecida 'ffffffff'"
    );
    let (status, body) = h.get("/worktree?target=nada&branch=x").await;
    assert_eq!(
        (status, body["error"].clone()),
        (400, json!("bancada desconhecida 'nada'"))
    );
    h.stop().await.unwrap();
}

#[tokio::test]
async fn worktree_de_um_terminal_so_reaponta_o_no_sem_conversa() {
    let dir = TempHome::new();
    let repo = repo_with_env(&dir);
    let benches = json!([{"id": "1a2b3c4d", "name": "deck", "path": repo.to_string_lossy(),
                          "nodes": [{"type": "shell", "id": "sh", "x": 10, "y": 20, "w": 300, "h": 200}]}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let (status, body) = h.get("/worktree?target=deck%2Fsh&branch=spike").await;
    assert_eq!(status, 200, "{body}");
    let wt = std::fs::canonicalize(&dir.0)
        .unwrap()
        .join("worktrees/repo/spike");
    assert_eq!(body["node"], "sh");
    assert_eq!(body["reused"], false);
    assert_eq!(body["path"], wt.to_string_lossy().as_ref());
    let saved = saved_eventually(&h, |v| v[0]["nodes"][0].get("cwd").is_some()).await;
    let node = &saved[0]["nodes"][0];
    assert_eq!(node["x"], 10.0, "o card fica onde estava");
    assert!(
        node["cwd"]
            .as_str()
            .unwrap()
            .ends_with("worktrees/repo/spike")
    );
    let (status, body) = h.get("/worktree?target=deck%2Ffantasma&branch=x").await;
    assert_eq!(
        (status, body["error"].clone()),
        (400, json!("nó desconhecido 'fantasma'"))
    );
    h.stop().await.unwrap();
}

// ── Limpar o agente do card (`/node/clear`) ────────────────────────────────

#[tokio::test]
async fn limpar_o_no_manda_o_clear_do_perfil_e_recusa_o_que_nao_e_agente() {
    let dir = TempHome::new();
    let benches = json!([{
        "id": "1a2b3c4d", "name": "deck", "path": dir.0.to_string_lossy(),
        "nodes": [{"type": "shell", "id": "sh"},
                  {"type": "agent", "id": "cl", "agent": "claude"},
                  {"type": "agent", "id": "mudo", "agent": "simples"}],
        "tabOrder": 0, "tabActive": true
    }]);
    let agents = json!({
        "claude": {"displayName": "Claude", "command": ["claude"], "clear": "/clear"},
        "simples": {"displayName": "Simples", "command": ["simples-cli"]}
    });
    let h = Harness::start_with_files(&[
        ("workbenches.json", benches.to_string()),
        ("agents.json", agents.to_string()),
    ])
    .await;

    let (status, body) = h.post("/node/clear?target=deck/sh", "").await;
    assert_eq!(
        (status, body["error"].clone()),
        (404, json!("agente desconhecido 'deck/sh'"))
    );
    let (_, body) = h.post("/node/clear?target=nada", "").await;
    assert_eq!(body["error"], "agente desconhecido 'nada'");
    let (_, body) = h.post("/node/clear?target=deck/mudo", "").await;
    assert_eq!(
        body["error"],
        "o CLI de 'deck/mudo' não declara comando de limpar"
    );

    // O terminal entra no dispatch no primeiro tique; aí o `clear` é aceito.
    let mut ok = false;
    for _ in 0..60 {
        let (status, body) = h.post("/node/clear?target=deck/cl", "").await;
        if status == 200 {
            assert_eq!(body, json!({"ok": true, "target": "deck/cl"}));
            ok = true;
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    assert!(ok, "o clear não foi aceito");
    h.stop().await.unwrap();
}

/// Decisão 16: toda assinatura recebe a tela inteira — também a segunda,
/// de outro cliente ou do mesmo, com a tela já desenhada e com delta ainda
/// por sair.
#[tokio::test]
async fn segunda_assinatura_da_tela_recebe_o_quadro_inteiro() {
    let h = Harness::start().await;
    let mut a = h.ui().await;
    a.send(json!({"id": 1, "cmd": "create_terminal", "cols": 20, "rows": 3}))
        .await;
    assert_eq!(a.reply(1).await["ok"], true);
    a.send(json!({"id": 2, "cmd": "subscribe", "topic": "screen/t1"}))
        .await;
    let first = a.until(|v| v["topic"] == "screen/t1").await;
    assert_eq!(first["kind"], "full");

    let (_, events, _) = h.pty.child(0);
    events
        .send(PtyEvent::Output(b"um\r\n".to_vec()))
        .await
        .unwrap();
    let delta = a.until(|v| v["topic"] == "screen/t1").await;
    assert_eq!(delta["kind"], "delta");

    // Outro cliente, com a tela já desenhada.
    let mut b = h.ui().await;
    b.send(json!({"id": 3, "cmd": "subscribe", "topic": "screen/t1"}))
        .await;
    let full = b.until(|v| v["topic"] == "screen/t1").await;
    assert_eq!(full["kind"], "full", "{full}");
    assert_eq!(full["lines"][0]["spans"][0]["text"], "um", "{full}");

    // O mesmo cliente assinando de novo (dois cards da mesma tela).
    a.send(json!({"id": 4, "cmd": "subscribe", "topic": "screen/t1"}))
        .await;
    let again = a.until(|v| v["topic"] == "screen/t1").await;
    assert_eq!(again["kind"], "full", "{again}");
    assert_eq!(again["lines"][0]["spans"][0]["text"], "um", "{again}");

    // Saída que chega com a segunda assinatura: o quadro inteiro já a traz,
    // e quem já assinava recebe o delta.
    events
        .send(PtyEvent::Output(b"dois\r\n".to_vec()))
        .await
        .unwrap();
    b.send(json!({"id": 5, "cmd": "subscribe", "topic": "screen/t1"}))
        .await;
    let latest = b
        .until(|v| v["topic"] == "screen/t1" && v["kind"] == "full")
        .await;
    let texts: Vec<&Value> = latest["lines"]
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|l| l["spans"].as_array().unwrap())
        .map(|s| &s["text"])
        .collect();
    assert!(texts.contains(&&json!("dois")), "{latest}");
    h.stop().await.unwrap();
}

// ── Limpar a bancada (`/workbench/clear`, ADR-059) ─────────────────────────

#[tokio::test]
async fn limpar_a_bancada_arquiva_chat_e_trilha_e_responde_no_fim() {
    let dir = TempHome::new();
    let benches = json!([{
        "id": "1a2b3c4d", "name": "deck", "path": dir.0.to_string_lossy(),
        "nodes": [{"type": "shell", "id": "sh"}, {"type": "agent", "id": "mudo", "agent": "simples"}]
    }]);
    let agents = json!({"simples": {"displayName": "Simples", "command": ["simples-cli"]}});
    let h = Harness::start_with_files(&[
        ("workbenches.json", benches.to_string()),
        ("agents.json", agents.to_string()),
    ])
    .await;
    let bench_dir = h._home.0.join("data/workbenches/1a2b3c4d");
    std::fs::create_dir_all(&bench_dir).unwrap();
    std::fs::write(bench_dir.join("chat.jsonl"), "{\"k\":1}\n").unwrap();
    std::fs::write(bench_dir.join("trace.md"), "# trilha\n").unwrap();

    let (status, body) = h.post("/workbench/clear?target=deck", "").await;
    assert_eq!(status, 200, "{body}");
    assert_eq!(body["ok"], true);
    assert_eq!(body["workbench"], "deck");
    assert_eq!(body["cleared"], json!([]), "CLI sem `clear` não é morto");
    assert_eq!(body["skipped"], json!(["mudo"]));
    assert_eq!(body["timeout"], false);
    let chat = body["archived"].as_str().unwrap();
    let trace = body["trace"].as_str().unwrap();
    assert!(
        chat.contains("chat-archive/chat-") && trace.contains("trace-archive/trace-"),
        "{body}"
    );
    assert!(std::path::Path::new(chat).exists() && std::path::Path::new(trace).exists());
    assert!(!bench_dir.join("chat.jsonl").exists() && !bench_dir.join("trace.md").exists());

    // Sem nada a arquivar: ok, e os dois campos viram nulo.
    let (status, body) = h.post("/workbench/clear?target=deck", "").await;
    assert_eq!(status, 200);
    assert_eq!(
        (body["archived"].clone(), body["trace"].clone()),
        (Value::Null, Value::Null)
    );
    let (status, body) = h.post("/workbench/clear?target=nada", "").await;
    assert_eq!(
        (status, body),
        (
            404,
            json!({"ok": false, "error": "bancada desconhecida 'nada'"})
        )
    );
    h.stop().await.unwrap();
}

#[tokio::test]
async fn limpar_pelo_comando_responde_igual() {
    let dir = TempHome::new();
    let h = Harness::start_with_files(&two_benches(&dir.0)).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "clear_workbench", "workbench": "5e6f7a8b"}))
        .await;
    let done = ui.reply(1).await;
    assert_eq!(done["ok"], true, "{done}");
    assert_eq!(done["workbench"], "outra");
    ui.send(json!({"id": 2, "cmd": "clear_workbench", "workbench": "ffffffff"}))
        .await;
    assert_eq!(
        ui.reply(2).await["error"],
        "bancada desconhecida 'ffffffff'"
    );
    h.stop().await.unwrap();
}

/// A fila é serial e nenhuma remoção se perde: duas seguidas terminam, na ordem.
#[tokio::test]
async fn duas_remocoes_seguidas_passam_pela_fila_e_terminam() {
    let dir = TempHome::new();
    let h = Harness::start_with_files(&two_benches(&dir.0)).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "remove_workbench", "workbench": "5e6f7a8b"}))
        .await;
    ui.send(json!({"id": 2, "cmd": "remove_workbench", "workbench": "1a2b3c4d"}))
        .await;
    assert_eq!(ui.reply(1).await["ok"], true);
    assert_eq!(ui.reply(2).await["ok"], true);
    let saved = saved_eventually(&h, |v| v.as_array().is_some_and(|l| l.is_empty())).await;
    assert_eq!(saved, json!([]));
    // A marca "removendo" não ficou para trás.
    ui.send(json!({"id": 3, "cmd": "remove_workbench", "workbench": "1a2b3c4d"}))
        .await;
    assert_eq!(
        ui.reply(3).await["error"],
        "bancada desconhecida '1a2b3c4d'"
    );
    h.stop().await.unwrap();
}

/// Decisão 35: a rota de tela vai à UI que assina `app` e volta com a
/// resposta dela; sem UI, responde como o Swift sem janela.
#[tokio::test]
async fn rota_de_tela_vai_a_ui_e_volta() {
    let h = Arc::new(Harness::start().await);
    let (status, body) = h.get("/layout?mode=chat").await;
    assert_eq!((status, body), (404, json!({"ok": false, "mode": "chat"})));

    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "app"}))
        .await;
    assert_eq!(ui.reply(1).await["ok"], true);
    let asker = h.clone();
    let pending = tokio::spawn(async move { asker.get("/layout?mode=chat").await });
    let request = ui
        .until(|v| v["topic"] == "app" && v["effect"] == "ui_request")
        .await;
    assert_eq!(request["route"], "layout");
    assert_eq!(request["params"]["mode"], "chat");
    ui.send(json!({"id": 2, "cmd": "ui_reply", "request": request["id"],
                   "value": "chat"}))
        .await;
    assert_eq!(ui.reply(2).await["ok"], true);
    let (status, body) = pending.await.unwrap();
    assert_eq!((status, body), (200, json!({"ok": true, "mode": "chat"})));

    // Resposta a pedido que já foi respondido é recusada.
    ui.send(json!({"id": 3, "cmd": "ui_reply", "request": request["id"],
                   "value": null}))
        .await;
    assert_eq!(ui.reply(3).await["ok"], false);
}

/// O core lançado pela UI segura o pedido de tela até ela assinar `app`,
/// em vez de responder "sem janela" na partida.
#[tokio::test]
async fn rota_de_tela_espera_a_ui_que_lancou_o_core() {
    let h = Arc::new(Harness::start_ui_parent().await);
    let asker = h.clone();
    let pending = tokio::spawn(async move { asker.get("/layout?mode=chat").await });
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert!(!pending.is_finished(), "respondeu sem esperar a UI");
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "app"}))
        .await;
    let request = ui
        .until(|v| v["topic"] == "app" && v["effect"] == "ui_request")
        .await;
    assert_eq!(request["route"], "layout");
    ui.send(json!({"id": 2, "cmd": "ui_reply", "request": request["id"],
                   "value": "chat"}))
        .await;
    let (status, body) = pending.await.unwrap();
    assert_eq!((status, body), (200, json!({"ok": true, "mode": "chat"})));
}

/// Decisão 37: a janela de processos no `/ui`, com o ensaio que só devolve
/// a confirmação.
#[tokio::test]
async fn processos_no_ui_listam_e_ensaiam() {
    let h = Harness::start().await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "processes"})).await;
    let list = ui.reply(1).await;
    assert_eq!(list["ok"], true, "{list}");
    assert!(list["summary"].is_string(), "{list}");
    assert!(list["processes"].is_array(), "{list}");
    ui.send(json!({"id": 2, "cmd": "processes_reap", "dry_run": true}))
        .await;
    let ask = ui.reply(2).await;
    assert_eq!(
        ask["detail"], "Recebem SIGTERM — o mesmo que fechar o terminal deles.",
        "{ask}"
    );
    assert!(
        ask["title"].as_str().unwrap().starts_with("Encerrar "),
        "{ask}"
    );
}

/// Decisão 37: o consumo da bancada no tópico `workbench/<id>/usage`.
#[tokio::test]
async fn consumo_da_bancada_no_topico() {
    let dir = TempHome::new();
    let benches = json!([{
        "id": "1a2b3c4d", "name": "deck", "path": dir.0.to_string_lossy(), "nodes": []
    }]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "workbench/1a2b3c4d/usage"}))
        .await;
    let usage = ui.until(|v| v["topic"] == "workbench/1a2b3c4d/usage").await;
    assert_eq!(usage["pill"]["text"], "US$ 0,00", "{usage}");
    assert!(usage["panel"]["heading"].is_string(), "{usage}");
    ui.send(json!({"id": 2, "cmd": "subscribe", "topic": "workbench/ffffffff/usage"}))
        .await;
    assert_eq!(ui.reply(2).await["ok"], false);
}

// ── /model (decisão 35) ────────────────────────────────────────────────────

#[tokio::test]
async fn model_troca_modelo_esforco_e_ultracode_como_o_swift() {
    let dir = TempHome::new();
    let benches = json!([{
        "id": "1a2b3c4d", "name": "deck", "path": dir.0.to_string_lossy(),
        "nodes": [{"type": "shell", "id": "sh"},
                  {"type": "agent", "id": "cl", "agent": "claude", "model": "opus", "effort": "high"},
                  {"type": "agent", "id": "mudo", "agent": "simples"}],
        "tabOrder": 0, "tabActive": true
    }]);
    let agents = json!({
        "claude": {"displayName": "Claude", "command": ["claude"], "model": ["--model", "{model}"],
                   "effort": ["--effort", "{effort}"], "ultracode": ["--effort", "ultracode"]},
        "simples": {"displayName": "Simples", "command": ["simples-cli"]}
    });
    let h = Harness::start_with_files(&[
        ("workbenches.json", benches.to_string()),
        ("agents.json", agents.to_string()),
    ])
    .await;

    let (status, body) = h.get("/model?target=deck/cl&model=sonnet").await;
    assert_eq!(
        (status, body),
        (
            200,
            json!({"ok": true, "target": "deck/cl", "model": "sonnet"})
        )
    );
    let saved = saved_eventually(&h, |v| v[0]["nodes"][1]["model"] == "sonnet").await;
    assert_eq!(saved[0]["nodes"][1]["effort"], "high");

    // Sem `model` volta ao padrão: o campo sai do arquivo.
    let (_, body) = h.get("/model?target=deck/cl").await;
    assert_eq!(body["model"], "padrão");
    saved_eventually(&h, |v| v[0]["nodes"][1].get("model").is_none()).await;

    let (_, body) = h.get("/model?target=deck/cl&effort=low").await;
    assert_eq!(body["effort"], "low");
    let (_, body) = h.get("/model?target=deck/cl&effort=default").await;
    assert_eq!(body["effort"], "padrão");
    saved_eventually(&h, |v| v[0]["nodes"][1].get("effort").is_none()).await;

    let (_, body) = h.get("/model?target=deck/cl&ultracode=on").await;
    assert_eq!(body["ultracode"], "on");
    saved_eventually(&h, |v| v[0]["nodes"][1]["ultracode"] == true).await;
    let (_, body) = h.get("/model?target=deck/cl&ultracode=0").await;
    assert_eq!(body["ultracode"], "off");
    saved_eventually(&h, |v| v[0]["nodes"][1].get("ultracode").is_none()).await;

    for (query, error) in [
        ("target=nada&model=x", "bancada desconhecida 'nada'"),
        ("target=deck/zz&model=x", "nó desconhecido 'deck/zz'"),
        ("target=deck/sh&model=x", "'deck/sh' não é um agente"),
        (
            "target=deck/mudo&model=x",
            "'deck/mudo' não é um agente que aceite modelo",
        ),
        (
            "target=deck/mudo&effort=low",
            "'deck/mudo' não é um agente que aceite esforço",
        ),
        (
            "target=deck/mudo&ultracode=on",
            "'deck/mudo' não é um agente com ultracode",
        ),
    ] {
        let (status, body) = h.get(&format!("/model?{query}")).await;
        assert_eq!(
            (status, body),
            (404, json!({"ok": false, "error": error})),
            "{query}"
        );
    }
    h.stop().await.unwrap();
}

/// O rebaixe do `changeModel`: modelo novo que não tem o nível em vigor leva o
/// nó de volta ao auto, em vez de deixar o CLI rebaixar calado.
#[tokio::test]
async fn model_novo_sem_o_nivel_em_vigor_volta_o_esforco_ao_auto() {
    let dir = TempHome::new();
    let benches = json!([{
        "id": "1a2b3c4d", "name": "deck", "path": dir.0.to_string_lossy(),
        "nodes": [{"type": "agent", "id": "cl", "agent": "claude", "model": "grande", "effort": "max"}],
        "tabOrder": 0, "tabActive": true
    }]);
    let agents = json!({"claude": {"displayName": "Claude", "command": ["claude"],
        "model": ["--model", "{model}"], "effort": ["--effort", "{effort}"]}});
    // O catálogo vem do cache que o ator guarda para o binário `claude` do PATH.
    let cache = json!({"binary": "/x/claude", "size": 1, "modified": 1.0, "catalog": {"models": [
        {"id": "grande", "family": "grande", "label": "Grande", "efforts": ["low", "high", "max"]},
        {"id": "pequeno", "family": "pequeno", "label": "Pequeno", "efforts": ["low", "high"]}
    ]}});
    let h = Harness::start_with_files(&[
        ("workbenches.json", benches.to_string()),
        ("agents.json", agents.to_string()),
        ("claude-models.json", cache.to_string()),
        ("bin/claude", "#!/bin/sh\n".to_owned()),
    ])
    .await;
    // O ator lê o cache no primeiro tique, não na hora do pedido.
    tokio::time::sleep(Duration::from_millis(800)).await;

    let (status, _) = h.get("/model?target=deck/cl&model=pequeno").await;
    assert_eq!(status, 200);
    let saved = saved_eventually(&h, |v| v[0]["nodes"][0]["model"] == "pequeno").await;
    assert!(saved[0]["nodes"][0].get("effort").is_none(), "{saved}");

    // De volta ao modelo que tem o nível, o esforço escolhido na mão fica.
    h.get("/model?target=deck/cl&effort=max").await;
    h.get("/model?target=deck/cl&model=grande").await;
    let saved = saved_eventually(&h, |v| v[0]["nodes"][0]["model"] == "grande").await;
    assert_eq!(saved[0]["nodes"][0]["effort"], "max");
    h.stop().await.unwrap();
}

fn agent_and_web(dir: &std::path::Path) -> Vec<(&'static str, String)> {
    let benches = json!([{
        "id": "1a2b3c4d", "name": "deck", "path": dir.to_string_lossy(),
        "nodes": [
            {"type": "agent", "id": "claude", "agent": "claude", "model": "opus"},
            {"type": "web", "id": "docs", "url": "https://docs.rs"}
        ]
    }]);
    vec![("workbenches.json", benches.to_string())]
}

/// O nó de agente por dentro: o cabeçalho do ModelRow, e o dial que, ao
/// assentar, grava o esforço no nó (decisão 31).
#[tokio::test]
async fn no_de_agente_por_dentro_e_o_dial_que_assenta() {
    let dir = TempHome::new();
    let h = Harness::start_with_files(&agent_and_web(&dir.0)).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "node/1a2b3c4d/claude"}))
        .await;
    assert_eq!(ui.reply(1).await["ok"], true);
    let state = ui.until(|v| v["topic"] == "node/1a2b3c4d/claude").await;
    assert_eq!(state["kind"], "agent");
    let agent = &state["agent"];
    assert_eq!(agent["model_title"], "opus");
    let labels: Vec<&Value> = agent["models"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| &m["label"])
        .collect();
    assert!(labels.contains(&&json!("padrão do CLI")), "{agent}");
    assert!(
        agent["models"]
            .as_array()
            .unwrap()
            .iter()
            .any(|m| m["value"] == "opus" && m["selected"] == true)
    );
    let levels = agent["dial"]["levels"].as_array().unwrap().len();
    assert!(levels > 0, "{agent}");
    assert_eq!(agent["clearable"], true);

    ui.send(json!({"id": 2, "cmd": "effort_move", "workbench": "1a2b3c4d", "node": "claude", "index": 0}))
        .await;
    // O estado novo sai antes da resposta.
    let moved = ui.until(|v| v["topic"] == "node/1a2b3c4d/claude").await;
    assert_eq!(ui.reply(2).await["ok"], true);
    assert_eq!(moved["agent"]["dial"]["pending"], true, "{moved}");
    let first = moved["agent"]["dial"]["levels"][0]
        .as_str()
        .unwrap()
        .to_owned();

    ui.send(json!({"id": 3, "cmd": "effort_settle", "workbench": "1a2b3c4d", "node": "claude"}))
        .await;
    assert_eq!(ui.reply(3).await["ok"], true);
    saved_eventually(&h, |v| v[0]["nodes"][0]["effort"] == first.as_str()).await;
    h.stop().await.unwrap();
}

/// O nó web: perfil padrão com o UUID do web-profiles.json, o endereço
/// digitado normalizado e gravado, e o perfil novo criado no arquivo.
#[tokio::test]
async fn no_web_por_dentro_navega_e_troca_de_perfil() {
    let dir = TempHome::new();
    let h = Harness::start_with_files(&agent_and_web(&dir.0)).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "node/1a2b3c4d/docs"}))
        .await;
    let state = ui.until(|v| v["topic"] == "node/1a2b3c4d/docs").await;
    assert_eq!(state["web"]["url"], "https://docs.rs");
    assert_eq!(state["web"]["profile"], "pessoal");
    let id = state["web"]["profile_id"].as_str().unwrap().to_owned();
    assert_eq!(id.len(), 36, "UUID: {id}");

    ui.send(json!({"id": 2, "cmd": "web_navigate", "workbench": "1a2b3c4d", "node": "docs", "typed": "tokio.rs"}))
        .await;
    assert_eq!(ui.reply(2).await["ok"], true);
    saved_eventually(&h, |v| v[0]["nodes"][1]["url"] == "https://tokio.rs").await;

    ui.send(json!({"id": 3, "cmd": "web_set_profile", "workbench": "1a2b3c4d", "node": "docs", "profile": "trabalho"}))
        .await;
    let after = ui
        .until(|v| v["topic"] == "node/1a2b3c4d/docs" && v["web"]["profile"] == "trabalho")
        .await;
    assert_eq!(ui.reply(3).await["ok"], true);
    assert_ne!(after["web"]["profile_id"], json!(id));
    saved_eventually(&h, |v| v[0]["nodes"][1]["profile"] == "trabalho").await;
    let profiles = h._home.0.join("data/web-profiles.json");
    for _ in 0..200 {
        if std::fs::read_to_string(&profiles).is_ok_and(|t| t.contains("trabalho")) {
            break;
        }
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    let saved: Value = serde_json::from_str(&std::fs::read_to_string(&profiles).unwrap()).unwrap();
    assert_eq!(saved["pessoal"], json!(id));
    assert!(saved["trabalho"].is_string());
    h.stop().await.unwrap();
}

/// O título do agente passa a mostrar quem respondeu, lido do transcript
/// fora do ator a cada 2 s, como o ModelRow do Swift.
#[tokio::test]
async fn agente_sem_transcript_tira_o_titulo_da_config() {
    let dir = TempHome::new();
    let config = dir.0.join("cfg");
    std::fs::create_dir_all(&config).unwrap();
    std::fs::write(
        config.join("settings.json"),
        r#"{"model":"claude-sonnet-5-5"}"#,
    )
    .unwrap();
    let benches = json!([{
        "id": "1a2b3c4d", "name": "deck", "path": dir.0.to_string_lossy(),
        "nodes": [{"type": "agent", "id": "claude", "agent": "claude",
                   "config": config.to_string_lossy()}]
    }]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "node/1a2b3c4d/claude"}))
        .await;
    let read = ui
        .until(|v| {
            v["topic"] == "node/1a2b3c4d/claude" && v["agent"]["model_title"] == "sonnet-5-5"
        })
        .await;
    assert_eq!(read["agent"]["model_title"], "sonnet-5-5", "{read}");
    h.stop().await.unwrap();
}

#[tokio::test]
async fn titulo_do_agente_vem_do_transcript() {
    let dir = TempHome::new();
    let transcript = dir.0.join("conversa.jsonl");
    std::fs::write(
        &transcript,
        // Linha de antes da subida do terminal, de outro modelo: não vale.
        "{\"type\":\"assistant\",\"timestamp\":\"2020-01-01T00:00:00.000Z\",\"message\":{\"model\":\"claude-haiku-4-5\",\"usage\":{\"input_tokens\":10}}}\n",
    )
    .unwrap();
    let benches = json!([{
        "id": "1a2b3c4d", "name": "deck", "path": dir.0.to_string_lossy(),
        "nodes": [{"type": "agent", "id": "claude", "agent": "claude", "model": "opusplan",
                   "transcript": transcript.to_string_lossy()}],
        // Aberta: o terminal sobe, e só linha posterior à subida vale.
        "tabOrder": 0, "tabActive": true
    }]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "node/1a2b3c4d/claude"}))
        .await;
    let first = ui.until(|v| v["topic"] == "node/1a2b3c4d/claude").await;
    assert_eq!(first["agent"]["model_title"], "opusplan");
    // A resposta nova, depois da subida, é a que vale.
    tokio::time::sleep(Duration::from_millis(20)).await;
    let fresh = "{\"type\":\"assistant\",\"timestamp\":\"2999-01-01T00:00:00.000Z\",\"message\":{\"model\":\"claude-opus-5-5\",\"usage\":{\"input_tokens\":10}}}\n";
    let mut text = std::fs::read_to_string(&transcript).unwrap();
    text.push_str(fresh);
    std::fs::write(&transcript, text).unwrap();
    let read = ui
        .until(|v| v["topic"] == "node/1a2b3c4d/claude" && v["agent"]["model_title"] != "opusplan")
        .await;
    assert_eq!(
        read["agent"]["model_title"], "opus-5-5 (opusplan)",
        "{read}"
    );
    h.stop().await.unwrap();
}

// ── Formulários de bancada e de worktree (decisão 37) ──────────────────────

#[tokio::test]
async fn templates_lista_o_que_esta_salvo() {
    let dir = TempHome::new();
    let templates = json!({"dupla": {"nodes": [{"type": "shell", "id": "a"}, {"type": "shell", "id": "b"}],
                                      "basePath": "~/Documents/agro", "view": "chat"},
                           "vazio": {"nodes": []}});
    let h = Harness::start_with_files(&[("templates.json", templates.to_string())]).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "templates"})).await;
    let done = ui.reply(1).await;
    assert_eq!(
        done["templates"],
        json!([
            {"name": "dupla", "nodes": 2, "base_path": "~/Documents/agro", "view": "chat"},
            {"name": "vazio", "nodes": 0}
        ])
    );
    drop(dir);
    h.stop().await.unwrap();
}

#[tokio::test]
async fn formulario_de_worktree_le_o_resumo_e_o_veredito_sem_criar_nada() {
    let dir = TempHome::new();
    let repo = repo_with_env(&dir);
    git_in(&repo, &["branch", "local-livre"]);
    let benches = json!([{"id": "1a2b3c4d", "name": "deck", "path": repo.to_string_lossy(),
                          "nodes": [{"type": "shell", "id": "sh"}]}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;

    ui.send(json!({"id": 1, "cmd": "worktree_info", "workbench": "1a2b3c4d"}))
        .await;
    let info = ui.reply(1).await;
    assert_eq!(info["suggested_branch"], "main-2");
    assert_eq!(
        info["nodes"],
        json!([{"node": "sh", "state": "follows_workbench"}])
    );
    assert!(
        info["summary"]
            .as_str()
            .unwrap()
            .contains("worktree-copy.sh"),
        "{info}"
    );

    ui.send(
        json!({"id": 2, "cmd": "worktree_plan", "workbench": "1a2b3c4d", "branch": "local-livre"}),
    )
    .await;
    let plan = ui.reply(2).await;
    assert_eq!(plan["verdict"], "open_existing");
    ui.send(json!({"id": 3, "cmd": "worktree_plan", "workbench": "1a2b3c4d", "branch": "nova"}))
        .await;
    let plan = ui.reply(3).await;
    assert_eq!(plan["verdict"], "create");
    assert!(
        plan["folder"]
            .as_str()
            .unwrap()
            .ends_with("worktrees/repo/nova"),
        "{plan}"
    );

    ui.send(json!({"id": 4, "cmd": "worktree_info", "workbench": "ffffffff"}))
        .await;
    assert_eq!(
        ui.reply(4).await["error"],
        "bancada desconhecida 'ffffffff'"
    );
    assert!(
        !std::fs::canonicalize(&dir.0)
            .unwrap()
            .join("worktrees")
            .exists(),
        "só lê"
    );
    h.stop().await.unwrap();
}

#[tokio::test]
async fn worktree_move_current_reaponta_a_propria_bancada_e_responde_o_id() {
    let dir = TempHome::new();
    let repo = repo_with_env(&dir);
    let benches = json!([{"id": "1a2b3c4d", "name": "deck", "path": repo.to_string_lossy(),
                          "nodes": [{"type": "shell", "id": "sh"}], "tabOrder": 0, "tabActive": true}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    ui.send(
        json!({"id": 1, "cmd": "worktree", "workbench": "1a2b3c4d", "branch": "mover",
                   "destination": "move_current"}),
    )
    .await;
    let done = ui.reply(1).await;
    assert_eq!(done["ok"], true, "{done}");
    assert_eq!(done["workbench"], "1a2b3c4d", "a mesma bancada, pelo id");
    let wt = std::fs::canonicalize(&dir.0)
        .unwrap()
        .join("worktrees/repo/mover");
    let saved = saved_eventually(&h, |v| {
        v[0]["path"]
            .as_str()
            .is_some_and(|p| p.ends_with("worktrees/repo/mover"))
    })
    .await;
    assert_eq!(saved.as_array().unwrap().len(), 1, "não nasce bancada nova");
    for _ in 0..500 {
        if wt.join(".env").exists() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    assert!(wt.join(".env").exists());
    h.stop().await.unwrap();
}

#[tokio::test]
async fn worktree_com_template_nasce_do_molde_e_responde_o_id_da_nova() {
    let dir = TempHome::new();
    let repo = repo_with_env(&dir);
    let benches = json!([{"id": "1a2b3c4d", "name": "deck", "path": repo.to_string_lossy(),
                          "nodes": [{"type": "shell", "id": "origem"}]}]);
    let templates = json!({"dupla": {"nodes": [{"type": "shell", "id": "a"}, {"type": "shell", "id": "b"}], "view": "chat"}});
    let h = Harness::start_with_files(&[
        ("workbenches.json", benches.to_string()),
        ("templates.json", templates.to_string()),
    ])
    .await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "worktree", "workbench": "1a2b3c4d", "branch": "doida", "template": "dupla"})).await;
    let done = ui.reply(1).await;
    assert_eq!(done["ok"], true, "{done}");
    let id = done["workbench"].as_str().unwrap().to_owned();
    assert_ne!(id, "1a2b3c4d");
    let saved = saved_eventually(&h, |v| v.as_array().is_some_and(|l| l.len() == 2)).await;
    let nova = &saved[1];
    assert_eq!(nova["id"], id.as_str());
    let ids: Vec<&Value> = nova["nodes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|n| &n["id"])
        .collect();
    assert_eq!(
        ids,
        [&json!("a"), &json!("b")],
        "os nós são do molde, não da origem"
    );
    assert_eq!(nova["template"], "dupla");
    assert_eq!(nova["view"], "chat");

    ui.send(json!({"id": 2, "cmd": "worktree", "workbench": "1a2b3c4d", "branch": "x", "template": "nada"})).await;
    assert_eq!(ui.reply(2).await["error"], "template desconhecido 'nada'");
    // Mover a bancada atual não tem molde: recusa em vez de sumir com o pedido.
    ui.send(json!({"id": 3, "cmd": "worktree", "workbench": "1a2b3c4d", "branch": "y", "template": "dupla", "destination": "move_current"})).await;
    assert_eq!(
        ui.reply(3).await["error"],
        "template só vale para bancada nova"
    );
    h.stop().await.unwrap();
}

/// US-206: a worktree roda sobre uma cópia e leva segundos; o que você mexe
/// nesse meio-tempo não pode ser desfeito quando ela termina. O gancho
/// `post-checkout` atrasa o `git worktree add` o bastante para o teste mexer.
#[tokio::test]
async fn editar_durante_a_worktree_sobrevive_ao_reapontamento() {
    use std::os::unix::fs::PermissionsExt;
    let dir = TempHome::new();
    let repo = repo_with_env(&dir);
    let hook = repo.join(".git/hooks/post-checkout");
    std::fs::write(&hook, "#!/bin/sh\n/bin/sleep 1\n").unwrap();
    std::fs::set_permissions(&hook, std::fs::Permissions::from_mode(0o755)).unwrap();
    let benches = json!([{"id": "1a2b3c4d", "name": "deck", "path": repo.to_string_lossy(),
                          "nodes": [{"type": "shell", "id": "sh", "x": 10, "y": 20, "w": 300, "h": 200}]}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    let frame = |x: f64| json!({"x": x, "y": 20.0, "w": 300.0, "h": 200.0});

    // A bancada inteira vai para a worktree: o card movido no meio fica movido.
    ui.send(
        json!({"id": 2, "cmd": "worktree", "workbench": "1a2b3c4d", "branch": "mover",
                   "destination": "move_current"}),
    )
    .await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    ui.send(json!({"id": 3, "cmd": "move_node", "workbench": "1a2b3c4d", "node": "sh", "frame": frame(777.0)}))
        .await;
    assert_eq!(ui.reply(3).await["ok"], true);
    let done = ui.reply(2).await;
    assert_eq!(done["ok"], true, "{done}");
    let saved = saved_eventually(&h, |v| {
        v[0]["path"]
            .as_str()
            .is_some_and(|p| p.ends_with("worktrees/repo/mover"))
    })
    .await;
    assert_eq!(saved[0]["nodes"][0]["x"], 777.0, "{saved}");

    // Um terminal só: a pasta nova entra no nó de agora.
    let pending = {
        let get = h.get("/worktree?target=deck%2Fsh&branch=so-no");
        tokio::pin!(get);
        tokio::time::sleep(Duration::from_millis(300)).await;
        ui.send(json!({"id": 4, "cmd": "move_node", "workbench": "1a2b3c4d", "node": "sh", "frame": frame(888.0)}))
            .await;
        assert_eq!(ui.reply(4).await["ok"], true);
        get.await
    };
    assert_eq!(pending.0, 200, "{}", pending.1);
    let saved = saved_eventually(&h, |v| v[0]["nodes"][0].get("cwd").is_some()).await;
    assert_eq!(saved[0]["nodes"][0]["x"], 888.0, "{saved}");
    h.stop().await.unwrap();
}

/// US-401: o formulário de um workspace que ainda não existe pede o nome padrão
/// do multi-projeto sem id de workspace, e o salvar dá o nome padrão ao
/// multi-projeto que veio sem nome.
#[tokio::test]
async fn multi_name_sem_workspace_e_multi_sem_nome_recebem_o_nome_padrao() {
    let dir = TempHome::new();
    let (a, b) = (dir.0.join("nexus-backend"), dir.0.join("nexus-front"));
    std::fs::create_dir_all(&a).unwrap();
    std::fs::create_dir_all(&b).unwrap();
    let folders = json!([a.to_string_lossy(), b.to_string_lossy()]);
    let h = Harness::start().await;
    let mut ui = h.ui().await;

    ui.send(json!({"id": 1, "cmd": "multi_name", "folders": folders}))
        .await;
    assert_eq!(ui.reply(1).await["name"], "nexus-backend + nexus-front");

    ui.send(
        json!({"id": 2, "cmd": "save_workspace", "name": "Agro", "folders": folders,
                   "multis": [{"folders": folders}]}),
    )
    .await;
    let saved = ui.reply(2).await;
    assert!(saved["workspace"].is_string(), "{saved}");
    let agro = |v: &Value| {
        v.as_array()
            .and_then(|l| l.iter().find(|w| w["name"] == "Agro").cloned())
            .filter(|w| w["projects"].as_array().is_some_and(|p| p.len() == 3))
    };
    let file = spaces_eventually(&h, |v| agro(v).is_some()).await;
    let names: Vec<String> = agro(&file).unwrap()["projects"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["name"].as_str().unwrap().to_owned())
        .collect();
    assert!(
        names.contains(&"nexus-backend + nexus-front".to_owned()),
        "{names:?}"
    );
    h.stop().await.unwrap();
}

/// US-402: o nó que chega sem frame ganha o do layout padrão, e o frame do
/// arrasto respeita o mínimo do cartão.
#[tokio::test]
async fn no_novo_sem_frame_ganha_o_do_layout_padrao() {
    let dir = TempHome::new();
    let benches =
        json!([{"id": "1a2b3c4d", "name": "deck", "path": dir.0.to_string_lossy(), "nodes": []}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    for (id, extra) in [
        (1, json!({})),
        (2, json!({})),
        (
            3,
            json!({"frame": {"x": -20.0, "y": 10.0, "w": 5.0, "h": 5.0}}),
        ),
    ] {
        let mut cmd =
            json!({"id": id, "cmd": "create_node", "workbench": "1a2b3c4d", "type": "web"});
        cmd.as_object_mut()
            .unwrap()
            .extend(extra.as_object().unwrap().clone());
        ui.send(cmd).await;
        assert!(ui.reply(id).await["node"].is_string());
    }
    let saved = saved_eventually(&h, |v| {
        v[0]["nodes"].as_array().is_some_and(|n| n.len() == 3)
    })
    .await;
    let frame = |i: usize| {
        let n = &saved[0]["nodes"][i];
        [
            n["x"].as_f64().unwrap(),
            n["y"].as_f64().unwrap(),
            n["w"].as_f64().unwrap(),
            n["h"].as_f64().unwrap(),
        ]
    };
    // O layout padrão, sem janela: a coluna de 900×600, a linha de cada nó
    // entre todos os da bancada.
    assert_eq!(frame(0), [40.0, 40.0, 900.0, 600.0]);
    assert_eq!(frame(1), [40.0, 348.0, 900.0, 292.0]);
    assert_eq!(
        frame(2),
        [0.0, 10.0, 280.0, 180.0],
        "mínimo do cartão e dentro do documento"
    );
    h.stop().await.unwrap();
}

/// US-402: a regra do arrasto da porta é do core — só terminal liga, e o par já
/// ligado, em qualquer sentido, é ok sem segunda aresta.
#[tokio::test]
async fn ligar_recusa_quem_nao_tem_porta_e_nao_duplica_o_par() {
    let dir = TempHome::new();
    let benches = json!([{"id": "1a2b3c4d", "name": "deck", "path": dir.0.to_string_lossy(),
        "nodes": [{"type": "shell", "id": "a"}, {"type": "agent", "id": "b", "agent": "claude"},
                  {"type": "web", "id": "w"}, {"type": "agent", "id": "c", "agent": "claude"},
                  {"type": "queue", "id": "q"}]}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    let link = |id: u64, from: &str, to: &str, both: bool| json!({"id": id, "cmd": "link", "workbench": "1a2b3c4d", "from": from, "to": to, "both": both});

    ui.send(link(1, "a", "w", false)).await;
    assert_eq!(
        ui.reply(1).await["error"],
        "'w' não recebe ligação: só shell e agente"
    );
    ui.send(link(2, "w", "a", false)).await;
    assert_eq!(
        ui.reply(2).await["error"],
        "'w' não tem porta: só shell, agente e fila ligam"
    );
    ui.send(link(3, "a", "a", false)).await;
    assert_eq!(ui.reply(3).await["error"], "um nó não liga a si mesmo");
    ui.send(link(4, "a", "zz", false)).await;
    assert_eq!(ui.reply(4).await["error"], "nó desconhecido 'zz'");

    ui.send(link(5, "a", "b", false)).await;
    assert_eq!(ui.reply(5).await["ok"], true);
    // O mesmo par pelo outro lado, e de novo pelo mesmo: ok, e nada se soma.
    ui.send(link(6, "b", "a", true)).await;
    assert_eq!(ui.reply(6).await["ok"], true);
    ui.send(link(7, "a", "b", false)).await;
    assert_eq!(ui.reply(7).await["ok"], true);
    ui.send(link(8, "b", "c", true)).await;
    assert_eq!(ui.reply(8).await["ok"], true);
    // A fila tem porta e dá o destino dela; ninguém solta numa fila.
    ui.send(link(9, "a", "q", false)).await;
    assert_eq!(
        ui.reply(9).await["error"],
        "'q' não recebe ligação: só shell e agente"
    );
    // O arrasto da fila manda `both`: a volta é a que o `add` cria sozinho.
    ui.send(link(10, "q", "b", true)).await;
    assert_eq!(ui.reply(10).await["ok"], true);
    ui.send(link(11, "q", "c", false)).await;
    assert_eq!(ui.reply(11).await["ok"], true);

    let saved = saved_eventually(&h, |v| {
        v[0]["edges"].as_array().is_some_and(|e| e.len() == 6)
    })
    .await;
    let pairs: Vec<String> = saved[0]["edges"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| {
            format!(
                "{}>{}",
                e["from"].as_str().unwrap(),
                e["to"].as_str().unwrap()
            )
        })
        .collect();
    assert_eq!(pairs, ["a>b", "b>c", "c>b", "q>b", "b>q", "q>c"]);
    h.stop().await.unwrap();
}

/// US-402: o estado dos nós diz com quem cada um pode ligar — a regra do
/// arrasto da porta vem do core, e a UI só lê.
#[tokio::test]
async fn o_estado_dos_nos_diz_com_quem_cada_no_pode_ligar() {
    let dir = TempHome::new();
    let benches = json!([{"id": "1a2b3c4d", "name": "deck", "path": dir.0.to_string_lossy(),
        "nodes": [{"type": "shell", "id": "a"}, {"type": "agent", "id": "b", "agent": "claude"},
                  {"type": "web", "id": "w"}]}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    ui.send(json!({"id": 1, "cmd": "subscribe", "topic": "workbench/1a2b3c4d/nodes"}))
        .await;
    let state = ui.until(|v| v["topic"] == "workbench/1a2b3c4d/nodes").await;
    let linkable = |state: &Value, i: usize| state["nodes"][i]["linkable"].clone();
    assert_eq!(linkable(&state, 0), json!(["b"]));
    assert_eq!(linkable(&state, 1), json!(["a"]));
    assert_eq!(linkable(&state, 2), Value::Null, "web não tem porta");
    let port = |state: &Value, i: usize| state["nodes"][i]["port"].clone();
    assert_eq!(
        (port(&state, 0), port(&state, 1), port(&state, 2)),
        (json!(true), json!(true), json!(false))
    );

    ui.send(json!({"id": 2, "cmd": "link", "workbench": "1a2b3c4d", "from": "a", "to": "b"}))
        .await;
    let state = ui
        .until(|v| {
            v["topic"] == "workbench/1a2b3c4d/nodes"
                && v["links"].as_array().is_some_and(|l| !l.is_empty())
        })
        .await;
    assert_eq!(
        linkable(&state, 0),
        Value::Null,
        "o par já ligado sai da lista"
    );
    assert_eq!(linkable(&state, 1), Value::Null);
    h.stop().await.unwrap();
}

/// Bancada nova numa worktree de uma pasta, sem bancada de origem: o
/// `createWorkbenchFromWorktree` do Swift, pelo comando `worktree` sem `workbench`.
#[tokio::test]
async fn worktree_de_uma_pasta_sem_origem_abre_bancada_nova_com_o_template() {
    let dir = TempHome::new();
    let repo = repo_with_env(&dir);
    let templates =
        json!({"dupla": {"nodes": [{"type": "shell", "id": "a"}, {"type": "shell", "id": "b"}]}});
    let h = Harness::start_with_files(&[("templates.json", templates.to_string())]).await;
    let mut ui = h.ui().await;

    ui.send(
        json!({"id": 1, "cmd": "worktree", "path": repo.to_string_lossy(),
                   "branch": "da-pasta", "template": "dupla"}),
    )
    .await;
    let done = ui.reply(1).await;
    assert_eq!(done["ok"], true, "{done}");
    let id = done["workbench"].as_str().unwrap().to_owned();
    let saved = saved_eventually(&h, |v| v.as_array().is_some_and(|l| l.len() == 1)).await;
    assert_eq!(saved[0]["id"], id.as_str());
    assert_eq!(saved[0]["name"], "da-pasta");
    assert_eq!(saved[0]["template"], "dupla");
    assert_eq!(saved[0]["nodes"].as_array().unwrap().len(), 2);
    let wt = std::fs::canonicalize(&dir.0)
        .unwrap()
        .join("worktrees/repo/da-pasta");
    assert!(wt.join("a.txt").exists());
    for _ in 0..500 {
        if wt.join(".env").exists() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
    assert!(wt.join(".env").exists(), "o não versionado vem depois");

    ui.send(json!({"id": 2, "cmd": "worktree", "branch": "x"}))
        .await;
    assert_eq!(ui.reply(2).await["error"], "pede a pasta do repositório");
    ui.send(
        json!({"id": 3, "cmd": "worktree", "path": repo.to_string_lossy(), "branch": "y",
                   "destination": "move_current"}),
    )
    .await;
    assert_eq!(ui.reply(3).await["error"], "não há bancada para mover");
    ui.send(json!({"id": 4, "cmd": "worktree", "project": "fantasma", "branch": "z"}))
        .await;
    assert_eq!(
        ui.reply(4).await["error"],
        "projeto desconhecido 'fantasma'"
    );
    h.stop().await.unwrap();
}

/// O build da bancada dá frame a quem não tem e resgata quem estava fora do
/// documento, e grava (`defaultFrames` do Swift).
#[tokio::test]
async fn abrir_a_bancada_da_frame_a_quem_nao_tem_e_resgata_o_negativo() {
    let dir = TempHome::new();
    let benches = json!([{"id": "1a2b3c4d", "name": "deck", "path": dir.0.to_string_lossy(),
        "nodes": [{"type": "shell", "id": "a"},
                  {"type": "shell", "id": "b", "x": -50, "y": 20, "w": 300, "h": 200}],
        "tabOrder": 0, "tabActive": true}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let saved = saved_eventually(&h, |v| v[0]["nodes"][0].get("x").is_some()).await;
    assert_eq!(saved[0]["nodes"][0]["x"], 40.0);
    assert_eq!(saved[0]["nodes"][0]["w"], 900.0);
    assert_eq!(
        saved[0]["nodes"][1]["x"], 0.0,
        "o negativo é resgatado para 0"
    );
    h.stop().await.unwrap();
}

/// A janela que a UI informa (`ui_focus.window`) dá a altura da linha do nó que
/// nasce sem frame.
#[tokio::test]
async fn no_novo_sem_frame_usa_a_janela_da_ui() {
    let dir = TempHome::new();
    let benches =
        json!([{"id": "1a2b3c4d", "name": "deck", "path": dir.0.to_string_lossy(), "nodes": []}]);
    let h = Harness::start_with_files(&[("workbenches.json", benches.to_string())]).await;
    let mut ui = h.ui().await;
    ui.send(
        json!({"id": 1, "cmd": "ui_focus", "app_active": true, "window": {"w": 1400.0, "h": 1000.0}}),
    )
    .await;
    assert_eq!(ui.reply(1).await["ok"], true);
    ui.send(json!({"id": 2, "cmd": "create_node", "workbench": "1a2b3c4d", "type": "web"}))
        .await;
    assert!(ui.reply(2).await["node"].is_string());
    let saved = saved_eventually(&h, |v| {
        v[0]["nodes"].as_array().is_some_and(|n| n.len() == 1)
    })
    .await;
    assert_eq!(saved[0]["nodes"][0]["w"], 1320.0);
    assert_eq!(saved[0]["nodes"][0]["h"], 920.0);
    h.stop().await.unwrap();
}
