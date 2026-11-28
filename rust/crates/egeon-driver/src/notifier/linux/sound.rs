//! Os sons do tema freedesktop, tocados pelo `paplay` (PulseAudio e o
//! PipeWire com a camada do Pulse) ou pelo `pw-play` (PipeWire puro).

use std::collections::HashMap;
use std::env;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::{Mutex, PoisonError};

use egeon_core::log;
use egeon_core::ports::notifier::SoundError;

/// Os sons do sistema do macOS, que o `agents.json` traz (o padrão é `Tink`) e
/// que não existem no Linux: tocam o aviso curto do tema, em vez de calar.
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
const MACOS_STAND_IN: &str = "message";
const EXTENSIONS: [&str; 3] = ["oga", "ogg", "wav"];

/// O som tocando de cada nome, para o seguinte reiniciar em vez de somar.
#[derive(Default)]
pub(in crate::notifier) struct Sounds {
    playing: Mutex<HashMap<String, Child>>,
}

impl Sounds {
    /// `name` é um som do tema (`~/.local/share/sounds`, `/usr/share/sounds`).
    pub(in crate::notifier) fn play(&self, name: &str, volume: f64) -> Result<(), SoundError> {
        if name.is_empty() || volume <= 0.0 {
            return Ok(());
        }
        let file = find(name, &data_dirs()).ok_or_else(|| SoundError::Unknown(name.to_string()))?;
        let mut playing = self.playing.lock().unwrap_or_else(PoisonError::into_inner);
        // Os que já acabaram saem da tabela aqui: sem isto ficariam zumbis.
        playing.retain(|_, child| matches!(child.try_wait(), Ok(None)));
        if let Some(mut previous) = playing.remove(name) {
            let _ = previous.kill();
            let _ = previous.wait();
        }
        match spawn_player(&file, volume.clamp(0.0, 1.0)) {
            Some(child) => {
                playing.insert(name.to_string(), child);
            }
            None => log!("atenção: sem paplay nem pw-play, o som \"{name}\" não tocou"),
        }
        Ok(())
    }
}

/// O alerta do sistema: o `bell` do tema, quando há.
pub(in crate::notifier) fn beep() {
    static BELL: std::sync::OnceLock<Sounds> = std::sync::OnceLock::new();
    let _ = BELL.get_or_init(Sounds::default).play("bell", 1.0);
}

/// `XDG_DATA_HOME` (ou `~/.local/share`) antes de `XDG_DATA_DIRS`: o som que
/// o usuário pôs ganha do que veio com o sistema, como no macOS.
fn data_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    match env::var_os("XDG_DATA_HOME").filter(|v| !v.is_empty()) {
        Some(home) => dirs.push(PathBuf::from(home)),
        None => {
            if let Some(home) = env::var_os("HOME") {
                dirs.push(Path::new(&home).join(".local/share"));
            }
        }
    }
    let system = env::var("XDG_DATA_DIRS")
        .ok()
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| "/usr/local/share:/usr/share".to_owned());
    dirs.extend(
        system
            .split(':')
            .filter(|d| !d.is_empty())
            .map(PathBuf::from),
    );
    dirs
}

fn find(name: &str, data_dirs: &[PathBuf]) -> Option<PathBuf> {
    // Nome com barra sairia da pasta de sons.
    if name.contains('/') {
        return None;
    }
    let lookup = |name: &str| {
        data_dirs.iter().find_map(|dir| {
            let sounds = dir.join("sounds");
            [sounds.clone(), sounds.join("freedesktop/stereo")]
                .into_iter()
                .flat_map(|folder| EXTENSIONS.map(|ext| folder.join(format!("{name}.{ext}"))))
                .find(|file| file.is_file())
        })
    };
    lookup(name).or_else(|| {
        MACOS_SOUNDS
            .contains(&name)
            .then(|| lookup(MACOS_STAND_IN))
            .flatten()
    })
}

fn spawn_player(file: &Path, volume: f64) -> Option<Child> {
    let quiet = |mut command: Command| {
        command
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .ok()
    };
    // `paplay` mede o volume de 0 a 65536; `pw-play`, de 0 a 1.
    let mut paplay = Command::new("paplay");
    paplay
        .arg(format!("--volume={}", (volume * 65536.0).round() as u32))
        .arg(file);
    quiet(paplay).or_else(|| {
        let mut pw_play = Command::new("pw-play");
        pw_play.arg(format!("--volume={volume}")).arg(file);
        quiet(pw_play)
    })
}

#[cfg(test)]
mod tests {
    use std::fs;

    use super::*;

    fn theme(root: &Path, files: &[&str]) -> std::io::Result<()> {
        for file in files {
            let path = root.join(file);
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent)?;
            }
            fs::write(path, b"")?;
        }
        Ok(())
    }

    #[test]
    fn o_som_do_usuario_ganha_do_tema_do_sistema() -> std::io::Result<()> {
        let dir = tempfile::tempdir()?;
        let (user, system) = (dir.path().join("user"), dir.path().join("system"));
        theme(&user, &["sounds/aviso.wav"])?;
        theme(&system, &["sounds/freedesktop/stereo/aviso.oga"])?;
        let dirs = [user.clone(), system.clone()];
        assert_eq!(find("aviso", &dirs), Some(user.join("sounds/aviso.wav")));
        assert_eq!(
            find("aviso", &dirs[1..]),
            Some(system.join("sounds/freedesktop/stereo/aviso.oga"))
        );
        Ok(())
    }

    #[test]
    fn som_do_macos_toca_o_aviso_curto_e_nome_desconhecido_nao_toca() -> std::io::Result<()> {
        let dir = tempfile::tempdir()?;
        theme(dir.path(), &["sounds/freedesktop/stereo/message.oga"])?;
        let dirs = [dir.path().to_path_buf()];
        let message = Some(dir.path().join("sounds/freedesktop/stereo/message.oga"));
        assert_eq!(find("Tink", &dirs), message);
        assert_eq!(find("Glass", &dirs), message);
        assert_eq!(find("Som Que Nao Existe", &dirs), None);
        assert_eq!(find("../stereo/message", &dirs), None);
        Ok(())
    }

    #[test]
    fn nome_vazio_ou_volume_zero_nao_tocam_e_nao_sao_erro() {
        let sounds = Sounds::default();
        assert_eq!(sounds.play("", 1.0), Ok(()));
        assert_eq!(sounds.play("Som Que Nao Existe", 0.0), Ok(()));
        assert_eq!(
            sounds.play("Som Que Nao Existe", 1.0),
            Err(SoundError::Unknown("Som Que Nao Existe".into()))
        );
    }
}
