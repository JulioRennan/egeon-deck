//! `egeon`: o comando dos agentes e os ganchos dos CLIs.
//!
//! Só fala o protocolo do socket; não conhece o resto do app.

#![forbid(unsafe_code)]

use std::ffi::OsString;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::ExitCode;

use egeon_cli::commands::{self, Streams};
use egeon_cli::hook::{self, PERMISSION_WAIT, Setup, SystemClock};
use egeon_core::commons::paths;

/// O socket do app: a cópia (estável ou dev) e a pasta de dados vêm do
/// ambiente do terminal, como no `egeon-app` que o lançou.
fn socket() -> Result<PathBuf, paths::PathsError> {
    let var = |name: &str| std::env::var(name).ok();
    let flavor =
        paths::Flavor::from_env_in_build(var("EGEON_FLAVOR").as_deref(), !cfg!(debug_assertions));
    paths::egeon_home(flavor, var("EGEON_HOME").as_deref(), var(HOME).as_deref())
        .map(|home| paths::Paths::new(home).socket())
}

/// A pasta do usuário, a mesma que o `egeon-app` usa: no Windows o
/// `%USERPROFILE%`, e não o `HOME` que o Git Bash define.
#[cfg(not(windows))]
const HOME: &str = "HOME";
#[cfg(windows)]
const HOME: &str = "USERPROFILE";

/// O argumento como os bytes que o agente digitou. No Windows o sistema
/// entrega UTF-16: vira UTF-8, que é o que o protocolo leva.
#[cfg(unix)]
fn arg_bytes(arg: OsString) -> Vec<u8> {
    std::os::unix::ffi::OsStringExt::into_vec(arg)
}

#[cfg(not(unix))]
fn arg_bytes(arg: OsString) -> Vec<u8> {
    arg.to_string_lossy().into_owned().into_bytes()
}

fn main() -> ExitCode {
    let args: Vec<Vec<u8>> = std::env::args_os().skip(1).map(arg_bytes).collect();
    let mut stdin = std::io::stdin().lock();

    if args.first().map(Vec::as_slice) == Some(b"hook".as_slice()) {
        // Drenado mesmo quando não é lido: stdin fechado sem leitura devolve
        // SIGPIPE para quem escreveu.
        let mut payload = Vec::new();
        let _ = stdin.read_to_end(&mut payload);
        let in_egeon = std::env::var_os("EGEON_TARGET").is_some_and(|v| !v.is_empty());
        if let Ok(sock) = socket() {
            let setup = Setup {
                sock: &sock,
                in_egeon,
                clock: &SystemClock,
                permission_wait: PERMISSION_WAIT,
            };
            let event = args.get(1).map(Vec::as_slice).unwrap_or_default();
            let mut out = std::io::stdout().lock();
            hook::run(event, &payload, &setup, &mut out);
            let _ = out.flush();
        }
        // Sempre 0: exit 2 apagaria o prompt do usuário.
        return ExitCode::SUCCESS;
    }

    let mut out = std::io::stdout().lock();
    let mut err = std::io::stderr().lock();
    let code = match socket() {
        Ok(sock) => commands::run(
            &args,
            &sock,
            &mut Streams {
                stdin: &mut stdin,
                out: &mut out,
                err: &mut err,
            },
        ),
        Err(e) => {
            let _ = writeln!(err, "egeon: {e}");
            1
        }
    };
    let _ = out.flush();
    ExitCode::from(u8::try_from(code).unwrap_or(1))
}
