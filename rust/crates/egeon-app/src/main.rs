//! Montagem: o executável do core.
//!
//! Cria o driver da plataforma e o terminal e os entrega ao core. A UI o
//! lança ao abrir; sozinho, roda sem janela.
//!
//! `--exit-with-stdin`: encerra quando o stdin fecha (decisão 21). A UI lança
//! o core com o stdin num cano dela e nunca escreve nele; quando ela sai —
//! ⌘Q, queda ou `kill -9` — o cano fecha e o core encerra os terminais, como
//! no SIGTERM. A opção é só para quem segura o cano: com o stdin em
//! `/dev/null` (launchd, `nohup`) o app sai no ato.

#![forbid(unsafe_code)]
// Com a UI morta por kill -9, stdout e stderr são canos quebrados: `eprintln!`
// entraria em pânico e o encerramento ordenado não rodaria.
#![deny(clippy::print_stdout, clippy::print_stderr)]

use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::Arc;

use tokio::sync::oneshot;

use egeon_core::commons::paths::{Flavor, Paths, egeon_home};
use egeon_core::log;
use egeon_core::runtime::{Config, Drivers, serve};

const USAGE: &str = "uso: egeon-app [--exit-with-stdin]";

/// A thread principal gira o run loop do sistema, como o app Swift: é dela
/// que dependem a notificação e o som. O core roda noutra thread, e quando
/// ele volta o loop para.
fn main() -> ExitCode {
    match egeon_driver::main_loop::run(real_main) {
        Ok(code) => code,
        Err(err) => {
            log!("egeon-app: {err}");
            ExitCode::FAILURE
        }
    }
}

fn real_main() -> ExitCode {
    let mut exit_with_stdin = false;
    for arg in std::env::args().skip(1) {
        match arg.as_str() {
            "--exit-with-stdin" => exit_with_stdin = true,
            "-h" | "--help" => {
                let _ = writeln!(std::io::stdout().lock(), "{USAGE}");
                return ExitCode::SUCCESS;
            }
            other => {
                log!("egeon-app: opção desconhecida {other:?}\n{USAGE}");
                return ExitCode::from(2);
            }
        }
    }
    let env = |name: &str| std::env::var(name).ok();
    let flavor = Flavor::from_env_in_build(env("EGEON_FLAVOR").as_deref(), !cfg!(debug_assertions));
    let home = match egeon_home(flavor, env("EGEON_HOME").as_deref(), env("HOME").as_deref()) {
        Ok(home) => home,
        Err(err) => {
            log!("egeon-app: {err}");
            return ExitCode::FAILURE;
        }
    };
    // Antes de tudo: o app aberto pelo Finder não tem stderr para ler.
    let paths = Paths::new(home);
    egeon_core::commons::log::to_file(paths.log_file());
    let config = Config {
        paths,
        flavor,
        // O `egeon` sai do mesmo build e mora ao lado do `egeon-app`.
        cli_binary: std::env::current_exe()
            .ok()
            .and_then(|exe| Some(exe.parent()?.join("egeon")))
            .filter(|cli| cli.exists()),
        ui_parent: exit_with_stdin,
        default_cwd: env("HOME").map_or_else(|| PathBuf::from("/"), PathBuf::from),
        version: env!("CARGO_PKG_VERSION").to_owned(),
        build: option_env!("EGEON_BUILD").unwrap_or_default().to_owned(),
    };
    let drivers = Drivers {
        pty: Arc::new(egeon_driver::SystemPty),
        screens: Arc::new(egeon_terminal::GhosttyScreens),
        local: Arc::new(egeon_driver::SystemLocalConn),
        procs: Arc::new(egeon_driver::SystemProcs),
        notifier: Arc::new(egeon_driver::SystemNotifier::new()),
        apps: Arc::new(egeon_driver::SystemApps),
        installer: Arc::new(egeon_driver::SystemInstaller),
        opener: Arc::new(egeon_driver::SystemOpener),
        cloner: Arc::new(egeon_driver::SystemFileCloner),
        links: Arc::new(egeon_driver::SystemLinks),
        is_executable: egeon_driver::is_executable,
        folders: Arc::new(egeon_driver::SystemFolderPermissions),
    };

    let runtime = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(err) => {
            log!("egeon-app: sem runtime: {err}");
            return ExitCode::FAILURE;
        }
    };
    // Os sinais são registrados na chamada a `shutdown()`, e ela tem de rodar
    // dentro do runtime: criado antes do `serve`, um SIGTERM que chegue durante
    // a partida não se perde.
    let outcome = runtime.block_on(async {
        let signal = egeon_driver::signals::shutdown();
        let stdin = exit_with_stdin.then(stdin_closed);
        let stop = async move {
            match stdin {
                Some(closed) => {
                    tokio::select! {
                        () = signal => {}
                        _ = closed => log!("egeon-app: stdin fechou; encerrando"),
                    }
                }
                None => signal.await,
            }
        };
        serve(config, drivers, stop).await
    });
    match outcome {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            log!("egeon-app: {err}");
            ExitCode::FAILURE
        }
    }
}

/// Resolve quando o stdin chega ao fim.
///
/// Numa thread comum, e não no `tokio::io::stdin`: aquele lê numa thread de
/// bloqueio do runtime, e o runtime espera essas threads ao sair — encerrado
/// por sinal com o stdin ainda aberto, o processo ficaria preso no `read`.
fn stdin_closed() -> oneshot::Receiver<()> {
    let (tx, rx) = oneshot::channel();
    std::thread::spawn(move || {
        let mut stdin = std::io::stdin().lock();
        let mut buf = [0u8; 4096];
        loop {
            match stdin.read(&mut buf) {
                Ok(0) => break,
                Ok(_) => {}
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                Err(_) => break,
            }
        }
        let _ = tx.send(());
    });
    rx
}
