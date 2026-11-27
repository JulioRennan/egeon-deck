//! A primeira versão do Windows não põe aviso na central do sistema: a
//! notificação do Windows (toast) pede um identificador de app registrado,
//! que só um instalador cria, e a decisão 54 sai em zip. O aviso fica na UI;
//! o som de atenção toca.

use std::ffi::OsStr;
use std::os::windows::ffi::OsStrExt;
use std::path::PathBuf;

use egeon_core::ports::notifier::{Notice, NoticeClick, SoundError};
use tokio::sync::mpsc;
use windows_sys::Win32::Media::Audio::{PlaySoundW, SND_ASYNC, SND_FILENAME, SND_NODEFAULT};
use windows_sys::Win32::System::Diagnostics::Debug::MessageBeep;
use windows_sys::Win32::UI::WindowsAndMessaging::MB_ICONASTERISK;

/// Os sons do sistema do macOS, que o `agents.json` traz (o padrão é `Tink`)
/// e que não existem no Windows: tocam o aviso do sistema, em vez de calar.
const MACOS_SOUNDS: [&str; 14] = [
    "Basso",
    "Blow",
    "Bottle",
    "Frog",
    "Funk",
    "Glass",
    "Hero",
    "Morse",
    "Ping",
    "Pop",
    "Purr",
    "Sosumi",
    "Submarine",
    "Tink",
];

#[derive(Default)]
pub(super) struct Center;

impl Center {
    /// Sem central, nenhum clique chega: o canal nasce fechado.
    pub(super) fn start(&self) -> mpsc::Receiver<NoticeClick> {
        let (_clicks, receiver) = mpsc::channel(1);
        receiver
    }

    pub(super) fn authorized(&self) -> bool {
        false
    }

    pub(super) fn post(&self, _notice: Notice) {}

    pub(super) fn withdraw(&self, _identifier: &str) {}
}

#[derive(Default)]
pub(super) struct Sounds;

impl Sounds {
    /// `name` é um som do macOS (vira o aviso do sistema) ou um `.wav` da
    /// pasta `Media` do Windows, sem a extensão. O volume é o do sistema.
    pub(super) fn play(&self, name: &str, volume: f64) -> Result<(), SoundError> {
        if name.is_empty() || volume <= 0.0 {
            return Ok(());
        }
        if MACOS_SOUNDS.contains(&name) {
            // SAFETY: sem pré-condição; volta na hora e o som toca sozinho.
            unsafe { MessageBeep(MB_ICONASTERISK) };
            return Ok(());
        }
        let file = media_file(name).ok_or_else(|| SoundError::Unknown(name.to_string()))?;
        let wide: Vec<u16> = file.as_os_str().encode_wide().chain([0]).collect();
        // SAFETY: o caminho termina em zero e vive até o fim da chamada; com
        // `SND_ASYNC` o sistema copia o que precisa antes de voltar.
        unsafe {
            PlaySoundW(
                wide.as_ptr(),
                std::ptr::null_mut(),
                SND_FILENAME | SND_ASYNC | SND_NODEFAULT,
            )
        };
        Ok(())
    }
}

fn media_file(name: &str) -> Option<PathBuf> {
    // Só o nome: nada de caminho que saia da pasta.
    if name.contains(['/', '\\', ':']) || name.contains("..") {
        return None;
    }
    let root = std::env::var_os("SystemRoot").unwrap_or_else(|| OsStr::new(r"C:\Windows").into());
    let file = PathBuf::from(root)
        .join("Media")
        .join(format!("{name}.wav"));
    file.is_file().then_some(file)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn som_que_nao_existe_e_erro_e_volume_zero_cala() {
        let sounds = Sounds;
        assert_eq!(
            sounds.play("egeon-som-que-nao-existe", 1.0),
            Err(SoundError::Unknown("egeon-som-que-nao-existe".into()))
        );
        assert!(sounds.play("..\\x", 1.0).is_err());
        assert_eq!(sounds.play("Tink", 0.0), Ok(()));
        assert_eq!(sounds.play("", 1.0), Ok(()));
    }
}
