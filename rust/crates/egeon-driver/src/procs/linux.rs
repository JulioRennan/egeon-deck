//! A tabela de processos pelo `/proc`.

use std::collections::HashMap;
use std::fs;
use std::io;
use std::path::PathBuf;
use std::sync::OnceLock;
use std::time::{Duration, SystemTime};

use egeon_core::ports::procs::{ProcessDetail, ProcessError, RawProcess};

#[derive(Debug, Default, PartialEq, Eq)]
pub(super) struct Arguments {
    pub arguments: Vec<String>,
    pub environment: HashMap<String, String>,
}

/// O que o `/proc/<pid>/stat` diz de um processo.
#[derive(Debug, PartialEq, Eq)]
struct Stat {
    name: String,
    ppid: u32,
    /// Em tiques do relógio desde o boot.
    start_ticks: u64,
}

pub(super) fn list(detail: ProcessDetail) -> Result<Vec<RawProcess>, ProcessError> {
    // SAFETY: `geteuid` não tem pré-condição e nunca falha.
    let uid = unsafe { libc::geteuid() };
    let boot = boot_time().map_err(ProcessError::Table)?;
    let ticks = ticks_per_second();
    let entries = fs::read_dir("/proc").map_err(ProcessError::Table)?;
    Ok(entries
        .filter_map(Result::ok)
        .filter_map(|entry| entry.file_name().to_str()?.parse::<u32>().ok())
        .filter_map(|pid| {
            // Processo que acabou entre a listagem e a leitura some da lista,
            // como no `sysctl` do macOS.
            if effective_uid(pid)? != uid {
                return None;
            }
            let stat = stat(pid)?;
            let arguments = match detail {
                ProcessDetail::Full => arguments_of(pid),
                ProcessDetail::Tree => None,
            };
            let command = arguments
                .as_ref()
                .map(|a| a.arguments.join(" "))
                .filter(|command| !command.is_empty())
                .unwrap_or_else(|| stat.name.clone());
            Some(RawProcess {
                pid,
                ppid: stat.ppid,
                started: started(boot, stat.start_ticks, ticks),
                name: stat.name,
                command,
                environment: arguments.map(|a| a.environment).unwrap_or_default(),
            })
        })
        .collect())
}

pub(super) fn cwd_of(pid: u32) -> Option<PathBuf> {
    fs::read_link(format!("/proc/{pid}/cwd")).ok()
}

pub(super) fn parent_of(pid: u32) -> Option<u32> {
    stat(pid).map(|stat| stat.ppid)
}

/// Linha de comando e ambiente. O `environ` é o ambiente de quando o processo
/// fez `exec`, como o `KERN_PROCARGS2` do macOS; o kernel só deixa ler o dos
/// processos do próprio usuário.
pub(super) fn arguments_of(pid: u32) -> Option<Arguments> {
    let cmdline = fs::read(format!("/proc/{pid}/cmdline")).ok()?;
    let environ = fs::read(format!("/proc/{pid}/environ")).unwrap_or_default();
    Some(Arguments {
        arguments: nul_separated(&cmdline).map(lossy).collect(),
        environment: parse_environ(&environ),
    })
}

fn nul_separated(data: &[u8]) -> impl Iterator<Item = &[u8]> {
    data.split(|&b| b == 0).filter(|part| !part.is_empty())
}

fn lossy(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

fn parse_environ(data: &[u8]) -> HashMap<String, String> {
    nul_separated(data)
        .filter_map(|entry| {
            let entry = lossy(entry);
            let (key, value) = entry.split_once('=')?;
            Some((key.to_string(), value.to_string()))
        })
        .collect()
}

fn stat(pid: u32) -> Option<Stat> {
    parse_stat(&fs::read(format!("/proc/{pid}/stat")).ok()?)
}

/// `pid (nome) estado ppid … início …`. O nome pode ter espaço e parêntese:
/// ele vai até o último `)` da linha.
fn parse_stat(data: &[u8]) -> Option<Stat> {
    let open = data.iter().position(|&b| b == b'(')?;
    let close = data.iter().rposition(|&b| b == b')')?;
    let name = lossy(data.get(open + 1..close)?);
    let rest = String::from_utf8_lossy(data.get(close + 1..)?).into_owned();
    // Depois do nome: estado é o campo 3 de `proc(5)`, ppid o 4 e o início o 22.
    let fields: Vec<&str> = rest.split_whitespace().collect();
    Some(Stat {
        name,
        ppid: fields.get(1)?.parse().ok()?,
        start_ticks: fields.get(19)?.parse().ok()?,
    })
}

/// O uid efetivo, o segundo número da linha `Uid:` do `status` — o mesmo que
/// o `pbi_uid` do macOS compara.
fn effective_uid(pid: u32) -> Option<u32> {
    let status = fs::read_to_string(format!("/proc/{pid}/status")).ok()?;
    parse_effective_uid(&status)
}

fn parse_effective_uid(status: &str) -> Option<u32> {
    status
        .lines()
        .find_map(|line| line.strip_prefix("Uid:"))?
        .split_whitespace()
        .nth(1)?
        .parse()
        .ok()
}

/// A hora do boot (`btime` do `/proc/stat`), em segundos: o início de cada
/// processo é contado a partir dela.
fn boot_time() -> io::Result<SystemTime> {
    let stat = fs::read_to_string("/proc/stat")?;
    parse_boot_time(&stat).ok_or_else(|| io::Error::other("/proc/stat sem btime"))
}

fn parse_boot_time(stat: &str) -> Option<SystemTime> {
    let seconds: u64 = stat
        .lines()
        .find_map(|line| line.strip_prefix("btime "))?
        .trim()
        .parse()
        .ok()?;
    Some(SystemTime::UNIX_EPOCH + Duration::from_secs(seconds))
}

fn ticks_per_second() -> u64 {
    static TICKS: OnceLock<u64> = OnceLock::new();
    *TICKS.get_or_init(|| {
        // SAFETY: `sysconf` só lê a configuração do sistema.
        let ticks = unsafe { libc::sysconf(libc::_SC_CLK_TCK) };
        // 100 é o valor do kernel em toda arquitetura que o Egeon roda.
        u64::try_from(ticks).ok().filter(|&t| t > 0).unwrap_or(100)
    })
}

/// O mesmo processo dá sempre o mesmo instante: é o que, com o pid, o
/// identifica.
fn started(boot: SystemTime, start_ticks: u64, ticks: u64) -> SystemTime {
    let whole = start_ticks / ticks;
    let nanos = (start_ticks % ticks) * 1_000_000_000 / ticks;
    boot + Duration::from_secs(whole) + Duration::from_nanos(nanos)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stat_com_espaco_e_parentese_no_nome() {
        let line = b"4242 (meu (app) x) S 17 4242 4242 34816 4242 4194560 1180 0 0 0 2 1 0 0 20 0 1 0 987654 9000000 300 18446744073709551615 1 1 0 0 0 0 0 0 0 0 0 0 17 3 0 0 0 0 0\n";
        assert_eq!(
            parse_stat(line),
            Some(Stat {
                name: "meu (app) x".into(),
                ppid: 17,
                start_ticks: 987654,
            })
        );
        assert_eq!(parse_stat(b"4242 (curto) S"), None);
    }

    #[test]
    fn uid_efetivo_e_o_segundo_da_linha() {
        let status = "Name:\tzsh\nUid:\t1000\t501\t1000\t1000\nGid:\t1000\t1000\t1000\t1000\n";
        assert_eq!(parse_effective_uid(status), Some(501));
        assert_eq!(parse_effective_uid("Name:\tx\n"), None);
    }

    #[test]
    fn inicio_conta_do_boot_em_tiques() {
        let boot = parse_boot_time("cpu  1 2 3\nbtime 1700000000\nprocesses 9\n");
        assert_eq!(
            boot,
            Some(SystemTime::UNIX_EPOCH + Duration::from_secs(1_700_000_000))
        );
        let boot = SystemTime::UNIX_EPOCH;
        assert_eq!(
            started(boot, 12_345, 100),
            boot + Duration::from_millis(123_450)
        );
    }

    #[test]
    fn ambiente_separa_chave_do_valor_no_primeiro_igual() {
        let env = parse_environ(b"EGEON_NODE=a/b\0X=1=2\0sem-igual\0\0");
        assert_eq!(env.get("EGEON_NODE").map(String::as_str), Some("a/b"));
        assert_eq!(env.get("X").map(String::as_str), Some("1=2"));
        assert_eq!(env.len(), 2);
    }

    #[test]
    fn le_o_proprio_processo() {
        let me = std::process::id();
        let all = list(ProcessDetail::Full).unwrap_or_default();
        let mine = all.iter().find(|p| p.pid == me);
        assert!(mine.is_some_and(|p| !p.command.is_empty() && !p.environment.is_empty()));
        assert_eq!(parent_of(me), Some(std::os::unix::process::parent_id()));
        assert!(cwd_of(me).is_some_and(|cwd| cwd == std::env::current_dir().unwrap_or_default()));
        // O início é estável entre duas leituras: é parte da identidade.
        let again = list(ProcessDetail::Tree).unwrap_or_default();
        let started = |list: &[RawProcess]| list.iter().find(|p| p.pid == me).map(|p| p.started);
        assert_eq!(started(&all), started(&again));
    }
}
