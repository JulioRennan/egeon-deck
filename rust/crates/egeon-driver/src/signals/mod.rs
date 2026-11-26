//! Pedido de encerramento do processo, vindo do sistema.

use std::future::Future;

#[cfg(unix)]
mod unix;
#[cfg(unix)]
use unix as platform;
#[cfg(windows)]
mod windows;
#[cfg(windows)]
use windows as platform;

/// Resolve no primeiro pedido de encerramento: SIGTERM (o da UI ao fechar o
/// core), SIGINT (Ctrl-C) ou SIGHUP (o terminal de quem lançou fechou). No
/// Windows, os eventos do console equivalentes (veja `windows.rs`).
///
/// Dentro do runtime tokio os sinais são registrados já na chamada, e não no
/// primeiro `poll`: um sinal que chega entre criar o futuro e esperá-lo não se
/// perde. Chamada fora do runtime, não entra em pânico: o registro fica para o
/// primeiro `poll`.
pub fn shutdown() -> impl Future<Output = ()> + Send {
    platform::shutdown()
}
