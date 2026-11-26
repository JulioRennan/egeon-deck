//! Interface do pty: abrir um processo atrás de um terminal virtual, ler o que
//! ele escreve, escrever o que ele lê, redimensionar e sinalizar.
//!
//! Implementada por `egeon-driver`. Nada aqui assume o sistema: o formato é o do
//! que o runtime precisa.
//!
//! O runtime não espera em nada que venha do pty. A saída chega por um canal
//! limitado ([`PtyChild::events`]), e `write`, `resize` e `signal` voltam na
//! hora, sem bloquear o ator.

use std::path::{Path, PathBuf};

use thiserror::Error;
use tokio::sync::mpsc;

/// Tamanho do terminal em células.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PtySize {
    pub cols: u16,
    pub rows: u16,
}

/// O que lançar. O ambiente é o completo do filho: o driver não herda nada do
/// processo atual por conta própria (veja `features::terminal::environment`).
#[derive(Debug, Clone)]
pub struct PtySpec {
    pub program: PathBuf,
    pub args: Vec<String>,
    pub env: Vec<(String, String)>,
    pub cwd: Option<PathBuf>,
    pub size: PtySize,
}

/// Como o filho terminou.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PtyExit {
    /// Saiu sozinho, com este código.
    Code(i32),
    /// Foi morto por este sinal.
    Signal(i32),
}

/// O que sai do canal de eventos de um filho.
#[derive(Debug)]
pub enum PtyEvent {
    /// Bytes que o filho escreveu no terminal, na ordem em que saíram.
    Output(Vec<u8>),
    /// O filho acabou. Sempre o último evento, depois de toda a saída do filho;
    /// o canal fecha em seguida. Saída de um neto que ainda segura o terminal
    /// depois disso não é garantida.
    Exited(PtyExit),
}

/// Sinais que o app manda a um terminal.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PtySignal {
    Hangup,
    Interrupt,
    Terminate,
    Kill,
}

#[derive(Debug, Error)]
pub enum PtyError {
    #[error("não foi possível abrir o pty: {0}")]
    Open(String),
    #[error("não foi possível lançar {program}: {reason}")]
    Spawn { program: String, reason: String },
    #[error("o processo já terminou")]
    Gone,
    #[error("fila de escrita cheia: o processo não está lendo")]
    WriteQueueFull,
    #[error("falha de sistema: {0}")]
    Io(String),
}

/// Um processo vivo atrás de um pty.
///
/// Largar o valor fecha o terminal (o filho recebe SIGHUP), mas não é uma morte
/// garantida: um filho que ignora o sinal continua vivo. Para matar, use
/// [`PtySession::signal`] antes.
pub trait PtySession: Send + Sync {
    /// Pid do filho, que é também o líder do grupo e da sessão dele.
    fn pid(&self) -> u32;

    /// Enfileira a entrada para o filho e volta; a escrita de fato acontece
    /// fora do chamador. Quem lê devagar enche a fila e recebe
    /// [`PtyError::WriteQueueFull`], em vez de travar o runtime.
    fn write(&self, data: &[u8]) -> Result<(), PtyError>;

    fn resize(&self, size: PtySize) -> Result<(), PtyError>;

    /// Manda o sinal ao **grupo** do filho — o que ele abriu dentro (agente,
    /// `npm`, `sleep`) morre junto, que é o que "remover o terminal" promete.
    /// Se o filho não for líder do próprio grupo, o sinal vai só a ele: o grupo
    /// poderia ser o do app. [`PtyError::Gone`] se o filho já foi colhido.
    fn signal(&self, signal: PtySignal) -> Result<(), PtyError>;

    /// A pasta do processo da frente do terminal agora — o shell, ou o
    /// programa que ele deixou em primeiro plano. É contra ela que um caminho
    /// relativo impresso na tela vale: no shell o usuário pode ter dado `cd`, e
    /// a pasta em que o nó abriu já não diz nada. `None` se o terminal acabou
    /// ou o sistema não deixa ler.
    fn foreground_dir(&self) -> Option<PathBuf> {
        None
    }
}

/// Um filho lançado: o controle e o canal de eventos.
pub struct PtyChild {
    pub session: Box<dyn PtySession>,
    pub events: mpsc::Receiver<PtyEvent>,
}

/// Abre processos atrás de um pty.
pub trait PtyDriver: Send + Sync {
    /// Lança o processo. Pode ser chamado de qualquer thread.
    fn spawn(&self, spec: PtySpec) -> Result<PtyChild, PtyError>;

    /// Diretórios onde este sistema costuma ter binários que o `PATH` de um app
    /// aberto pelo Finder não traz (no macOS, Homebrew, `~/.cargo/bin`…), na
    /// ordem em que entram na frente do `PATH`. Quais existem e a composição do
    /// ambiente são do core (`features::terminal::environment`).
    fn path_dirs(&self, home: &Path) -> Vec<PathBuf>;
    /// O shell em que os terminais sobem (decisão 53): o `/bin/zsh` no macOS,
    /// o do usuário no Linux. Como cada um é chamado é do core
    /// (`features::terminal::shell`).
    fn user_shell(&self) -> PathBuf;
}
