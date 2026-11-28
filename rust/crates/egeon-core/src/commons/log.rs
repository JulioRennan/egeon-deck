//! O log do core: uma linha no stderr e, com `to_file`, no `egeon.log` da
//! pasta de dados (decisão 38) — o app aberto pelo Finder perde o stderr.
//!
//! Nunca entra em pânico. `eprintln!` entra quando o stderr é um cano
//! quebrado — a UI que lançou o core morreu com `kill -9` — e levaria junto a
//! tarefa que escrevia (o ator, ou o encerramento que manda HUP e KILL aos
//! terminais). Linha que não dá para escrever se perde.

use std::fmt;
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::sync::mpsc::{Receiver, SyncSender, sync_channel};

/// O arquivo do log, na pasta de dados.
pub const FILE: &str = "egeon.log";

/// Passou disto, o arquivo vira `egeon.log.1` e recomeça.
pub const MAX_BYTES: u64 = 5 * 1024 * 1024;

/// Linhas que esperam o escritor; cheia, a linha nova se perde em vez de
/// segurar quem escreve (o ator).
const BACKLOG: usize = 1024;

static SINK: OnceLock<SyncSender<String>> = OnceLock::new();

pub fn write(args: fmt::Arguments<'_>) {
    let _ = writeln!(std::io::stderr().lock(), "{args}");
    if let Some(sink) = SINK.get() {
        let _ = sink.try_send(format!("{} {args}\n", hour()));
    }
}

/// Liga o arquivo, uma vez por processo. O log da sessão anterior vira
/// `egeon.log.1`, como o `Log.reset` do Swift zera o dele ao abrir. A
/// gravação é de uma thread própria: o disco não segura quem loga.
pub fn to_file(path: PathBuf) {
    let (tx, rx) = sync_channel(BACKLOG);
    if SINK.set(tx).is_err() {
        return;
    }
    let spawned = std::thread::Builder::new()
        .name("egeon-log".into())
        .spawn(move || writer(&path, &rx, MAX_BYTES));
    if let Err(error) = spawned {
        let _ = writeln!(std::io::stderr().lock(), "log: sem arquivo, {error}");
    }
}

/// `HH:MM:SS` na hora local, como as linhas do log do Swift.
fn hour() -> String {
    jiff::Zoned::now().strftime("%H:%M:%S").to_string()
}

fn rotated(path: &Path) -> PathBuf {
    let mut name = path.as_os_str().to_owned();
    name.push(".1");
    PathBuf::from(name)
}

fn reopen(path: &Path, fresh: bool) -> Option<File> {
    if fresh && path.exists() {
        let _ = std::fs::rename(path, rotated(path));
    }
    OpenOptions::new().create(true).append(true).open(path).ok()
}

fn writer(path: &Path, lines: &Receiver<String>, max: u64) {
    let mut file = reopen(path, true);
    for line in lines {
        let Some(out) = file.as_mut() else {
            file = reopen(path, false);
            continue;
        };
        if out.write_all(line.as_bytes()).is_err() {
            file = None;
            continue;
        }
        if out.metadata().is_ok_and(|m| m.len() > max) {
            file = reopen(path, true);
        }
    }
}

/// `log!("terminal[{id}]: …")`: como `eprintln!`, sem o pânico.
#[macro_export]
macro_rules! log {
    ($($arg:tt)*) => {
        $crate::commons::log::write(format_args!($($arg)*))
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn grava_e_gira_quando_passa_do_limite() {
        let dir = std::env::temp_dir().join(format!("egeon-log-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join(FILE);
        std::fs::write(&path, "sessão anterior\n").unwrap();
        let (tx, rx) = sync_channel(8);
        for line in ["um\n", "dois\n", "três\n"] {
            tx.send(line.to_owned()).unwrap();
        }
        drop(tx);
        writer(&path, &rx, 6);
        // A sessão anterior foi para o .1 ao abrir; "um" e "dois" passaram
        // de 6 bytes e giraram também; "três" ficou no arquivo novo.
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "três\n");
        assert_eq!(
            std::fs::read_to_string(rotated(&path)).unwrap(),
            "um\ndois\n"
        );
        let _ = std::fs::remove_dir_all(&dir);
    }
}
