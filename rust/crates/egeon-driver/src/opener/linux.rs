//! `xdg-open`, o abridor do freedesktop, e o som `bell` do tema de sons.

use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Command, Stdio};
use std::thread;

use egeon_core::log;
use egeon_core::ports::opener::OpenTarget;

use super::url::{scheme_of, url_of};

const XDG_OPEN: &str = "xdg-open";
const XDG_MIME: &str = "xdg-mime";

/// O `xdg-open` pode ficar de pé enquanto o app aberto roda (quando cai num
/// programa de terminal): o core chama da tarefa dona do estado, então ele é
/// solto em vez de esperado. O que dá para saber antes — arquivo que sumiu,
/// texto que não é URL, esquema sem quem o trate — devolve `false` aqui.
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
            if !has_handler(Path::new(XDG_MIME), scheme_of(&url)) {
                return false;
            }
            url.into()
        }
    };
    let spawned = Command::new(XDG_OPEN)
        .arg(&argument)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        // Fora do grupo do app: o `killpg` que o encerra não leva junto o app
        // que o usuário abriu.
        .process_group(0)
        .spawn();
    let mut child = match spawned {
        Ok(child) => child,
        Err(error) => {
            log!("abrir: xdg-open não rodou — {error}");
            return false;
        }
    };
    // Sem quem espere, o `xdg-open` vira zumbi até o app sair.
    let reaper = thread::Builder::new()
        .name("xdg-open".into())
        .spawn(move || match child.wait() {
            Ok(status) if !status.success() => log!("abrir: xdg-open saiu com {status}"),
            _ => {}
        });
    if let Err(error) = reaper {
        log!("abrir: sem thread para esperar o xdg-open — {error}");
    }
    true
}

/// Web e arquivo sempre têm quem abra numa sessão gráfica; para o resto, o
/// `xdg-mime` diz se algum app se registrou para o esquema.
fn has_handler(xdg_mime: &Path, scheme: &str) -> bool {
    let scheme = scheme.to_ascii_lowercase();
    if matches!(scheme.as_str(), "http" | "https" | "file") {
        return true;
    }
    Command::new(xdg_mime)
        .args(["query", "default", &format!("x-scheme-handler/{scheme}")])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .is_ok_and(|out| out.status.success() && !out.stdout.trim_ascii().is_empty())
}

pub(super) fn beep() {
    crate::notifier::beep();
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    use super::*;

    #[test]
    fn esquema_sem_app_registrado_nao_tem_quem_abra() -> std::io::Result<()> {
        let dir = tempfile::tempdir()?;
        let script = dir.path().join("xdg-mime");
        // Imita o `xdg-mime`: só conhece o `slack`.
        fs::write(
            &script,
            "#!/bin/sh\n[ \"$3\" = x-scheme-handler/slack ] && echo slack.desktop\nexit 0\n",
        )?;
        fs::set_permissions(&script, fs::Permissions::from_mode(0o755))?;
        assert!(has_handler(&script, "slack"));
        assert!(!has_handler(&script, "egeon-esquema-que-ninguem-trata"));
        assert!(has_handler(&script, "HTTPS"));
        assert!(!has_handler(Path::new("/nao/existe/xdg-mime"), "slack"));
        Ok(())
    }

    #[test]
    fn arquivo_que_nao_existe_nao_abre_e_nao_roda_nada() {
        let path = std::path::PathBuf::from("/tmp/egeon-nao-existe-e2e/nada.txt");
        assert!(!open(&OpenTarget::File(path)));
        assert!(!open(&OpenTarget::Url("isto nao e url".into())));
    }
}
