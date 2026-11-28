//! A tabela de processos no macOS: `libproc` para a lista e `KERN_PROCARGS2`
//! para a linha de comando e o ambiente — direto do kernel, e não um `ps -E`
//! por processo, que seriam centenas de subprocessos a cada leitura.

use std::collections::HashMap;
use std::io;
use std::mem;
use std::path::PathBuf;
use std::ptr;
use std::time::{Duration, SystemTime};

use egeon_core::ports::procs::{ProcessDetail, ProcessError, RawProcess};

/// A linha de comando e o ambiente de um processo.
#[derive(Debug, Default, PartialEq, Eq)]
pub(super) struct Arguments {
    pub arguments: Vec<String>,
    pub environment: HashMap<String, String>,
}

pub(super) fn list(detail: ProcessDetail) -> Result<Vec<RawProcess>, ProcessError> {
    // SAFETY: `geteuid` não tem pré-condição.
    let uid = unsafe { libc::geteuid() };
    let pids = pids().map_err(ProcessError::Table)?;
    Ok(pids
        .into_iter()
        .filter_map(|pid| {
            let info = bsd_info(pid)?;
            // Só os do usuário, como o `KERN_PROC_UID` do Swift.
            if info.pbi_uid != uid {
                return None;
            }
            let name = c_string(&info.pbi_comm);
            let arguments = match detail {
                ProcessDetail::Full => arguments_of(pid),
                ProcessDetail::Tree => None,
            };
            let command = arguments
                .as_ref()
                .map(|a| a.arguments.join(" "))
                .filter(|command| !command.is_empty())
                .unwrap_or_else(|| name.clone());
            Some(RawProcess {
                pid,
                ppid: info.pbi_ppid,
                started: SystemTime::UNIX_EPOCH
                    + Duration::new(info.pbi_start_tvsec, (info.pbi_start_tvusec * 1000) as u32),
                name,
                command,
                environment: arguments.map(|a| a.environment).unwrap_or_default(),
            })
        })
        .collect())
}

/// A pasta atual de um processo (`PROC_PIDVNODEPATHINFO`); `None` se ele sumiu
/// ou o caminho vem vazio.
pub(super) fn cwd_of(pid: u32) -> Option<PathBuf> {
    let pid = i32::try_from(pid).ok()?;
    // SAFETY: `proc_vnodepathinfo` é só inteiros e bytes; zerada é válida.
    let mut info: libc::proc_vnodepathinfo = unsafe { mem::zeroed() };
    let size = mem::size_of::<libc::proc_vnodepathinfo>() as i32;
    // SAFETY: `info` tem `size` bytes graváveis.
    let read = unsafe {
        libc::proc_pidinfo(
            pid,
            libc::PROC_PIDVNODEPATHINFO,
            0,
            (&raw mut info).cast(),
            size,
        )
    };
    if read != size {
        return None;
    }
    // O caminho é um vetor de `MAXPATHLEN` bytes que o `libc` declara como
    // matriz de 32 por 32.
    let raw = info.pvi_cdir.vip_path.as_flattened();
    let path = c_string(raw);
    (!path.is_empty()).then(|| PathBuf::from(path))
}

pub(super) fn parent_of(pid: u32) -> Option<u32> {
    bsd_info(pid).map(|info| info.pbi_ppid)
}

/// `None` quando o processo sumiu ou é de outro usuário.
pub(super) fn arguments_of(pid: u32) -> Option<Arguments> {
    let pid = i32::try_from(pid).ok()?;
    let mut mib = [libc::CTL_KERN, libc::KERN_PROCARGS2, pid];
    let mut size = 0usize;
    // SAFETY: `mib` tem 3 entradas; com buffer nulo o `sysctl` só mede.
    let measured = unsafe {
        libc::sysctl(
            mib.as_mut_ptr(),
            3,
            ptr::null_mut(),
            &raw mut size,
            ptr::null_mut(),
            0,
        )
    };
    if measured != 0 || size == 0 {
        return None;
    }
    let mut buffer = vec![0u8; size];
    // SAFETY: `buffer` tem `size` bytes graváveis e `size` diz isso ao kernel.
    let read = unsafe {
        libc::sysctl(
            mib.as_mut_ptr(),
            3,
            buffer.as_mut_ptr().cast(),
            &raw mut size,
            ptr::null_mut(),
            0,
        )
    };
    if read != 0 {
        return None;
    }
    buffer.truncate(size);
    parse_procargs(&buffer)
}

/// O buffer do `KERN_PROCARGS2`: `argc` em 4 bytes, o caminho do executável,
/// zeros de alinhamento, os `argc` argumentos e então o ambiente, tudo
/// separado por NUL.
fn parse_procargs(data: &[u8]) -> Option<Arguments> {
    let (head, bytes) = data.split_first_chunk::<4>()?;
    let argc = i32::from_ne_bytes(*head);
    let mut strings = Strings { bytes, index: 0 };

    strings.next()?;
    strings.skip_padding();
    let mut parsed = Arguments::default();
    for _ in 0..argc.max(0) {
        let Some(argument) = strings.next() else {
            break;
        };
        parsed.arguments.push(argument);
    }
    // O ambiente termina na primeira string vazia; o que vem depois é a área
    // de strings do kernel (o `apple[]`), que não é do processo.
    while let Some(entry) = strings.next() {
        if entry.is_empty() {
            break;
        }
        if let Some((key, value)) = entry.split_once('=') {
            parsed
                .environment
                .insert(key.to_string(), value.to_string());
        }
    }
    Some(parsed)
}

/// Strings separadas por NUL, lidas em sequência.
struct Strings<'a> {
    bytes: &'a [u8],
    index: usize,
}

impl Strings<'_> {
    fn next(&mut self) -> Option<String> {
        if self.index >= self.bytes.len() {
            return None;
        }
        let rest = &self.bytes[self.index..];
        let length = rest.iter().position(|&b| b == 0).unwrap_or(rest.len());
        self.index += length + 1;
        Some(String::from_utf8_lossy(&rest[..length]).into_owned())
    }

    fn skip_padding(&mut self) {
        while self.bytes.get(self.index) == Some(&0) {
            self.index += 1;
        }
    }
}

fn pids() -> io::Result<Vec<u32>> {
    // SAFETY: com buffer nulo a chamada só conta os pids.
    let count = unsafe { libc::proc_listallpids(ptr::null_mut(), 0) };
    if count <= 0 {
        return Err(io::Error::last_os_error());
    }
    // Folga: entre contar e ler, processos nascem.
    let capacity = count as usize + count as usize / 8 + 16;
    let mut buffer = vec![0i32; capacity];
    let bytes = i32::try_from(capacity * mem::size_of::<i32>()).unwrap_or(i32::MAX);
    // SAFETY: `buffer` tem `capacity` inteiros e `bytes` é o tamanho dele.
    let found = unsafe { libc::proc_listallpids(buffer.as_mut_ptr().cast(), bytes) };
    if found <= 0 {
        return Err(io::Error::last_os_error());
    }
    buffer.truncate(found as usize);
    Ok(buffer
        .into_iter()
        .filter_map(|pid| u32::try_from(pid).ok())
        .filter(|&p| p > 0)
        .collect())
}

fn bsd_info(pid: u32) -> Option<libc::proc_bsdinfo> {
    let pid = i32::try_from(pid).ok()?;
    // SAFETY: `proc_bsdinfo` é só inteiros e bytes; zerada é um valor válido.
    let mut info: libc::proc_bsdinfo = unsafe { mem::zeroed() };
    let size = mem::size_of::<libc::proc_bsdinfo>() as i32;
    // SAFETY: `info` tem `size` bytes graváveis.
    let read =
        unsafe { libc::proc_pidinfo(pid, libc::PROC_PIDTBSDINFO, 0, (&raw mut info).cast(), size) };
    (read == size).then_some(info)
}

fn c_string(raw: &[libc::c_char]) -> String {
    let bytes: Vec<u8> = raw
        .iter()
        .take_while(|&&c| c != 0)
        .map(|&c| c as u8)
        .collect();
    String::from_utf8_lossy(&bytes).into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn procargs_separa_argumentos_do_ambiente() {
        let mut data = 2i32.to_ne_bytes().to_vec();
        data.extend(b"/usr/bin/node\0\0\0");
        data.extend(b"node\0app.js\0");
        data.extend(b"EGEON_NODE=a/b\0X=1=2\0\0");
        data.extend(b"ptr_munge=\0");
        let parsed = parse_procargs(&data);
        assert_eq!(
            parsed.as_ref().map(|p| p.arguments.as_slice()),
            Some(["node".to_string(), "app.js".to_string()].as_slice())
        );
        let env = parsed.map(|p| p.environment).unwrap_or_default();
        assert_eq!(env.get("EGEON_NODE").map(String::as_str), Some("a/b"));
        assert_eq!(env.get("X").map(String::as_str), Some("1=2"));
        assert_eq!(env.len(), 2);
        assert_eq!(parse_procargs(&[1]), None);
    }

    #[test]
    fn le_o_proprio_processo() {
        let me = std::process::id();
        let all = list(ProcessDetail::Full).unwrap_or_default();
        let mine = all.iter().find(|p| p.pid == me);
        assert!(mine.is_some_and(|p| !p.command.is_empty() && !p.environment.is_empty()));
        assert_eq!(parent_of(me), Some(std::os::unix::process::parent_id()));
    }
}
