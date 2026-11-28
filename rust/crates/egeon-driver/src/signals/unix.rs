use std::future::Future;
use std::io;

use tokio::runtime::Handle;
use tokio::signal::unix::{Signal, SignalKind, signal};

type Registered = (io::Result<Signal>, io::Result<Signal>, io::Result<Signal>);

fn register() -> Registered {
    (
        signal(SignalKind::terminate()),
        signal(SignalKind::interrupt()),
        signal(SignalKind::hangup()),
    )
}

pub(super) fn shutdown() -> impl Future<Output = ()> + Send {
    // `signal` entra em pânico sem runtime; fora dele o registro espera o
    // primeiro `poll`, que acontece dentro de um.
    let early = Handle::try_current().ok().map(|_| register());
    async move {
        let (Ok(mut term), Ok(mut int), Ok(mut hup)) = early.unwrap_or_else(register) else {
            // Sem registrar não há como ouvir; espera ao menos o Ctrl-C em vez de
            // encerrar o app por um erro de configuração.
            let _ = tokio::signal::ctrl_c().await;
            return;
        };
        tokio::select! {
            _ = term.recv() => {}
            _ = int.recv() => {}
            _ = hup.recv() => {}
        }
    }
}
