//! O Windows não tem SIGTERM: os pedidos de encerramento são os eventos do
//! console. A UI encerra o core fechando o stdin (decisão 21), não por aqui.

use std::future::Future;
use std::io;

use tokio::runtime::Handle;
use tokio::signal::windows::{
    CtrlBreak, CtrlC, CtrlClose, CtrlShutdown, ctrl_break, ctrl_c, ctrl_close, ctrl_shutdown,
};

type Registered = (
    io::Result<CtrlC>,
    io::Result<CtrlBreak>,
    io::Result<CtrlClose>,
    io::Result<CtrlShutdown>,
);

fn register() -> Registered {
    (ctrl_c(), ctrl_break(), ctrl_close(), ctrl_shutdown())
}

pub(super) fn shutdown() -> impl Future<Output = ()> + Send {
    // Como no unix: registra já na chamada quando há runtime, para o evento
    // que chega antes do primeiro `poll` não se perder.
    let early = Handle::try_current().ok().map(|_| register());
    async move {
        let (Ok(mut c), Ok(mut brk), Ok(mut close), Ok(mut down)) = early.unwrap_or_else(register)
        else {
            let _ = tokio::signal::ctrl_c().await;
            return;
        };
        // Ctrl-C (o do terminal de quem lançou), Ctrl-Break, o console de
        // quem lançou fechado (o SIGHUP) e o desligamento do sistema.
        tokio::select! {
            _ = c.recv() => {}
            _ = brk.recv() => {}
            _ = close.recv() => {}
            _ = down.recv() => {}
        }
    }
}
