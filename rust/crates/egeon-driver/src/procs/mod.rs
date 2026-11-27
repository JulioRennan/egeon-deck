//! Tabela de processos e sinais: implementa `ports::procs::ProcessDriver`.

use std::collections::HashMap;
#[cfg(unix)]
use std::io;

use egeon_core::ports::procs::{
    ProcessDetail, ProcessDriver, ProcessError, ProcessSignal, RawProcess,
};

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
#[cfg(windows)]
use windows::send;

/// A pasta atual de um processo, para quem já tem o pid (o terminal).
pub(crate) fn cwd_of(pid: u32) -> Option<std::path::PathBuf> {
    platform::cwd_of(pid)
}

/// Pid, pai e nome de cada processo do usuário, para quem já está no driver
/// (o Job do terminal no Windows). Vazio se a tabela não abre.
#[cfg(windows)]
pub(crate) fn tree() -> Vec<RawProcess> {
    platform::list(ProcessDetail::Tree).unwrap_or_default()
}

/// O driver de processos do sistema em que o programa roda.
#[derive(Debug, Clone, Copy, Default)]
pub struct SystemProcs;

impl ProcessDriver for SystemProcs {
    fn list(&self, detail: ProcessDetail) -> Result<Vec<RawProcess>, ProcessError> {
        platform::list(detail)
    }

    fn environment_of(&self, pid: u32) -> Option<HashMap<String, String>> {
        platform::arguments_of(pid).map(|arguments| arguments.environment)
    }

    fn parent_of(&self, pid: u32) -> Option<u32> {
        platform::parent_of(pid)
    }

    fn signal(&self, pid: u32, signal: ProcessSignal) -> Result<(), ProcessError> {
        send(pid, signal)
    }
}

#[cfg(unix)]
/// `kill(0)` e `kill(-1)` atingiriam o grupo do chamador ou o sistema todo, e o
/// pid 1 é o `launchd`: nada disso passa por um pid vindo da tabela.
fn send(pid: u32, signal: ProcessSignal) -> Result<(), ProcessError> {
    let raw = match i32::try_from(pid) {
        Ok(raw) if raw > 1 => raw,
        _ => {
            return Err(ProcessError::Signal {
                pid,
                source: io::Error::from(io::ErrorKind::InvalidInput),
            });
        }
    };
    let number = match signal {
        ProcessSignal::Terminate => libc::SIGTERM,
        ProcessSignal::Kill => libc::SIGKILL,
    };
    // SAFETY: `kill` só lê os dois inteiros e não toca memória do processo.
    if unsafe { libc::kill(raw, number) } == 0 {
        return Ok(());
    }
    let source = io::Error::last_os_error();
    if source.raw_os_error() == Some(libc::ESRCH) {
        Err(ProcessError::Gone(pid))
    } else {
        Err(ProcessError::Signal { pid, source })
    }
}
