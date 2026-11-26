//! O pseudoconsole do Windows direto pela API. A `portable-pty` o criava com
//! `PSEUDOCONSOLE_INHERIT_CURSOR` fixo: o console pergunta a posição do cursor
//! (`ESC[6n`) ao nascer e segura o filho até a resposta, e a ci/win-7 viu
//! sessões travarem no meio com essa conversa no caminho. Sem o flag a pergunta
//! não existe. A linha de comando, o ambiente e a pasta são montados como a
//! `portable-pty` montava, para o filho ver o mesmo que via.

use std::collections::BTreeMap;
use std::ffi::OsStr;
use std::fs::File;
use std::io;
use std::os::windows::ffi::OsStrExt;
use std::os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle};
use std::path::{Path, PathBuf};

use egeon_core::ports::pty::{PtySize, PtySpec};
use windows_sys::Win32::Foundation::{HANDLE, INVALID_HANDLE_VALUE};
use windows_sys::Win32::System::Console::{
    COORD, ClosePseudoConsole, CreatePseudoConsole, HPCON, ResizePseudoConsole,
};
use windows_sys::Win32::System::Pipes::CreatePipe;
use windows_sys::Win32::System::Threading::{
    CREATE_UNICODE_ENVIRONMENT, CreateProcessW, DeleteProcThreadAttributeList,
    EXTENDED_STARTUPINFO_PRESENT, GetExitCodeProcess, INFINITE, InitializeProcThreadAttributeList,
    PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, PROCESS_INFORMATION, STARTF_USESTDHANDLES, STARTUPINFOEXW,
    TerminateProcess, UpdateProcThreadAttribute, WaitForSingleObject,
};

/// O código de saída de quem é encerrado por aqui.
const KILLED_EXIT: u32 = 1;

/// O pseudoconsole aberto; largá-lo o fecha (`ClosePseudoConsole`), e os
/// processos ligados a ele recebem o `CTRL_CLOSE_EVENT`.
pub(super) struct PseudoConsole(HPCON);

impl PseudoConsole {
    pub(super) fn resize(&self, size: PtySize) -> io::Result<()> {
        // SAFETY: o pseudoconsole é válido enquanto `self` vive.
        hresult(unsafe { ResizePseudoConsole(self.0, coord(size)) })
    }
}

impl Drop for PseudoConsole {
    fn drop(&mut self) {
        // SAFETY: o pseudoconsole é nosso e só é fechado aqui.
        unsafe { ClosePseudoConsole(self.0) };
    }
}

/// O console e as duas pontas que ficam com o driver: `input` é o que o filho
/// lê como teclado, `output` é a tela que ele escreve.
pub(super) struct Opened {
    pub(super) console: PseudoConsole,
    pub(super) input: File,
    pub(super) output: File,
}

pub(super) fn open(size: PtySize) -> io::Result<Opened> {
    let (input_read, input) = pipe()?;
    let (output, output_write) = pipe()?;
    let mut console: HPCON = 0;
    // SAFETY: as duas pontas são válidas; `console` é um local vivo. Flags 0:
    // sem `INHERIT_CURSOR` (ver o topo do arquivo).
    hresult(unsafe {
        CreatePseudoConsole(
            coord(size),
            input_read.as_raw_handle(),
            output_write.as_raw_handle(),
            0,
            &mut console,
        )
    })?;
    // As pontas do console ficam com ele (o conhost as duplicou): fechá-las
    // aqui é o que deixa a leitura ver o fim quando o console fecha.
    drop(input_read);
    drop(output_write);
    Ok(Opened {
        console: PseudoConsole(console),
        input: File::from(input),
        output: File::from(output),
    })
}

/// O filho no pseudoconsole: o handle serve a quem espera e a quem encerra.
pub(super) struct Process {
    handle: OwnedHandle,
    pub(super) pid: u32,
}

impl Process {
    pub(super) fn handle(&self) -> HANDLE {
        self.handle.as_raw_handle()
    }

    /// Bloqueia até o filho acabar e devolve o código de saída.
    pub(super) fn wait(&self) -> io::Result<u32> {
        // SAFETY: o handle é válido enquanto `self` vive.
        unsafe { WaitForSingleObject(self.handle(), INFINITE) };
        let mut code = 0u32;
        // SAFETY: `code` é um local vivo.
        if unsafe { GetExitCodeProcess(self.handle(), &mut code) } == 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(code)
    }

    pub(super) fn kill(&self) {
        // SAFETY: o handle é válido enquanto `self` vive.
        unsafe { TerminateProcess(self.handle(), KILLED_EXIT) };
    }
}

pub(super) fn spawn(console: &PseudoConsole, spec: &PtySpec) -> io::Result<Process> {
    let env = environment(&spec.env);
    let program = search_path(&spec.program, &env);
    let application = wide(program.as_os_str());
    let mut command_line = command_line(&program, &spec.args)?;
    let block = environment_block(&env);
    let directory = current_directory(spec.cwd.as_deref(), &env);

    let mut attributes = AttributeList::with_console(console)?;
    let mut startup = STARTUPINFOEXW::default();
    startup.StartupInfo.cb = size_of::<STARTUPINFOEXW>() as u32;
    // Sem isto o filho herda as entradas e saídas redirecionadas do app (a UI
    // lança o core com canos) em vez de usar o pseudoconsole.
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput = INVALID_HANDLE_VALUE;
    startup.StartupInfo.hStdOutput = INVALID_HANDLE_VALUE;
    startup.StartupInfo.hStdError = INVALID_HANDLE_VALUE;
    startup.lpAttributeList = attributes.as_mut_ptr();

    // SAFETY: estrutura zerada é válida e é preenchida pela chamada.
    let mut info: PROCESS_INFORMATION = unsafe { std::mem::zeroed() };
    // SAFETY: as cadeias terminam em zero e vivem até o fim da chamada; a
    // linha de comando é mutável, como a API exige; a lista de atributos vive
    // em `attributes`.
    let created = unsafe {
        CreateProcessW(
            application.as_ptr(),
            command_line.as_mut_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            0,
            EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
            block.as_ptr().cast(),
            directory.as_ref().map_or(std::ptr::null(), |d| d.as_ptr()),
            &raw const startup.StartupInfo,
            &mut info,
        )
    };
    if created == 0 {
        return Err(io::Error::last_os_error());
    }
    // SAFETY: os dois handles são novos e só nossos.
    let (_thread, handle) = unsafe {
        (
            OwnedHandle::from_raw_handle(info.hThread),
            OwnedHandle::from_raw_handle(info.hProcess),
        )
    };
    Ok(Process {
        handle,
        pid: info.dwProcessId,
    })
}

/// A lista de atributos do `CreateProcessW`, só com o pseudoconsole.
struct AttributeList(Vec<u8>);

impl AttributeList {
    fn with_console(console: &PseudoConsole) -> io::Result<Self> {
        let mut size = 0usize;
        // SAFETY: a primeira chamada só mede o tamanho.
        unsafe { InitializeProcThreadAttributeList(std::ptr::null_mut(), 1, 0, &mut size) };
        let mut list = AttributeList(vec![0u8; size]);
        // SAFETY: o buffer tem o tamanho pedido.
        if unsafe { InitializeProcThreadAttributeList(list.as_mut_ptr(), 1, 0, &mut size) } == 0 {
            // Sem lista iniciada não há o que apagar no `Drop`.
            std::mem::forget(list);
            return Err(io::Error::last_os_error());
        }
        // O valor do atributo é o próprio HPCON, não um ponteiro para ele.
        // SAFETY: a lista foi iniciada; o pseudoconsole vive mais que ela.
        let updated = unsafe {
            UpdateProcThreadAttribute(
                list.as_mut_ptr(),
                0,
                PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE as usize,
                console.0 as *const core::ffi::c_void,
                size_of::<HPCON>(),
                std::ptr::null_mut(),
                std::ptr::null(),
            )
        };
        if updated == 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(list)
    }

    fn as_mut_ptr(&mut self) -> *mut core::ffi::c_void {
        self.0.as_mut_ptr().cast()
    }
}

impl Drop for AttributeList {
    fn drop(&mut self) {
        // SAFETY: a lista foi iniciada (o caminho de erro a esquece).
        unsafe { DeleteProcThreadAttributeList(self.as_mut_ptr()) };
    }
}

fn pipe() -> io::Result<(OwnedHandle, OwnedHandle)> {
    let (mut read, mut write): (HANDLE, HANDLE) = (std::ptr::null_mut(), std::ptr::null_mut());
    // SAFETY: dois locais vivos; sem atributos, as pontas não são herdáveis.
    if unsafe { CreatePipe(&mut read, &mut write, std::ptr::null(), 0) } == 0 {
        return Err(io::Error::last_os_error());
    }
    // SAFETY: handles novos e só nossos.
    Ok(unsafe {
        (
            OwnedHandle::from_raw_handle(read),
            OwnedHandle::from_raw_handle(write),
        )
    })
}

fn coord(size: PtySize) -> COORD {
    COORD {
        X: i16::try_from(size.cols).unwrap_or(i16::MAX),
        Y: i16::try_from(size.rows).unwrap_or(i16::MAX),
    }
}

fn hresult(code: windows_sys::core::HRESULT) -> io::Result<()> {
    if code >= 0 {
        Ok(())
    } else {
        Err(io::Error::from_raw_os_error(code))
    }
}

fn wide(text: &OsStr) -> Vec<u16> {
    text.encode_wide().chain(std::iter::once(0)).collect()
}

/// O ambiente do pedido, uma entrada por nome sem caixa (o Windows não
/// distingue `Path` de `PATH`), em ordem — como o bloco que a API espera.
fn environment(env: &[(String, String)]) -> BTreeMap<String, (String, String)> {
    env.iter()
        .map(|(key, value)| (key.to_uppercase(), (key.clone(), value.clone())))
        .collect()
}

fn lookup<'a>(env: &'a BTreeMap<String, (String, String)>, key: &str) -> Option<&'a str> {
    env.get(&key.to_uppercase()).map(|(_, v)| v.as_str())
}

fn environment_block(env: &BTreeMap<String, (String, String)>) -> Vec<u16> {
    let mut block = Vec::new();
    for (key, value) in env.values() {
        block.extend(OsStr::new(key).encode_wide());
        block.push(u16::from(b'='));
        block.extend(OsStr::new(value).encode_wide());
        block.push(0);
    }
    // Bloco vazio também termina com dois zeros.
    if block.is_empty() {
        block.push(0);
    }
    block.push(0);
    block
}

/// O programa pelo PATH do pedido quando não vem com pasta, tentando as
/// extensões do `PATHEXT` (o `search_path` da `portable-pty`).
fn search_path(program: &Path, env: &BTreeMap<String, (String, String)>) -> PathBuf {
    let Some(path) = lookup(env, "PATH") else {
        return program.to_path_buf();
    };
    let extensions = lookup(env, "PATHEXT").unwrap_or(".EXE");
    for dir in std::env::split_paths(path) {
        let candidate = dir.join(program);
        if candidate.exists() {
            return candidate;
        }
        for ext in extensions.split(';').filter_map(|e| e.strip_prefix('.')) {
            let candidate = dir.join(program).with_extension(ext);
            if candidate.exists() {
                return candidate;
            }
        }
    }
    program.to_path_buf()
}

/// A pasta pedida, ou o `USERPROFILE` do pedido, se forem pastas; senão a do
/// app.
fn current_directory(
    cwd: Option<&Path>,
    env: &BTreeMap<String, (String, String)>,
) -> Option<Vec<u16>> {
    let home = lookup(env, "USERPROFILE").map(Path::new);
    let dir = cwd.filter(|d| d.is_dir()).or(home.filter(|d| d.is_dir()))?;
    let dir = if dir.is_relative() {
        std::env::current_dir().map_or_else(|_| dir.to_path_buf(), |c| c.join(dir))
    } else {
        dir.to_path_buf()
    };
    Some(wide(dir.as_os_str()))
}

fn command_line(program: &Path, args: &[String]) -> io::Result<Vec<u16>> {
    let mut line = Vec::new();
    append_quoted(program.as_os_str(), &mut line);
    for arg in args {
        if arg.contains('\0') {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                format!("argumento com NUL: {arg:?}"),
            ));
        }
        line.push(u16::from(b' '));
        append_quoted(OsStr::new(arg), &mut line);
    }
    line.push(0);
    Ok(line)
}

/// As regras do `CommandLineToArgvW` (o `ArgvQuote`), as mesmas da
/// `portable-pty`: aspas só quando precisa, e as barras antes de aspas
/// dobradas.
fn append_quoted(arg: &OsStr, line: &mut Vec<u16>) {
    let units: Vec<u16> = arg.encode_wide().collect();
    let plain = !units.is_empty()
        && !units
            .iter()
            .any(|&c| matches!(c, 0x20 | 0x09 | 0x0A | 0x0B | 0x22));
    if plain {
        line.extend(units);
        return;
    }
    let (quote, backslash) = (u16::from(b'"'), u16::from(b'\\'));
    line.push(quote);
    let mut i = 0;
    while i < units.len() {
        let mut backslashes = 0;
        while i < units.len() && units[i] == backslash {
            i += 1;
            backslashes += 1;
        }
        if i == units.len() {
            line.extend(std::iter::repeat_n(backslash, backslashes * 2));
            break;
        }
        if units[i] == quote {
            line.extend(std::iter::repeat_n(backslash, backslashes * 2 + 1));
        } else {
            line.extend(std::iter::repeat_n(backslash, backslashes));
        }
        line.push(units[i]);
        i += 1;
    }
    line.push(quote);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn quoted(arg: &str) -> String {
        let mut line = Vec::new();
        append_quoted(OsStr::new(arg), &mut line);
        String::from_utf16_lossy(&line)
    }

    #[test]
    fn aspas_como_o_command_line_to_argv() {
        assert_eq!(quoted("simples"), "simples");
        assert_eq!(quoted(""), "\"\"");
        assert_eq!(quoted("com espaço"), "\"com espaço\"");
        assert_eq!(quoted(r#"diz "oi""#), r#""diz \"oi\"""#);
        assert_eq!(quoted(r"C:\a b\"), r#""C:\a b\\""#);
        assert_eq!(quoted(r"C:\sem\espaco"), r"C:\sem\espaco");
    }

    #[test]
    fn bloco_de_ambiente_sem_caixa_em_ordem_e_com_dois_zeros() {
        let env = environment(&[
            ("b".into(), "2".into()),
            ("Path".into(), "x".into()),
            ("PATH".into(), "y".into()),
        ]);
        let block = String::from_utf16_lossy(&environment_block(&env));
        assert_eq!(block, "b=2\0PATH=y\0\0");
        assert_eq!(environment_block(&BTreeMap::new()), [0, 0]);
    }
}
