//! A troca do AppImage: o arquivo apontado por `$APPIMAGE`, trocado por um
//! script que roda depois que o app sai.
//!
//! O `.deb` não se troca sozinho: instalado pelo gerenciador de pacotes, não
//! tem `$APPIMAGE`, e `can_install` diz que não.
//!
//! Não há assinatura de código no Linux. A confiança no arquivo baixado é toda
//! do Ed25519 que o core confere antes de chamar `unpack`.

use std::ffi::{CString, OsStr, OsString};
use std::fs::{self, File};
use std::io;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use egeon_core::ports::installer::{InstallError, Swap, UnpackedApp};

/// Argumentos: pid do app, AppImage novo, destino, `1` para reabrir.
///
/// Um arquivo só, na mesma pasta: o `mv` é um `rename` atômico por cima do
/// antigo, e nunca há um instante sem app no lugar. Se falhar, o antigo fica.
/// O app que ainda roda não sente: o AppImage montado segura o arquivo velho.
const SWAP_SCRIPT: &str = r#"#!/bin/sh
pid="$1"; novo="$2"; destino="$3"; reabrir="$4"
# O script mora no temp: some ao sair, dê certo ou não.
trap 'rm -f "$0"' EXIT
tentativas=0
while kill -0 "$pid" 2>/dev/null; do
  tentativas=$((tentativas + 1))
  if [ "$tentativas" -gt 300 ]; then echo "o app não saiu; troca cancelada"; exit 1; fi
  sleep 0.2
done
if ! mv -f "$novo" "$destino"; then echo "não movi o AppImage novo; o atual ficou"; exit 1; fi
echo "atualizado: $destino"
if [ "$reabrir" = 1 ]; then
  # Sem o que o AppImage velho deixou no ambiente: o novo monta e define o dele.
  setsid env -u APPIMAGE -u APPDIR -u ARGV0 -u OWD "$destino" >/dev/null 2>&1 < /dev/null &
fi
"#;

/// A chave do `.desktop` com a versão, que o empacotamento escreve.
const VERSION_KEY: &str = "X-AppImage-Version";

pub(super) fn can_install(destination: &Path) -> bool {
    can_install_with(destination, std::env::var_os("APPIMAGE").as_deref())
}

/// Só o AppImage que está rodando: o destino tem de ser o `$APPIMAGE`, e a
/// pasta dele, gravável.
fn can_install_with(destination: &Path, appimage: Option<&OsStr>) -> bool {
    if appimage.map(Path::new) != Some(destination) || !destination.is_file() {
        return false;
    }
    let Some(parent) = destination.parent() else {
        return false;
    };
    let Ok(parent) = CString::new(parent.as_os_str().as_bytes()) else {
        return false;
    };
    // SAFETY: `parent` é uma string C válida durante a chamada.
    unsafe { libc::access(parent.as_ptr(), libc::W_OK) == 0 }
}

/// O "zip" é o próprio AppImage. O identificador e a versão vêm do `.desktop`
/// da raiz dele: o nome do arquivo é o identificador, e a versão é a chave
/// `X-AppImage-Version`.
pub(super) fn unpack(appimage: &Path, into: &Path) -> Result<UnpackedApp, InstallError> {
    fs::create_dir_all(into).map_err(|_| not_installable("sem pasta de trabalho"))?;
    let name = appimage
        .file_name()
        .map_or_else(|| OsString::from("app.AppImage"), OsStr::to_owned);
    let path = into.join(name);
    fs::copy(appimage, &path).map_err(|_| not_installable("não copiei o AppImage"))?;
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755))
        .map_err(|_| not_installable("não copiei o AppImage"))?;
    // Roda o arquivo baixado: o runtime do AppImage é que sabe abrir o
    // squashfs, e a assinatura já foi conferida. `--appimage-extract` não
    // monta nada nem precisa de FUSE.
    let extracted = status_when_free(|| {
        let mut command = Command::new(&path);
        command
            .args(["--appimage-extract", "*.desktop"])
            .current_dir(into)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        command
    })
    .is_ok_and(|status| status.success());
    if !extracted {
        return Err(not_installable("não abriu o AppImage"));
    }
    let (bundle_id, version) = read_desktop(&into.join("squashfs-root")).ok_or_else(no_bundle)?;
    Ok(UnpackedApp {
        path,
        bundle_id,
        version,
    })
}

/// Roda, esperando o arquivo soltar. Recém-copiado, o executável recusa o
/// `exec` com `ETXTBSY` enquanto algum processo filho criado no meio da cópia
/// (o core abre ptys o tempo todo) ainda segura o fd de escrita herdado: ele
/// fecha no `exec` desse filho, em milissegundos.
fn status_when_free(command: impl Fn() -> Command) -> io::Result<ExitStatus> {
    for _ in 0..BUSY_TRIES {
        match command().status() {
            Err(error) if error.raw_os_error() == Some(libc::ETXTBSY) => {
                thread::sleep(BUSY_WAIT);
            }
            other => return other,
        }
    }
    command().status()
}

const BUSY_TRIES: usize = 20;
const BUSY_WAIT: Duration = Duration::from_millis(50);

/// O único `.desktop` da raiz, como o `appimagetool` exige.
fn read_desktop(root: &Path) -> Option<(String, String)> {
    let mut desktops: Vec<PathBuf> = fs::read_dir(root)
        .ok()?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|e| e == "desktop"))
        .collect();
    let (Some(desktop), true) = (desktops.pop(), desktops.is_empty()) else {
        return None;
    };
    let bundle_id = desktop.file_stem()?.to_str()?.to_owned();
    let text = fs::read_to_string(&desktop).ok()?;
    Some((bundle_id, desktop_version(&text)?))
}

/// A chave dentro do grupo `[Desktop Entry]`: a mesma chave noutro grupo (uma
/// ação do menu) não conta.
fn desktop_version(text: &str) -> Option<String> {
    let mut in_entry = false;
    for line in text.lines().map(str::trim) {
        if line.starts_with('[') {
            in_entry = line == "[Desktop Entry]";
        } else if in_entry
            && let Some((key, value)) = line.split_once('=')
            && key.trim() == VERSION_KEY
        {
            let value = value.trim();
            return (!value.is_empty()).then(|| value.to_owned());
        }
    }
    None
}

fn not_installable(why: &str) -> InstallError {
    InstallError::NotInstallable(why.into())
}

fn no_bundle() -> InstallError {
    not_installable("sem .desktop com identificador e versão")
}

pub(super) fn stage(app: &UnpackedApp, staged: &Path) -> Result<(), InstallError> {
    let cannot_write = || {
        let folder = staged.parent().unwrap_or(staged).to_path_buf();
        InstallError::CannotWrite(folder)
    };
    fs::copy(&app.path, staged).map_err(|_| cannot_write())?;
    fs::set_permissions(staged, fs::Permissions::from_mode(0o755)).map_err(|_| cannot_write())
}

pub(super) fn launch_swap(swap: Swap<'_>) -> io::Result<()> {
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_nanos());
    let script =
        std::env::temp_dir().join(format!("egeon-update-{}-{stamp}.sh", std::process::id()));
    fs::write(&script, SWAP_SCRIPT)?;
    let log = File::create(swap.log)?;
    let mut child = Command::new("/bin/sh")
        .arg(&script)
        .arg(swap.app_pid.to_string())
        .arg(swap.staged)
        .arg(swap.destination)
        .arg(if swap.reopen { "1" } else { "0" })
        .stdin(Stdio::null())
        .stdout(log.try_clone()?)
        .stderr(log)
        // Fora do grupo do app: o `killpg` que o encerra não leva a troca junto.
        .process_group(0)
        .spawn()?;
    // Sem quem espere, o script vira zumbi até o app sair.
    thread::Builder::new()
        .name("troca-app".into())
        .spawn(move || {
            let _ = child.wait();
        })?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versao_e_a_chave_do_grupo_principal() {
        let desktop = "[Desktop Entry]\nName=Egeon Deck\nX-AppImage-Version = 2.1.0 \n\
                       [Desktop Action nova]\nX-AppImage-Version=9.9.9\n";
        assert_eq!(desktop_version(desktop).as_deref(), Some("2.1.0"));
        let only_action = "[Desktop Entry]\nName=x\n[Desktop Action a]\nX-AppImage-Version=1.0.0\n";
        assert_eq!(desktop_version(only_action), None);
        assert_eq!(
            desktop_version("[Desktop Entry]\nX-AppImage-Version=\n"),
            None
        );
    }

    #[test]
    fn o_script_da_troca_se_apaga_ao_sair_dando_certo_ou_nao() -> io::Result<()> {
        let dir = tempfile::tempdir()?;
        let destination = dir.path().join("app.AppImage");
        fs::write(&destination, "velho")?;
        for staged in [dir.path().join("novo"), dir.path().join("nao-existe")] {
            if staged.ends_with("novo") {
                fs::write(&staged, "novo")?;
            }
            let script = dir.path().join("troca.sh");
            fs::write(&script, SWAP_SCRIPT)?;
            let status = Command::new("/bin/sh")
                .arg(&script)
                .args(["999999".as_ref(), staged.as_os_str()])
                .arg(&destination)
                .arg("0")
                .stdout(Stdio::null())
                .status()?;
            assert!(!script.exists(), "sobrou o script (saída {status})");
        }
        assert_eq!(fs::read_to_string(&destination)?, "novo");
        Ok(())
    }

    #[test]
    fn so_se_troca_o_appimage_que_esta_rodando() -> io::Result<()> {
        let dir = tempfile::tempdir()?;
        let app = dir.path().join("EgeonDeck-linux-x86_64.AppImage");
        fs::write(&app, "x")?;
        assert!(can_install_with(&app, Some(app.as_os_str())));
        // O `.deb`: sem `$APPIMAGE`.
        assert!(!can_install_with(&app, None));
        // O executável de dentro da montagem não é o arquivo a trocar.
        let other = dir.path().join("outro.AppImage");
        assert!(!can_install_with(&app, Some(other.as_os_str())));
        let missing = dir.path().join("sumiu.AppImage");
        assert!(!can_install_with(&missing, Some(missing.as_os_str())));
        Ok(())
    }
}
