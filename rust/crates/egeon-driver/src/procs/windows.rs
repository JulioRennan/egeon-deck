//! A tabela de processos do Windows: o retrato do Toolhelp (pid, pai, nome),
//! o início pelo `GetProcessTimes` e a linha de comando, o ambiente e a pasta
//! lidos do PEB do processo.
//!
//! Só os processos do usuário, como no unix: o dono do token tem de ser o
//! mesmo do app. Processo que não se deixa abrir fica de fora.

use std::collections::HashMap;
use std::ffi::OsString;
use std::io;
use std::os::windows::ffi::OsStringExt;
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
use std::path::PathBuf;
use std::time::{Duration, SystemTime};

use egeon_core::ports::procs::{ProcessDetail, ProcessError, ProcessSignal, RawProcess};
use windows_sys::Wdk::System::Threading::{NtQueryInformationProcess, ProcessBasicInformation};
use windows_sys::Win32::Foundation::{
    ERROR_ACCESS_DENIED, ERROR_INVALID_PARAMETER, FILETIME, HANDLE, INVALID_HANDLE_VALUE,
};
use windows_sys::Win32::Security::{
    EqualSid, GetTokenInformation, TOKEN_QUERY, TOKEN_USER, TokenUser,
};
use windows_sys::Win32::System::Diagnostics::Debug::ReadProcessMemory;
use windows_sys::Win32::System::Diagnostics::ToolHelp::{
    CreateToolhelp32Snapshot, PROCESSENTRY32W, Process32FirstW, Process32NextW, TH32CS_SNAPPROCESS,
};
use windows_sys::Win32::System::Threading::{
    GetCurrentProcess, GetProcessTimes, OpenProcess, OpenProcessToken, PROCESS_BASIC_INFORMATION,
    PROCESS_QUERY_LIMITED_INFORMATION, PROCESS_TERMINATE, PROCESS_VM_READ, TerminateProcess,
};

#[derive(Debug, Default, PartialEq, Eq)]
pub(super) struct Arguments {
    pub arguments: Vec<String>,
    pub environment: HashMap<String, String>,
}

/// Do FILETIME (100 ns desde 1601) para o relógio do Rust (desde 1970).
const EPOCH_DIFF_100NS: u64 = 116_444_736_000_000_000;
/// Teto do bloco de ambiente lido de outro processo.
const MAX_ENVIRONMENT: usize = 1 << 20;
/// O código de saída de quem é encerrado por aqui.
const KILLED_EXIT: u32 = 1;

// Deslocamentos do PEB e do `RTL_USER_PROCESS_PARAMETERS` no x86_64, estáveis
// desde o Vista; o alvo da decisão 54 é só x86_64.
const PEB_PROCESS_PARAMETERS: usize = 0x20;
const PARAMS_CURRENT_DIRECTORY: usize = 0x38;
const PARAMS_COMMAND_LINE: usize = 0x70;
const PARAMS_ENVIRONMENT: usize = 0x80;
const PARAMS_ENVIRONMENT_SIZE: usize = 0x3F0;

pub(super) fn list(detail: ProcessDetail) -> Result<Vec<RawProcess>, ProcessError> {
    let me = current_user().map_err(ProcessError::Table)?;
    let entries = snapshot().map_err(ProcessError::Table)?;
    Ok(entries
        .into_iter()
        .filter_map(|entry| {
            // Processo que acabou entre o retrato e a leitura some da lista.
            let access = match detail {
                ProcessDetail::Full => PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ,
                ProcessDetail::Tree => PROCESS_QUERY_LIMITED_INFORMATION,
            };
            let process = open(entry.pid, access)
                .or_else(|| open(entry.pid, PROCESS_QUERY_LIMITED_INFORMATION))?;
            if !owned_by(&process, &me) {
                return None;
            }
            let started = start_time(&process)?;
            let arguments = match detail {
                ProcessDetail::Full => read_parameters(&process).map(|p| p.arguments),
                ProcessDetail::Tree => None,
            };
            let command = arguments
                .as_ref()
                .map(|a| a.arguments.join(" "))
                .filter(|command| !command.is_empty())
                .unwrap_or_else(|| entry.name.clone());
            Some(RawProcess {
                pid: entry.pid,
                ppid: entry.ppid,
                started,
                name: entry.name,
                command,
                environment: arguments.map(|a| a.environment).unwrap_or_default(),
            })
        })
        .collect())
}

pub(super) fn cwd_of(pid: u32) -> Option<PathBuf> {
    let process = open(pid, PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ)?;
    read_parameters(&process).map(|p| p.cwd)
}

/// O pai segundo o retrato. O Windows não reaproveita o pai como o unix (não
/// há reparentamento para o pid 1): pai que morreu deixa o pid dele no filho,
/// e o pid pode já ser de outro processo — quem sobe a cadeia para no
/// terminal dono, que está vivo.
pub(super) fn parent_of(pid: u32) -> Option<u32> {
    snapshot()
        .ok()?
        .into_iter()
        .find(|entry| entry.pid == pid)
        .map(|entry| entry.ppid)
}

pub(super) fn arguments_of(pid: u32) -> Option<Arguments> {
    let process = open(pid, PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ)?;
    read_parameters(&process).map(|p| p.arguments)
}

/// O Windows não tem sinal: os dois encerram o processo. O 0 é o processo
/// ocioso do sistema e o 4 é o `System`; nada disso passa por um pid da
/// tabela, como o `kill(0)` e o pid 1 no unix.
pub(super) fn send(pid: u32, _signal: ProcessSignal) -> Result<(), ProcessError> {
    if pid <= 4 {
        return Err(ProcessError::Signal {
            pid,
            source: io::Error::from(io::ErrorKind::InvalidInput),
        });
    }
    let Some(process) = open(pid, PROCESS_TERMINATE) else {
        let source = io::Error::last_os_error();
        return Err(match source.raw_os_error() {
            Some(code) if code == ERROR_INVALID_PARAMETER as i32 => ProcessError::Gone(pid),
            _ => ProcessError::Signal { pid, source },
        });
    };
    // SAFETY: o handle é válido e tem o direito de encerrar.
    if unsafe { TerminateProcess(raw(&process), KILLED_EXIT) } != 0 {
        return Ok(());
    }
    let source = io::Error::last_os_error();
    // Encerrar quem já está saindo dá acesso negado.
    if source.raw_os_error() == Some(ERROR_ACCESS_DENIED as i32) && start_time(&process).is_none() {
        return Err(ProcessError::Gone(pid));
    }
    Err(ProcessError::Signal { pid, source })
}

struct Entry {
    pid: u32,
    ppid: u32,
    name: String,
}

fn snapshot() -> io::Result<Vec<Entry>> {
    // SAFETY: sem pré-condição; o handle devolvido é nosso.
    let raw_snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) };
    if raw_snapshot == INVALID_HANDLE_VALUE {
        return Err(io::Error::last_os_error());
    }
    // SAFETY: handle novo e válido, só nosso.
    let snapshot = unsafe { OwnedHandle::from_raw_handle(raw_snapshot) };
    let mut entries = Vec::new();
    // SAFETY: estrutura zerada é válida; o `dwSize` é o que a API exige.
    let mut entry: PROCESSENTRY32W = unsafe { std::mem::zeroed() };
    entry.dwSize = size_of::<PROCESSENTRY32W>() as u32;
    // SAFETY: `entry` é um local vivo com o `dwSize` preenchido.
    let mut more = unsafe { Process32FirstW(raw(&snapshot), &mut entry) } != 0;
    while more {
        entries.push(Entry {
            pid: entry.th32ProcessID,
            ppid: entry.th32ParentProcessID,
            name: short_name(&entry.szExeFile),
        });
        // SAFETY: como acima.
        more = unsafe { Process32NextW(raw(&snapshot), &mut entry) } != 0;
    }
    Ok(entries)
}

/// O nome sem o `.exe`: é por ele que o core reconhece outro `egeon-app`, e
/// assim fica igual ao `p_comm` do unix.
fn short_name(exe: &[u16]) -> String {
    let end = exe.iter().position(|&c| c == 0).unwrap_or(exe.len());
    let name = String::from_utf16_lossy(&exe[..end]);
    match name.len().checked_sub(4) {
        Some(cut) if name.is_char_boundary(cut) && name[cut..].eq_ignore_ascii_case(".exe") => {
            name[..cut].to_owned()
        }
        _ => name,
    }
}

fn raw(handle: &OwnedHandle) -> HANDLE {
    handle.as_raw_handle()
}

fn open(pid: u32, access: u32) -> Option<OwnedHandle> {
    // SAFETY: sem pré-condição; o handle devolvido, se houver, é nosso.
    let handle = unsafe { OpenProcess(access, 0, pid) };
    if handle.is_null() {
        return None;
    }
    // SAFETY: handle novo e válido, só nosso.
    Some(unsafe { OwnedHandle::from_raw_handle(handle) })
}

fn start_time(process: &OwnedHandle) -> Option<SystemTime> {
    let zero = FILETIME {
        dwLowDateTime: 0,
        dwHighDateTime: 0,
    };
    let (mut created, mut exited, mut kernel, mut user) = (zero, zero, zero, zero);
    // SAFETY: quatro locais vivos; o handle tem o direito de consulta.
    let ok = unsafe {
        GetProcessTimes(
            raw(process),
            &mut created,
            &mut exited,
            &mut kernel,
            &mut user,
        )
    };
    if ok == 0 {
        return None;
    }
    let ticks = (u64::from(created.dwHighDateTime) << 32) | u64::from(created.dwLowDateTime);
    let since_epoch = ticks.checked_sub(EPOCH_DIFF_100NS)?;
    Some(SystemTime::UNIX_EPOCH + Duration::from_nanos(since_epoch.saturating_mul(100)))
}

/// O SID do dono do token, em bytes (o `TOKEN_USER` aponta para dentro do
/// próprio buffer).
struct UserSid(Vec<u8>);

impl UserSid {
    fn sid(&self) -> *mut core::ffi::c_void {
        // SAFETY: o buffer começa com um `TOKEN_USER` preenchido pelo sistema.
        unsafe { (*self.0.as_ptr().cast::<TOKEN_USER>()).User.Sid }
    }
}

fn token_user(process: HANDLE) -> Option<UserSid> {
    let mut token: HANDLE = std::ptr::null_mut();
    // SAFETY: `token` é um local vivo; o handle devolvido é nosso.
    if unsafe { OpenProcessToken(process, TOKEN_QUERY, &mut token) } == 0 {
        return None;
    }
    // SAFETY: handle novo e válido, só nosso.
    let token = unsafe { OwnedHandle::from_raw_handle(token) };
    let mut needed = 0u32;
    // SAFETY: a primeira chamada só mede o tamanho.
    unsafe { GetTokenInformation(raw(&token), TokenUser, std::ptr::null_mut(), 0, &mut needed) };
    if needed == 0 {
        return None;
    }
    // `u64` para o alinhamento do `TOKEN_USER`.
    let mut buffer = vec![0u64; (needed as usize).div_ceil(8)];
    // SAFETY: o buffer tem pelo menos `needed` bytes.
    let ok = unsafe {
        GetTokenInformation(
            raw(&token),
            TokenUser,
            buffer.as_mut_ptr().cast(),
            needed,
            &mut needed,
        )
    };
    if ok == 0 {
        return None;
    }
    let bytes = buffer.iter().flat_map(|w| w.to_ne_bytes()).collect();
    Some(UserSid(bytes))
}

fn current_user() -> io::Result<UserSid> {
    // SAFETY: o pseudo-handle do próprio processo não precisa ser fechado.
    token_user(unsafe { GetCurrentProcess() })
        .ok_or_else(|| io::Error::other("não li o usuário do próprio processo"))
}

fn owned_by(process: &OwnedHandle, user: &UserSid) -> bool {
    let Some(owner) = token_user(raw(process)) else {
        return false;
    };
    // SAFETY: os dois SIDs apontam para dentro de buffers vivos.
    unsafe { EqualSid(owner.sid(), user.sid()) != 0 }
}

struct Parameters {
    arguments: Arguments,
    cwd: PathBuf,
}

fn read_parameters(process: &OwnedHandle) -> Option<Parameters> {
    // SAFETY: estrutura zerada é válida e é preenchida pela chamada.
    let mut basic: PROCESS_BASIC_INFORMATION = unsafe { std::mem::zeroed() };
    let mut returned = 0u32;
    // SAFETY: `basic` é um local vivo com o tamanho declarado.
    let status = unsafe {
        NtQueryInformationProcess(
            raw(process),
            ProcessBasicInformation,
            (&raw mut basic).cast(),
            size_of::<PROCESS_BASIC_INFORMATION>() as u32,
            &mut returned,
        )
    };
    if status < 0 || basic.PebBaseAddress.is_null() {
        return None;
    }
    let peb = basic.PebBaseAddress as usize;
    let params = read_usize(process, peb + PEB_PROCESS_PARAMETERS)?;
    let command_line = read_unicode_string(process, params + PARAMS_COMMAND_LINE)?;
    let cwd = read_unicode_string(process, params + PARAMS_CURRENT_DIRECTORY).unwrap_or_default();
    let environment = read_environment(process, params).unwrap_or_default();
    Some(Parameters {
        arguments: Arguments {
            arguments: split_command_line(&command_line),
            environment,
        },
        // A pasta do PEB termina em `\`, salvo na raiz do disco.
        cwd: PathBuf::from(trim_separator(&cwd)),
    })
}

fn trim_separator(path: &str) -> &str {
    if path.len() > 3 {
        path.strip_suffix('\\').unwrap_or(path)
    } else {
        path
    }
}

fn read_memory(process: &OwnedHandle, address: usize, buffer: &mut [u8]) -> Option<()> {
    let mut read = 0usize;
    // SAFETY: o buffer é um slice vivo com o tamanho passado; a leitura é da
    // memória do outro processo, que o sistema confere.
    let ok = unsafe {
        ReadProcessMemory(
            raw(process),
            address as *const _,
            buffer.as_mut_ptr().cast(),
            buffer.len(),
            &mut read,
        )
    };
    (ok != 0 && read == buffer.len()).then_some(())
}

fn read_usize(process: &OwnedHandle, address: usize) -> Option<usize> {
    let mut bytes = [0u8; 8];
    read_memory(process, address, &mut bytes)?;
    usize::try_from(u64::from_le_bytes(bytes)).ok()
}

/// `UNICODE_STRING` do x86_64: tamanho em bytes (u16), máximo (u16), folga e
/// o ponteiro.
fn read_unicode_string(process: &OwnedHandle, address: usize) -> Option<String> {
    let mut header = [0u8; 16];
    read_memory(process, address, &mut header)?;
    let length = usize::from(u16::from_le_bytes([header[0], header[1]]));
    let buffer = usize::try_from(u64::from_le_bytes(header[8..16].try_into().ok()?)).ok()?;
    if length == 0 || buffer == 0 {
        return Some(String::new());
    }
    let mut bytes = vec![0u8; length];
    read_memory(process, buffer, &mut bytes)?;
    Some(utf16_lossy(&bytes))
}

fn utf16_lossy(bytes: &[u8]) -> String {
    let units: Vec<u16> = bytes
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| u16::from_le_bytes(*pair))
        .collect();
    OsString::from_wide(&units).to_string_lossy().into_owned()
}

fn read_environment(process: &OwnedHandle, params: usize) -> Option<HashMap<String, String>> {
    let block = read_usize(process, params + PARAMS_ENVIRONMENT)?;
    let size = read_usize(process, params + PARAMS_ENVIRONMENT_SIZE)?.min(MAX_ENVIRONMENT);
    if block == 0 || size == 0 {
        return None;
    }
    let mut bytes = vec![0u8; size & !1];
    read_memory(process, block, &mut bytes)?;
    Some(parse_environment(&utf16_lossy(&bytes)))
}

/// `CHAVE=valor\0…\0\0`. As entradas que começam com `=` (`=C:=C:\pasta`, a
/// pasta de cada disco) não são variáveis.
fn parse_environment(block: &str) -> HashMap<String, String> {
    block
        .split('\0')
        .take_while(|entry| !entry.is_empty())
        .filter(|entry| !entry.starts_with('='))
        .filter_map(|entry| {
            let (key, value) = entry.split_once('=')?;
            Some((key.to_owned(), value.to_owned()))
        })
        .collect()
}

/// A linha de comando partida como o `CommandLineToArgvW`: espaço separa,
/// aspas agrupam, e barras invertidas só escapam quando vêm antes de aspas.
fn split_command_line(line: &str) -> Vec<String> {
    let mut arguments = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;
    let mut has_argument = false;
    let mut chars = line.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '\\' => {
                let mut slashes = 1;
                while chars.peek() == Some(&'\\') {
                    chars.next();
                    slashes += 1;
                }
                if chars.peek() == Some(&'"') {
                    current.extend(std::iter::repeat_n('\\', slashes / 2));
                    if slashes % 2 == 1 {
                        chars.next();
                        current.push('"');
                    }
                } else {
                    current.extend(std::iter::repeat_n('\\', slashes));
                }
                has_argument = true;
            }
            '"' => {
                in_quotes = !in_quotes;
                has_argument = true;
            }
            ' ' | '\t' if !in_quotes => {
                if has_argument {
                    arguments.push(std::mem::take(&mut current));
                    has_argument = false;
                }
            }
            other => {
                current.push(other);
                has_argument = true;
            }
        }
    }
    if has_argument {
        arguments.push(current);
    }
    arguments
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn linha_de_comando_partida_como_no_windows() {
        assert_eq!(
            split_command_line(r#""C:\Program Files\x.exe" -a "b c" d"#),
            [r"C:\Program Files\x.exe", "-a", "b c", "d"]
        );
        assert_eq!(
            split_command_line(r#"a\\\"b "c\\" """#),
            [r#"a\"b"#, r"c\", ""]
        );
        assert_eq!(split_command_line(r"a\b  c"), [r"a\b", "c"]);
        assert!(split_command_line("   ").is_empty());
    }

    #[test]
    fn ambiente_sem_as_pastas_de_disco() {
        let env = parse_environment("=C:=C:\\x\0PATH=C:\\bin\0A=b=c\0\0LIXO=1");
        assert_eq!(env.len(), 2);
        assert_eq!(env.get("PATH").map(String::as_str), Some("C:\\bin"));
        assert_eq!(env.get("A").map(String::as_str), Some("b=c"));
    }

    #[test]
    fn nome_sem_exe() {
        let wide = |s: &str| s.encode_utf16().chain([0, 7]).collect::<Vec<u16>>();
        assert_eq!(short_name(&wide("egeon-app.exe")), "egeon-app");
        assert_eq!(short_name(&wide("EgeonDeck.EXE")), "EgeonDeck");
        assert_eq!(short_name(&wide("System")), "System");
    }

    #[test]
    fn o_proprio_processo_aparece_com_pai_inicio_e_pasta() -> Result<(), ProcessError> {
        let me = std::process::id();
        let all = list(ProcessDetail::Full)?;
        let mine = all
            .iter()
            .find(|p| p.pid == me)
            .ok_or(ProcessError::Gone(me))?;
        assert!(mine.started <= SystemTime::now());
        assert!(mine.environment.contains_key("PATH") || mine.environment.contains_key("Path"));
        assert!(!mine.command.is_empty());
        assert_eq!(parent_of(me), Some(mine.ppid));
        let cwd = std::env::current_dir().map_err(ProcessError::Table)?;
        assert_eq!(cwd_of(me), Some(cwd));
        Ok(())
    }
}
