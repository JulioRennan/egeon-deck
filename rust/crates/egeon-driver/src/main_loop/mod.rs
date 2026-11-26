//! O run loop da thread principal.
//!
//! Várias APIs do sistema só funcionam com o run loop principal girando: a
//! central de notificações entrega o clique por ele, e o `NSWorkspace` só
//! atualiza a lista de apps quando ele gira. O executável do core roda o
//! runtime tokio numa thread própria e entrega a principal a este módulo,
//! como o app Swift fazia.

use std::thread;

use thiserror::Error;

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
use macos as platform;
#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "linux")]
use linux as platform;
#[cfg(windows)]
mod windows;
#[cfg(windows)]
use windows as platform;

#[derive(Debug, Error)]
pub enum MainLoopError {
    /// O run loop principal só gira na thread principal do processo.
    #[error("o run loop principal só gira na thread principal")]
    NotMainThread,
    #[error("o sistema não tem run loop principal")]
    NoRunLoop,
    #[error("não consegui criar a thread do core: {0}")]
    SpawnFailed(std::io::Error),
    #[error("a thread do core terminou em pânico")]
    CorePanicked,
}

/// Roda `core` numa thread nova e gira o run loop principal até ele voltar;
/// devolve o que `core` devolveu. Chamar da thread principal, antes de qualquer
/// outra coisa que a use.
pub fn run<T: Send + 'static>(
    core: impl FnOnce() -> T + Send + 'static,
) -> Result<T, MainLoopError> {
    if !platform::is_main_thread() {
        return Err(MainLoopError::NotMainThread);
    }
    let spinner = platform::Spinner::new().ok_or(MainLoopError::NoRunLoop)?;
    let stopper = spinner.stopper();
    let worker = thread::Builder::new()
        .name("core".into())
        .spawn(move || {
            // No `Drop`, e não depois de `core()`: um pânico em `core` também
            // tem de soltar a thread principal.
            let _stop_on_exit = StopOnDrop(stopper);
            core()
        })
        .map_err(MainLoopError::SpawnFailed)?;
    spinner.spin();
    worker.join().map_err(|_| MainLoopError::CorePanicked)
}

struct StopOnDrop(platform::Stopper);

impl Drop for StopOnDrop {
    fn drop(&mut self) {
        self.0.stop();
    }
}

/// Despacha `job` para a thread principal. Só roda enquanto [`run`] gira.
pub fn on_main(job: impl FnOnce() + Send + 'static) {
    platform::on_main(job);
}
