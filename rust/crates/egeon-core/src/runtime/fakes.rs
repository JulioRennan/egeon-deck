//! Pty, tela e escuta falsos: o runtime inteiro roda nos testes sem sistema
//! operacional.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime};

use tokio::io::DuplexStream;
use tokio::sync::mpsc;

use crate::ports::file_clone::FileCloner;
use crate::ports::installer::{AppInstaller, InstallError, Swap, UnpackedApp};
use crate::ports::links::FileLinks;
use crate::ports::local_conn::{
    BoxFuture, LocalConn, LocalConnDriver, LocalConnError, LocalListener, Probe,
};
use crate::ports::notifier::{Notice, NoticeClick, Notifier, SoundError};
use crate::ports::opener::{OpenTarget, Opener};
use crate::ports::procs::{
    AppDriver, ProcessDetail, ProcessDriver, ProcessError, ProcessSignal, RawProcess, RunningApp,
    SocketLinks,
};
use crate::ports::pty::{
    PtyChild, PtyDriver, PtyError, PtyEvent, PtySession, PtySignal, PtySize, PtySpec,
};
use crate::ports::screen::{LinkHit, Screen, ScreenError, ScreenFactory};
use crate::protocol::screen::{
    Cursor, CursorShape, Effect, Frame, FrameKind, Key, KeyPress, Line, NamedKey, Pointer,
    PointerKind, Scroll, Scrollbar, Size, Span, Style,
};

#[derive(Default)]
pub struct ChildLog {
    pub writes: Mutex<Vec<u8>>,
    pub signals: Mutex<Vec<PtySignal>>,
    pub sizes: Mutex<Vec<PtySize>>,
}

/// Um filho lançado: o que o core pediu, o que fez com ele e o lado do teste
/// do canal de eventos.
pub struct Spawned {
    pub spec: PtySpec,
    pub log: Arc<ChildLog>,
    pub events: mpsc::Sender<PtyEvent>,
}

/// O que pty e tabela de processos falsos fizeram, na ordem: é o que prova
/// que a árvore foi lida antes do HUP no shell.
pub type Journal = Arc<Mutex<Vec<String>>>;

#[derive(Default)]
pub struct FakePty {
    pub spawned: Mutex<Vec<Spawned>>,
    next_pid: AtomicU32,
    pub journal: Journal,
    /// O shell do usuário; `None` é o do macOS.
    pub shell: Option<PathBuf>,
}

impl FakePty {
    pub fn child(&self, index: usize) -> (Arc<ChildLog>, mpsc::Sender<PtyEvent>, PtySpec) {
        let spawned = self.spawned.lock().unwrap();
        let s = &spawned[index];
        (s.log.clone(), s.events.clone(), s.spec.clone())
    }
}

struct FakeSession {
    pid: u32,
    log: Arc<ChildLog>,
    journal: Journal,
}

impl PtySession for FakeSession {
    fn pid(&self) -> u32 {
        self.pid
    }
    fn write(&self, data: &[u8]) -> Result<(), PtyError> {
        self.log.writes.lock().unwrap().extend_from_slice(data);
        Ok(())
    }
    fn resize(&self, size: PtySize) -> Result<(), PtyError> {
        self.log.sizes.lock().unwrap().push(size);
        Ok(())
    }
    fn signal(&self, signal: PtySignal) -> Result<(), PtyError> {
        self.log.signals.lock().unwrap().push(signal);
        self.journal
            .lock()
            .unwrap()
            .push(format!("pty {} {signal:?}", self.pid));
        Ok(())
    }
}

impl PtyDriver for FakePty {
    fn spawn(&self, spec: PtySpec) -> Result<PtyChild, PtyError> {
        let (tx, rx) = mpsc::channel(64);
        let log = Arc::new(ChildLog::default());
        let pid = 1000 + self.next_pid.fetch_add(1, Ordering::SeqCst);
        self.spawned.lock().unwrap().push(Spawned {
            spec,
            log: log.clone(),
            events: tx,
        });
        Ok(PtyChild {
            session: Box::new(FakeSession {
                pid,
                log,
                journal: self.journal.clone(),
            }),
            events: rx,
        })
    }

    fn path_dirs(&self, home: &Path) -> Vec<PathBuf> {
        vec![home.join(".fake/bin")]
    }

    fn user_shell(&self) -> PathBuf {
        self.shell
            .clone()
            .unwrap_or_else(|| PathBuf::from(crate::features::terminal::model::LAUNCH_SHELL))
    }
}

/// Tela de brinquedo: `\n` desce uma linha, `\r` volta à coluna 0, o resto
/// escreve. Responde ao pedido de posição do cursor (`ESC[6n`); `BEL` vira o
/// efeito de sino. A roda devolve `wheel±N` como bytes, a vista não rola, e a
/// seleção é tudo ou nada.
pub struct FakeScreen {
    size: Size,
    rows: Vec<String>,
    row: usize,
    dirty: Vec<bool>,
    all_dirty: bool,
    answer: Vec<u8>,
    bracketed: bool,
    selected: bool,
    effects: Vec<Effect>,
}

impl FakeScreen {
    fn new(size: Size) -> Self {
        Self {
            size,
            rows: vec![String::new(); size.rows as usize],
            row: 0,
            dirty: vec![false; size.rows as usize],
            all_dirty: false,
            answer: Vec::new(),
            bracketed: false,
            selected: false,
            effects: Vec::new(),
        }
    }

    fn line(&self, row: usize) -> Line {
        let text = &self.rows[row];
        Line {
            row: row as u16,
            spans: if text.is_empty() {
                vec![]
            } else {
                vec![Span {
                    col: 0,
                    cells: text.chars().count() as u16,
                    text: text.clone(),
                    style: Style::default(),
                }]
            },
            selection: (self.selected && !text.is_empty())
                .then(|| [0, text.chars().count() as u16 - 1]),
        }
    }

    fn frame_of(&self, kind: FrameKind, rows: impl Iterator<Item = usize>) -> Frame {
        Frame {
            kind,
            cols: self.size.cols,
            rows: self.size.rows,
            cursor: Cursor {
                row: self.row as u16,
                col: self.rows[self.row].chars().count() as u16,
                visible: true,
                shape: CursorShape::Block,
            },
            scrollbar: (kind == FrameKind::Full).then_some(Scrollbar {
                total: u64::from(self.size.rows),
                offset: 0,
                len: u64::from(self.size.rows),
            }),
            lines: rows.map(|r| self.line(r)).collect(),
        }
    }
}

impl Screen for FakeScreen {
    fn bracketed_paste(&self) -> bool {
        self.bracketed
    }

    fn feed(&mut self, bytes: &[u8]) {
        let text = String::from_utf8_lossy(bytes).into_owned();
        if text.contains("\x1b[6n") {
            self.answer.extend_from_slice(b"\x1b[1;1R");
        }
        // O último dos dois que aparecer vale, como num terminal de verdade.
        match (text.rfind("\x1b[?2004h"), text.rfind("\x1b[?2004l")) {
            (Some(on), Some(off)) => self.bracketed = on > off,
            (Some(_), None) => self.bracketed = true,
            (None, Some(_)) => self.bracketed = false,
            (None, None) => {}
        }
        for ch in text.replace("\x1b[6n", "").chars() {
            match ch {
                '\x07' => self.effects.push(Effect::Bell),
                '\n' => {
                    if self.row + 1 < self.rows.len() {
                        self.row += 1;
                    } else {
                        self.rows.remove(0);
                        self.rows.push(String::new());
                        self.all_dirty = true;
                    }
                }
                '\r' => {}
                c => {
                    self.rows[self.row].push(c);
                    self.dirty[self.row] = true;
                }
            }
        }
    }

    fn take_responses(&mut self) -> Vec<u8> {
        std::mem::take(&mut self.answer)
    }

    fn resize(&mut self, size: Size) -> Result<(), ScreenError> {
        if size.cols == 0 || size.rows == 0 {
            return Err(ScreenError::InvalidSize {
                cols: size.cols,
                rows: size.rows,
            });
        }
        self.size = size;
        self.rows.resize(size.rows as usize, String::new());
        self.dirty = vec![false; size.rows as usize];
        self.row = self.row.min(self.rows.len() - 1);
        self.all_dirty = true;
        Ok(())
    }

    fn size(&self) -> Size {
        self.size
    }

    fn full_frame(&mut self) -> Frame {
        self.frame_of(FrameKind::Full, 0..self.rows.len())
    }

    fn take_delta(&mut self) -> Option<Frame> {
        if self.all_dirty {
            self.all_dirty = false;
            self.dirty.fill(false);
            return Some(self.frame_of(FrameKind::Full, 0..self.rows.len()));
        }
        let rows: Vec<usize> = (0..self.rows.len()).filter(|r| self.dirty[*r]).collect();
        if rows.is_empty() {
            return None;
        }
        self.dirty.fill(false);
        Some(self.frame_of(FrameKind::Delta, rows.into_iter()))
    }

    fn rows_text(&mut self) -> Vec<String> {
        self.rows.clone()
    }

    fn encode_key(&mut self, key: &KeyPress) -> Vec<u8> {
        match &key.key {
            Key::Named(NamedKey::Enter) => b"\r".to_vec(),
            Key::Named(NamedKey::Up) => b"\x1b[A".to_vec(),
            Key::Named(_) => Vec::new(),
            Key::Char(c) if key.mods.ctrl => c.bytes().map(|b| b & 0x1f).collect(),
            Key::Char(c) => key.text.clone().unwrap_or_else(|| c.clone()).into_bytes(),
        }
    }

    fn scroll(&mut self, _to: Scroll) {}

    fn pointer(&mut self, event: &Pointer) -> Vec<u8> {
        match event.kind {
            PointerKind::Wheel => format!("wheel{:+}", event.lines).into_bytes(),
            PointerKind::Release => b"release".to_vec(),
            PointerKind::Press => {
                self.selected = false;
                Vec::new()
            }
            _ => Vec::new(),
        }
    }

    fn select_all(&mut self) {
        self.selected = true;
        self.all_dirty = true;
    }

    fn selection_text(&mut self) -> Option<String> {
        self.selected.then(|| {
            let lines: Vec<&str> = self.rows.iter().map(|r| r.trim_end()).collect();
            lines.join("\n").trim_end().to_owned()
        })
    }

    fn clipboard_answer(&mut self, text: &str) -> Vec<u8> {
        format!("clipboard:{text}").into_bytes()
    }

    fn take_effects(&mut self) -> Vec<Effect> {
        std::mem::take(&mut self.effects)
    }

    /// A palavra entre espaços sob a coluna: com `/` é link (a regex do
    /// Ghostty pega caminho com barra), só com `.` é nome solto.
    fn link_at(&mut self, col: u16, row: u16) -> Option<LinkHit> {
        let line: Vec<char> = self.rows.get(usize::from(row))?.chars().collect();
        let col = usize::from(col);
        if line.get(col)?.is_whitespace() {
            return None;
        }
        let start = line[..col]
            .iter()
            .rposition(|c| c.is_whitespace())
            .map_or(0, |i| i + 1);
        let end = line[col..]
            .iter()
            .position(|c| c.is_whitespace())
            .map_or(line.len(), |i| col + i);
        let word: String = line[start..end].iter().collect();
        if word.contains('/') {
            return Some(LinkHit::Link(word));
        }
        word.contains('.').then_some(LinkHit::Word(word))
    }
}

#[derive(Default)]
pub struct FakeScreens;

impl ScreenFactory for FakeScreens {
    fn create(&self, size: Size) -> Result<Box<dyn Screen>, ScreenError> {
        Ok(Box::new(FakeScreen::new(size)))
    }
}

/// Escuta em memória: [`FakeLocal::connect`] devolve o lado do cliente de um
/// `duplex` e entrega o outro lado ao `accept` da escuta aberta agora.
pub struct FakeLocal {
    sender: Mutex<Option<mpsc::Sender<LocalConn>>>,
    pub probe: Mutex<Probe>,
    pub listens: AtomicUsize,
    /// Quando `false`, a escuta atual diz que o arquivo não é mais dela.
    pub current: Arc<AtomicBool>,
}

impl Default for FakeLocal {
    fn default() -> Self {
        Self {
            sender: Mutex::new(None),
            probe: Mutex::new(Probe::Nobody),
            listens: AtomicUsize::new(0),
            current: Arc::new(AtomicBool::new(true)),
        }
    }
}

impl FakeLocal {
    pub async fn connect(&self) -> DuplexStream {
        let (client, server) = tokio::io::duplex(1 << 16);
        let tx = loop {
            // O core pode ainda não ter aberto a escuta.
            if let Some(tx) = self.sender.lock().unwrap().clone() {
                break tx;
            }
            tokio::task::yield_now().await;
        };
        tx.send(LocalConn {
            stream: Box::new(server),
            peer_pid: Some(4242),
        })
        .await
        .unwrap();
        client
    }
}

struct FakeListener {
    incoming: tokio::sync::Mutex<mpsc::Receiver<LocalConn>>,
    current: Arc<AtomicBool>,
}

impl LocalConnDriver for FakeLocal {
    fn listen(&self, _path: &Path) -> Result<Box<dyn LocalListener>, LocalConnError> {
        self.listens.fetch_add(1, Ordering::SeqCst);
        let (tx, rx) = mpsc::channel(16);
        *self.sender.lock().unwrap() = Some(tx);
        self.current.store(true, Ordering::SeqCst);
        Ok(Box::new(FakeListener {
            incoming: tokio::sync::Mutex::new(rx),
            current: self.current.clone(),
        }))
    }

    fn probe(&self, _path: &Path) -> Probe {
        *self.probe.lock().unwrap()
    }
}

impl LocalListener for FakeListener {
    fn accept(&self) -> BoxFuture<'_, Result<LocalConn, LocalConnError>> {
        Box::pin(async move {
            match self.incoming.lock().await.recv().await {
                Some(conn) => Ok(conn),
                None => std::future::pending().await,
            }
        })
    }

    fn is_current(&self) -> bool {
        self.current.load(Ordering::SeqCst)
    }
}

pub fn process(pid: u32, ppid: u32, started: u64) -> RawProcess {
    RawProcess {
        pid,
        ppid,
        started: SystemTime::UNIX_EPOCH + Duration::from_secs(started),
        name: "p".into(),
        command: "p".into(),
        environment: HashMap::new(),
    }
}

/// Tabela de processos de brinquedo: `table` é o que a leitura de agora
/// devolve, e `signals` o que se mandou a quem.
#[derive(Default)]
pub struct FakeProcs {
    pub journal: Journal,
    pub table: Mutex<Vec<RawProcess>>,
    pub signals: Mutex<Vec<(u32, ProcessSignal)>>,
}

impl FakeProcs {
    pub fn sharing(journal: Journal) -> Self {
        Self {
            journal,
            ..Self::default()
        }
    }
}

impl ProcessDriver for FakeProcs {
    fn list(&self, _detail: ProcessDetail) -> Result<Vec<RawProcess>, ProcessError> {
        Ok(self.table.lock().unwrap().clone())
    }

    fn environment_of(&self, _pid: u32) -> Option<HashMap<String, String>> {
        None
    }

    fn parent_of(&self, pid: u32) -> Option<u32> {
        let table = self.table.lock().unwrap();
        table.iter().find(|p| p.pid == pid).map(|p| p.ppid)
    }

    fn signal(&self, pid: u32, signal: ProcessSignal) -> Result<(), ProcessError> {
        self.signals.lock().unwrap().push((pid, signal));
        self.journal
            .lock()
            .unwrap()
            .push(format!("procs {pid} {signal:?}"));
        Ok(())
    }
}

/// Notificador de brinquedo: guarda o que pediram.
#[derive(Default)]
pub struct FakeNotifier {
    /// A ponta do clique: o teste "clica" por aqui.
    pub clicks: Mutex<Option<mpsc::Sender<NoticeClick>>>,
    pub posted: Mutex<Vec<Notice>>,
    pub withdrawn: Mutex<Vec<String>>,
    pub sounds: Mutex<Vec<(String, f64)>>,
}

impl Notifier for FakeNotifier {
    fn start(&self) -> mpsc::Receiver<NoticeClick> {
        let (tx, rx) = mpsc::channel(4);
        if let Ok(mut clicks) = self.clicks.lock() {
            *clicks = Some(tx);
        }
        rx
    }
    fn authorized(&self) -> bool {
        true
    }
    fn post(&self, notice: Notice) {
        self.posted.lock().unwrap().push(notice);
    }
    fn withdraw(&self, identifier: &str) {
        self.withdrawn.lock().unwrap().push(identifier.to_owned());
    }
    fn play_sound(&self, name: &str, volume: f64) -> Result<(), SoundError> {
        self.sounds.lock().unwrap().push((name.to_owned(), volume));
        Ok(())
    }
}

/// Sem apps abertos nem instalador: o que precisa deles responde que não há.
#[derive(Default)]
pub struct FakeApps;

impl AppDriver for FakeApps {
    fn running_apps(&self) -> Vec<RunningApp> {
        Vec::new()
    }
    fn request_quit(&self, _pid: u32) {}
    fn socket_links(&self) -> Option<SocketLinks> {
        None
    }
    fn container_working_dirs(&self) -> Option<Vec<String>> {
        None
    }
}

impl AppInstaller for FakeApps {
    fn can_install(&self, _destination: &Path) -> bool {
        false
    }
    fn unpack(&self, _zip: &Path, _into: &Path) -> Result<UnpackedApp, InstallError> {
        Err(InstallError::NotInstallable("teste".into()))
    }
    fn stage(&self, _app: &UnpackedApp, _staged: &Path) -> Result<(), InstallError> {
        Err(InstallError::NotInstallable("teste".into()))
    }
    fn launch_swap(&self, _swap: Swap<'_>) -> std::io::Result<()> {
        Err(std::io::Error::other("teste"))
    }
}

/// Abridor de brinquedo: guarda o que pediram para abrir e os alertas.
#[derive(Default)]
pub struct FakeOpener {
    pub opened: Mutex<Vec<OpenTarget>>,
    pub beeps: AtomicUsize,
}

impl Opener for FakeOpener {
    fn open(&self, target: &OpenTarget) -> bool {
        self.opened.lock().unwrap().push(target.clone());
        true
    }
    fn beep(&self) {
        self.beeps.fetch_add(1, Ordering::SeqCst);
    }
}

/// Clonagem como cópia simples: o teste não depende do APFS.
#[derive(Default)]
pub struct FakeCloner;

impl FileCloner for FakeCloner {
    fn clone_entry(&self, from: &Path, to: &Path) -> std::io::Result<()> {
        std::fs::copy(from, to).map(|_| ())
    }
}

/// Não toca o disco: link e bit de execução de verdade mudam por sistema, e o
/// core não tem `cfg`. Nenhum teste do core lê o link nem o bit; as chamadas
/// reais são testadas no driver (`egeon-driver/tests/file_clone.rs`).
#[derive(Default)]
pub struct FakeLinks;

impl FileLinks for FakeLinks {
    fn symlink(&self, _target: &Path, _link: &Path) -> std::io::Result<()> {
        Ok(())
    }
    fn make_executable(&self, _path: &Path) -> std::io::Result<()> {
        Ok(())
    }
}

/// Nos testes vale só o que o teste pôs na pasta temporária. O `PATH` do
/// filho herda o do processo, e sem esta guarda o catálogo achava o `claude`
/// de verdade da máquina (centenas de MB) e o lia inteiro em cada teste.
pub fn fake_executable(path: &Path) -> bool {
    let temp = std::env::temp_dir();
    let inside = |p: &Path| {
        p.starts_with(&temp)
            || temp
                .canonicalize()
                .is_ok_and(|t| p.canonicalize().is_ok_and(|c| c.starts_with(t)))
    };
    inside(path) && path.is_file()
}

/// O TCC de brinquedo: guarda os serviços zerados, e o painel é uma URL
/// qualquer (o `FakeOpener` não abre nada na tela).
#[derive(Default)]
pub struct FakeFolders {
    pub resets: Mutex<Vec<String>>,
}

impl crate::ports::folder_access::FolderPermissions for FakeFolders {
    fn reset(&self, service: &str) -> bool {
        if let Ok(mut resets) = self.resets.lock() {
            resets.push(service.to_owned());
        }
        true
    }

    fn settings_url(&self) -> Option<String> {
        Some("x-apple.systempreferences:privacidade".to_owned())
    }
}
