//! Dono: `terminal`. Liga ao ator a tela do terminal (decisão 26) e o
//! ⌘-clique, o hover com ⌘ e o arrasto de arquivo.
//!
//! Comandos do `/ui` que chegam aqui: scroll, pointer, select_all, copy,
//! clipboard_reply, link_hover e drop. `None` quer dizer que a resposta sai
//! depois (trabalho fora do ator, pela [`Actor::run_later`]). O core mantém a
//! assinatura; o corpo é do dono.
//!
//! A regra de cada gesto é da tela (`ports::screen`); aqui só se liga o gesto
//! ao pty, ao `Opener` e aos eventos, como o `MBTerminalView` do Swift fazia.

use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use base64::Engine;
use base64::engine::general_purpose::STANDARD;
use serde_json::json;

use super::{Actor, ClientId, NodeError};
use crate::commons::ids::NodeId;
use crate::features::terminal::{drop, link};
use crate::ports::opener::OpenTarget;
use crate::ports::screen::{LinkHit, Screen};
use crate::protocol::message::{CommandKind, Event, EventBody, Reply, Topic};
use crate::protocol::node::{Drop, LinkHover, PointerAt};
use crate::protocol::screen::PointerKind;

impl Actor {
    pub(super) fn terminal_command(
        &mut self,
        _client: ClientId,
        re: u64,
        kind: CommandKind,
    ) -> Option<Reply> {
        Some(match kind {
            CommandKind::Scroll(s) => self.on_screen(re, &s.node, |screen| screen.scroll(s.to)),
            CommandKind::Pointer(p) => {
                let outcome = self.pointer(&p);
                self.result(re, outcome)
            }
            CommandKind::SelectAll(s) => self.on_screen(re, &s.node, |screen| screen.select_all()),
            CommandKind::Copy(s) => match self.nodes.get_mut(&s.node) {
                Some(n) => Reply::with(re, &json!({ "text": n.screen.selection_text() })),
                None => Reply::err(re, NodeError::Unknown(s.node).to_string()),
            },
            CommandKind::ClipboardReply(c) => {
                let bytes = match self.nodes.get_mut(&c.node) {
                    Some(n) => n.screen.clipboard_answer(&c.text),
                    None => return Some(Reply::err(re, NodeError::Unknown(c.node).to_string())),
                };
                // Resposta ao programa, não entrada do usuário: não rola.
                self.result(re, self.write_raw(&c.node, &bytes))
            }
            CommandKind::LinkHover(h) => {
                // A mão acende sobre link mesmo sem destino (o clique apita);
                // sobre o nome solto, só se o arquivo existe (`linkUnder`).
                let link = match self.link_hit(&h) {
                    Some(LinkHit::Link(_)) => true,
                    Some(LinkHit::Word(word)) => self.resolve_link(&h.node, &word).is_some(),
                    None => false,
                };
                Reply::with(re, &json!({ "link": link }))
            }
            CommandKind::Drop(d) => {
                let outcome = self.drop_files(&d);
                self.result(re, outcome)
            }
            other => Reply::err(re, format!("{} não é comando de tela", other.name())),
        })
    }

    /// O sino e a área de transferência que o programa pediu desde o último
    /// `feed`, no tópico da tela.
    pub(super) fn screen_effects(&mut self, id: &NodeId) {
        let Some(node) = self.nodes.get_mut(id) else {
            return;
        };
        for effect in node.screen.take_effects() {
            self.publish(&Event {
                topic: Topic::Screen(id.clone()),
                body: EventBody::ScreenEffect(effect),
            });
        }
    }

    fn on_screen(&mut self, re: u64, node: &NodeId, act: impl FnOnce(&mut dyn Screen)) -> Reply {
        match self.nodes.get_mut(node) {
            Some(n) => {
                act(n.screen.as_mut());
                n.dirty = true;
                Reply::ok(re)
            }
            None => Reply::err(re, NodeError::Unknown(node.clone()).to_string()),
        }
    }

    /// O ⌘-clique num link é dele: abre (ou apita) e o programa não recebe o
    /// soltar, como no `mouseUp` do SwiftTerm. No nome solto o soltar vai ao
    /// programa antes, e o arquivo só abre se existir, calado quando não
    /// (o override do `MBTerminalView` chama o `super` primeiro).
    fn pointer(&mut self, p: &PointerAt) -> Result<(), NodeError> {
        let ev = &p.pointer;
        let hit = if ev.kind == PointerKind::Release && ev.mods.meta {
            self.link_hit(&LinkHover {
                node: p.node.clone(),
                x: ev.x,
                y: ev.y,
            })
        } else {
            None
        };
        if let Some(LinkHit::Link(text)) = &hit {
            self.open_link(&p.node, text);
            return Ok(());
        }
        let bytes = match self.nodes.get_mut(&p.node) {
            Some(n) => {
                n.dirty = true;
                n.screen.pointer(ev)
            }
            None => return Err(NodeError::Unknown(p.node.clone())),
        };
        self.write_raw(&p.node, &bytes)?;
        if let Some(LinkHit::Word(word)) = &hit
            && let Some(target) = self.resolve_link(&p.node, word)
        {
            crate::log!("terminal: ⌘-clique abre {} (nome solto)", shown(&target));
            self.drivers.opener.open(&target);
        }
        Ok(())
    }

    fn open_link(&self, id: &NodeId, text: &str) {
        match self.resolve_link(id, text) {
            Some(target) => {
                crate::log!("terminal[{id}]: ⌘-clique abre {}", shown(&target));
                if !self.drivers.opener.open(&target) {
                    self.drivers.opener.beep();
                }
            }
            None => {
                crate::log!("terminal[{id}]: ⌘-clique em \"{text}\" — nada que exista");
                self.drivers.opener.beep();
            }
        }
    }

    fn link_hit(&mut self, at: &LinkHover) -> Option<LinkHit> {
        let node = self.nodes.get_mut(&at.node)?;
        let size = node.screen.size();
        node.screen
            .link_at(cell(at.x, size.cols)?, cell(at.y, size.rows)?)
    }

    /// Contra a pasta do processo da frente e depois a pasta em que o nó
    /// abriu: o caminho relativo foi impresso de onde o processo está, e o
    /// `cd` pode tê-lo levado para longe da pasta do nó.
    fn resolve_link(&self, id: &NodeId, text: &str) -> Option<OpenTarget> {
        let node = self.nodes.get(id)?;
        let front = node.session.as_ref().and_then(|s| s.foreground_dir());
        let mut dirs: Vec<&Path> = front.iter().map(|p| p.as_path()).collect();
        dirs.push(Path::new(&node.info.cwd));
        link::resolve(text, &dirs, &self.config.default_cwd, Path::exists)
    }

    /// Só o caminho, e o Enter é seu: arrastar um arquivo é entregá-lo, não
    /// mandar o agente sair trabalhando com ele.
    fn drop_files(&mut self, d: &Drop) -> Result<(), NodeError> {
        let mut paths = d.paths.clone();
        if paths.is_empty()
            && let Some(png) = &d.png
        {
            let bytes = STANDARD
                .decode(png)
                .map_err(|e| NodeError::Screen(format!("drop: png em base64 inválido: {e}")))?;
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map_or(0, |t| t.as_millis());
            let flavor = self.config.flavor.identifier();
            let saved =
                drop::save_image(&bytes, &std::env::temp_dir(), flavor, now).map_err(|e| {
                    NodeError::Screen(format!(
                        "drop: imagem sem arquivo não pôde ser gravada: {e}"
                    ))
                })?;
            paths.push(saved.to_string_lossy().into_owned());
        }
        let refs: Vec<&str> = paths.iter().map(String::as_str).collect();
        let Some(text) = drop::text(&refs) else {
            return Ok(());
        };
        // Agente que recebe prompt por bracketed paste recebe o arrasto como
        // colagem, sempre, e não pelo modo da tela: o Claude Code só troca o
        // caminho de imagem por `[Image #1]` no evento de paste. No shell o
        // marcador voltaria literal (ADR-007).
        let bytes = if self.drop_as_paste(&d.node) {
            format!("\x1b[200~{text}\x1b[201~").into_bytes()
        } else {
            text.clone().into_bytes()
        };
        self.write(&d.node, &bytes)?;
        crate::log!("drop: caminho injetado no terminal: {}", text.trim());
        Ok(())
    }

    fn drop_as_paste(&self, id: &NodeId) -> bool {
        self.node_profile(id)
            .is_some_and(|p| p.inject_config().mode == "bracketed-paste")
    }
}

fn shown(target: &OpenTarget) -> String {
    match target {
        OpenTarget::File(p) => p.display().to_string(),
        OpenTarget::Url(u) => u.clone(),
    }
}

/// A célula sob o ponto em células fracionárias; fora da vista, nenhuma.
fn cell(v: f32, n: u16) -> Option<u16> {
    (v.is_finite() && v >= 0.0 && v < f32::from(n)).then_some(v as u16)
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::sync::Arc;
    use std::sync::atomic::Ordering;

    use serde_json::{Value, json};
    use tokio::sync::{mpsc, oneshot};

    use super::super::{Actor, Msg};
    use crate::commons::paths::{Flavor, Paths};
    use crate::features::agent::model::AgentProfile;
    use crate::features::workbench::model::WorkbenchConfig;
    use crate::ports::opener::OpenTarget;
    use crate::ports::pty::PtyEvent;
    use crate::protocol::message::{Command, NodeId};
    use crate::runtime::fakes::{
        ChildLog, FakeApps, FakeCloner, FakeFolders, FakeLinks, FakeLocal, FakeNotifier,
        FakeOpener, FakeProcs, FakePty, FakeScreens, fake_executable,
    };
    use crate::runtime::{Config, Drivers};

    struct Bench {
        actor: Actor,
        outbox: mpsc::Receiver<Arc<[u8]>>,
        client: u64,
        pty: Arc<FakePty>,
        opener: Arc<FakeOpener>,
        dir: tempfile::TempDir,
        next: u64,
    }

    impl Bench {
        /// Um ator com um terminal `t1` aberto em `dir`, e o cliente assinando
        /// a tela dele.
        fn new() -> Self {
            let dir = tempfile::tempdir().unwrap();
            let pty = Arc::new(FakePty::default());
            let opener = Arc::new(FakeOpener::default());
            let drivers = Drivers {
                pty: pty.clone(),
                screens: Arc::new(FakeScreens),
                local: Arc::new(FakeLocal::default()),
                procs: Arc::new(FakeProcs::default()),
                notifier: Arc::new(FakeNotifier::default()),
                apps: Arc::new(FakeApps),
                installer: Arc::new(FakeApps),
                opener: opener.clone(),
                cloner: Arc::new(FakeCloner),
                links: Arc::new(FakeLinks),
                is_executable: fake_executable,
                folders: Arc::new(FakeFolders::default()),
            };
            let config = Config {
                paths: Paths::new(dir.path().join("data")),
                default_cwd: PathBuf::from("/Users/eu"),
                flavor: Flavor::Stable,
                cli_binary: None,
                ui_parent: false,
                version: "9.9.9".into(),
                build: "42".into(),
            };
            let (inbox, _rx) = mpsc::channel(64);
            let mut actor = Actor::new(config, drivers, inbox);
            let (queue, outbox) = mpsc::channel(64);
            let (tx, mut id) = oneshot::channel();
            let (alive, _hung_up) = oneshot::channel();
            actor.handle(Msg::UiOpen {
                queue,
                alive,
                reply: tx,
            });
            let client = id.try_recv().unwrap();
            let mut b = Self {
                actor,
                outbox,
                client,
                pty,
                opener,
                dir,
                next: 1,
            };
            let cwd = b.dir.path().to_string_lossy().into_owned();
            b.send(json!({"cmd": "create_terminal", "cwd": cwd}));
            b.send(json!({"cmd": "subscribe", "topic": "screen/t1"}));
            b.drain();
            b
        }

        fn send(&mut self, mut body: Value) -> Value {
            body["id"] = json!(self.next);
            self.next += 1;
            let command: Command = serde_json::from_value(body).unwrap();
            self.actor.handle(Msg::UiCommand {
                client: self.client,
                command,
            });
            self.recv()
        }

        fn recv(&mut self) -> Value {
            serde_json::from_slice(&self.outbox.try_recv().unwrap()).unwrap()
        }

        fn drain(&mut self) {
            while self.outbox.try_recv().is_ok() {}
        }

        fn output(&mut self, text: &str) {
            self.actor.handle(Msg::Pty {
                node: NodeId::new("t1").unwrap(),
                generation: 1,
                event: PtyEvent::Output(text.as_bytes().to_vec()),
            });
        }

        fn log(&self) -> Arc<ChildLog> {
            self.pty.child(0).0
        }

        fn writes(&self) -> Vec<u8> {
            std::mem::take(&mut *self.log().writes.lock().unwrap())
        }

        fn pointer(&mut self, kind: &str, x: f32, meta: bool) -> Value {
            self.send(json!({
                "cmd": "pointer", "node": "t1", "kind": kind, "button": "left",
                "x": x, "y": 0.5, "mods": {"meta": meta}, "time_ms": 0
            }))
        }
    }

    #[tokio::test]
    async fn cmd_clique_em_link_abre_e_o_programa_nao_recebe_o_soltar() {
        let mut b = Bench::new();
        b.output("veja https://egeon.dev/a");
        assert_eq!(b.pointer("release", 7.5, true)["ok"], true);
        let opened = b.opener.opened.lock().unwrap().clone();
        assert_eq!(opened, vec![OpenTarget::Url("https://egeon.dev/a".into())]);
        assert!(b.writes().is_empty(), "o soltar não vai ao programa");
    }

    #[tokio::test]
    async fn cmd_clique_em_link_sem_destino_apita() {
        let mut b = Bench::new();
        b.output("veja nao/existe.md");
        b.pointer("release", 7.5, true);
        assert!(b.opener.opened.lock().unwrap().is_empty());
        assert_eq!(b.opener.beeps.load(Ordering::SeqCst), 1);
        assert!(b.writes().is_empty());
    }

    #[tokio::test]
    async fn cmd_clique_em_nome_solto_entrega_o_soltar_e_abre_se_existe() {
        let mut b = Bench::new();
        std::fs::write(b.dir.path().join("README.md"), "").unwrap();
        b.output("veja README.md");
        b.pointer("release", 7.5, true);
        assert_eq!(b.writes(), b"release", "o soltar vai ao programa antes");
        let opened = b.opener.opened.lock().unwrap().clone();
        assert_eq!(
            opened,
            vec![OpenTarget::File(b.dir.path().join("README.md"))]
        );
    }

    #[tokio::test]
    async fn cmd_clique_em_nome_solto_que_nao_existe_fica_calado() {
        let mut b = Bench::new();
        b.output("veja sumiu.md");
        b.pointer("release", 7.5, true);
        assert_eq!(b.writes(), b"release");
        assert!(b.opener.opened.lock().unwrap().is_empty());
        assert_eq!(
            b.opener.beeps.load(Ordering::SeqCst),
            0,
            "nome solto não apita"
        );
    }

    #[tokio::test]
    async fn soltar_sem_cmd_ou_sem_link_vai_a_tela() {
        let mut b = Bench::new();
        b.output("veja https://egeon.dev/a");
        b.pointer("release", 7.5, false);
        assert_eq!(b.writes(), b"release");
        b.pointer("release", 1.5, true);
        assert_eq!(b.writes(), b"release");
        assert!(b.opener.opened.lock().unwrap().is_empty());
        assert_eq!(b.opener.beeps.load(Ordering::SeqCst), 0);
        // A roda da FakeScreen vira bytes, que vão crus ao pty.
        let reply = b.send(json!({
            "cmd": "pointer", "node": "t1", "kind": "wheel", "x": 1.0, "y": 0.5, "lines": 3
        }));
        assert_eq!(reply["ok"], true);
        assert_eq!(b.writes(), b"wheel+3");
    }

    #[tokio::test]
    async fn hover_acende_em_link_e_em_nome_solto_que_existe() {
        let mut b = Bench::new();
        std::fs::write(b.dir.path().join("a.txt"), "").unwrap();
        b.output("a.txt b.txt c/d.md");
        let hover = |b: &mut Bench, x: f32| {
            b.send(json!({"cmd": "link_hover", "node": "t1", "x": x, "y": 0.2}))["link"].clone()
        };
        assert_eq!(hover(&mut b, 1.0), true, "nome solto que existe");
        assert_eq!(hover(&mut b, 7.0), false, "nome solto que não existe");
        // Link acende mesmo sem destino; o clique é que apita.
        assert_eq!(hover(&mut b, 13.0), true);
        assert_eq!(hover(&mut b, 99.0), false);
    }

    #[tokio::test]
    async fn selecionar_tudo_e_copiar() {
        let mut b = Bench::new();
        b.output("oi\nmundo");
        assert_eq!(
            b.send(json!({"cmd": "copy", "node": "t1"}))["text"],
            Value::Null
        );
        assert_eq!(
            b.send(json!({"cmd": "select_all", "node": "t1"}))["ok"],
            true
        );
        assert_eq!(
            b.send(json!({"cmd": "copy", "node": "t1"}))["text"],
            "oi\nmundo"
        );
        let unknown = b.send(json!({"cmd": "copy", "node": "t9"}));
        assert_eq!(unknown["ok"], false);
    }

    #[tokio::test]
    async fn resposta_da_area_de_transferencia_vai_ao_pty() {
        let mut b = Bench::new();
        let reply = b.send(json!({"cmd": "clipboard_reply", "node": "t1", "text": "xyz"}));
        assert_eq!(reply["ok"], true);
        assert_eq!(b.writes(), b"clipboard:xyz");
    }

    #[tokio::test]
    async fn arrasto_de_arquivos_escreve_os_caminhos_citados() {
        let mut b = Bench::new();
        let reply = b.send(json!({
            "cmd": "drop", "node": "t1", "paths": ["/tmp/um arquivo.pdf", "/tmp/b.swift"]
        }));
        assert_eq!(reply["ok"], true);
        // Terminal solto não tem perfil: vai cru, sem o embrulho do paste.
        assert_eq!(b.writes(), b"'/tmp/um arquivo.pdf' /tmp/b.swift ");
    }

    #[tokio::test]
    async fn arrasto_num_agente_de_bracketed_paste_vai_como_colagem() {
        let mut b = Bench::new();
        let bench: WorkbenchConfig = serde_json::from_value(json!({
            "id": "wb", "name": "bancada", "path": b.dir.path(),
            "nodes": [{"id": "n", "type": "agent", "agent": "claude"}]
        }))
        .unwrap();
        b.actor.org.state.workbenches.push(bench);
        // O modo de injeção padrão do perfil é o bracketed-paste.
        b.actor
            .org
            .profiles
            .insert("claude".into(), AgentProfile::default());
        b.actor.open_terminals("wb");
        b.drain();
        let reply = b.send(json!({"cmd": "drop", "node": "wb.n", "paths": ["/tmp/a.png"]}));
        assert_eq!(reply["ok"], true, "{reply}");
        let agent = b.pty.child(1).0;
        let written = std::mem::take(&mut *agent.writes.lock().unwrap());
        assert_eq!(written, b"\x1b[200~/tmp/a.png \x1b[201~");
    }

    #[tokio::test]
    async fn arrasto_de_imagem_sem_arquivo_grava_e_escreve_o_caminho() {
        let mut b = Bench::new();
        let reply = b.send(json!({"cmd": "drop", "node": "t1", "png": "aGVsbG8="}));
        assert_eq!(reply["ok"], true);
        let written = String::from_utf8(b.writes()).unwrap();
        let path = written.trim_end();
        let sep = std::path::MAIN_SEPARATOR;
        assert!(
            path.contains(&format!("egeon-next-drop{sep}drop-")),
            "{path}"
        );
        assert_eq!(std::fs::read(path).unwrap(), b"hello");
        let _ = std::fs::remove_file(path);

        let bad = b.send(json!({"cmd": "drop", "node": "t1", "png": "%%%"}));
        assert_eq!(bad["ok"], false);
    }

    #[tokio::test]
    async fn sino_vira_evento_no_topico_da_tela() {
        let mut b = Bench::new();
        b.output("a\x07");
        let event = b.recv();
        assert_eq!(event["topic"], "screen/t1");
        assert_eq!(event["effect"], "bell");
    }

    #[tokio::test]
    async fn rolar_responde_ok() {
        let mut b = Bench::new();
        let reply = b.send(json!({"cmd": "scroll", "node": "t1", "to": {"rows": -3}}));
        assert_eq!(reply["ok"], true);
        let unknown = b.send(json!({"cmd": "scroll", "node": "t9", "to": "bottom"}));
        assert_eq!(unknown["ok"], false);
    }
}
