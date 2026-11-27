//! O `ShellExecuteW` com o verbo `open`, que abre o arquivo ou a URL no app
//! padrão, e o alerta do sistema.

use std::ffi::OsStr;
use std::os::windows::ffi::OsStrExt;
use std::thread;

use egeon_core::log;
use egeon_core::ports::opener::OpenTarget;
use windows_sys::Win32::System::Com::{
    COINIT_APARTMENTTHREADED, COINIT_DISABLE_OLE1DDE, CoInitializeEx, CoUninitialize,
};
use windows_sys::Win32::System::Diagnostics::Debug::MessageBeep;
use windows_sys::Win32::System::Registry::{
    HKEY, HKEY_CLASSES_ROOT, KEY_READ, RegCloseKey, RegOpenKeyExW, RegQueryValueExW,
};
use windows_sys::Win32::UI::Shell::ShellExecuteW;
use windows_sys::Win32::UI::WindowsAndMessaging::{MB_OK, SW_SHOWNORMAL};

use super::url::{scheme_of, url_of};

/// O `ShellExecuteW` pode demorar (extensões do shell, DDE) e o core chama da
/// tarefa dona do estado: ele roda solto numa thread. O que dá para saber
/// antes — arquivo que sumiu, texto que não é URL, esquema sem quem o trate —
/// devolve `false` aqui, como no Linux.
pub(super) fn open(target: &OpenTarget) -> bool {
    let argument = match target {
        OpenTarget::File(path) => {
            if !path.exists() {
                return false;
            }
            path.as_os_str().to_owned()
        }
        OpenTarget::Url(text) => {
            let Some(url) = url_of(text) else {
                return false;
            };
            if !has_handler(scheme_of(&url)) {
                return false;
            }
            url.into()
        }
    };
    let spawned = thread::Builder::new()
        .name("abrir".into())
        .spawn(move || shell_open(&argument));
    if let Err(error) = spawned {
        log!("abrir: sem thread para o ShellExecute — {error}");
        return false;
    }
    true
}

fn wide(text: &OsStr) -> Vec<u16> {
    text.encode_wide().chain([0]).collect()
}

fn shell_open(argument: &OsStr) {
    let verb = wide(OsStr::new("open"));
    let file = wide(argument);
    // SAFETY: as strings são locais terminadas em zero e vivem até o fim das
    // chamadas. O COM em STA é o que o `ShellExecute` pede a quem o chama.
    let result = unsafe {
        let com = CoInitializeEx(
            std::ptr::null(),
            (COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE) as u32,
        );
        let result = ShellExecuteW(
            std::ptr::null_mut(),
            verb.as_ptr(),
            file.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            SW_SHOWNORMAL,
        );
        if com >= 0 {
            CoUninitialize();
        }
        result as isize
    };
    // Até 32 é código de erro (`SE_ERR_*`).
    if result <= 32 {
        log!("abrir: ShellExecute falhou ({result})");
    }
}

/// Web e arquivo sempre têm quem abra; para o resto, o esquema tem de estar
/// registrado como protocolo (`HKCR\<esquema>` com o valor `URL Protocol`).
fn has_handler(scheme: &str) -> bool {
    let scheme = scheme.to_ascii_lowercase();
    if matches!(scheme.as_str(), "http" | "https" | "file") {
        return true;
    }
    let key_name = wide(OsStr::new(&scheme));
    let value_name = wide(OsStr::new("URL Protocol"));
    let mut key: HKEY = std::ptr::null_mut();
    // SAFETY: nomes terminados em zero; `key` é um local vivo e, aberto, é
    // fechado abaixo.
    unsafe {
        if RegOpenKeyExW(HKEY_CLASSES_ROOT, key_name.as_ptr(), 0, KEY_READ, &mut key) != 0 {
            return false;
        }
        let found = RegQueryValueExW(
            key,
            value_name.as_ptr(),
            std::ptr::null(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
        ) == 0;
        RegCloseKey(key);
        found
    }
}

pub(super) fn beep() {
    // SAFETY: sem pré-condição.
    unsafe { MessageBeep(MB_OK) };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn esquema_sem_app_registrado_nao_tem_quem_abra() {
        assert!(has_handler("HTTPS"));
        assert!(!has_handler("egeon-esquema-que-ninguem-trata"));
    }

    #[test]
    fn arquivo_que_nao_existe_nao_abre_e_nao_roda_nada() {
        let path = std::env::temp_dir()
            .join("egeon-nao-existe-e2e")
            .join("nada.txt");
        assert!(!open(&OpenTarget::File(path)));
        assert!(!open(&OpenTarget::Url("isto nao e url".into())));
    }
}
