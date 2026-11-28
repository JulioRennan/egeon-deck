//! A troca de um bundle `.app`: `ditto` e `codesign` do sistema e um script
//! que roda depois que o app sai.

use std::ffi::{CString, OsStr};
use std::fs::{self, File};
use std::io;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

use egeon_core::ports::installer::{InstallError, Swap, UnpackedApp};

const DITTO: &str = "/usr/bin/ditto";
const CODESIGN: &str = "/usr/bin/codesign";

/// Argumentos: pid do app, bundle novo, destino, `1` para reabrir.
///
/// Precisa ser outro processo: o app não se substitui estando de pé. A troca
/// são dois `mv` no mesmo volume, como no `install.sh`, e por isso o novo já
/// espera ao lado do destino; se o segundo falhar, o antigo volta.
const SWAP_SCRIPT: &str = r#"#!/bin/sh
pid="$1"; novo="$2"; destino="$3"; reabrir="$4"
antigo="$destino.antigo"
tentativas=0
while kill -0 "$pid" 2>/dev/null; do
  tentativas=$((tentativas + 1))
  if [ "$tentativas" -gt 300 ]; then echo "o app não saiu; troca cancelada"; exit 1; fi
  sleep 0.2
done
rm -rf "$antigo"
if ! mv "$destino" "$antigo"; then echo "não movi o bundle atual"; exit 1; fi
if ! mv "$novo" "$destino"; then
  mv "$antigo" "$destino"
  echo "não movi o bundle novo; o atual voltou"
  exit 1
fi
rm -rf "$antigo"
xattr -dr com.apple.quarantine "$destino" 2>/dev/null
echo "atualizado: $destino"
if [ "$reabrir" = 1 ]; then open "$destino"; fi
"#;

pub(super) fn can_install(destination: &Path) -> bool {
    if destination.to_string_lossy().contains("/AppTranslocation/") {
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

pub(super) fn unpack(zip: &Path, into: &Path) -> Result<UnpackedApp, InstallError> {
    // `ditto`, e não unzip: preserva a assinatura de código do bundle.
    let extracted = succeeds(
        DITTO,
        &[
            OsStr::new("-x"),
            OsStr::new("-k"),
            zip.as_os_str(),
            into.as_os_str(),
        ],
    );
    if !extracted {
        return Err(InstallError::NotInstallable("não descompactou".into()));
    }
    let mut apps: Vec<PathBuf> = fs::read_dir(into)
        .map(|entries| {
            entries
                .filter_map(Result::ok)
                .map(|entry| entry.path())
                .filter(|path| path.extension().is_some_and(|e| e == "app"))
                .collect()
        })
        .unwrap_or_default();
    let (Some(path), true) = (apps.pop(), apps.is_empty()) else {
        return Err(no_bundle());
    };
    let info =
        plist::Value::from_file(path.join("Contents/Info.plist")).map_err(|_| no_bundle())?;
    let text = |key: &str| {
        info.as_dictionary()
            .and_then(|d| d.get(key))
            .and_then(plist::Value::as_string)
            .map(str::to_string)
    };
    match (
        text("CFBundleIdentifier"),
        text("CFBundleShortVersionString"),
    ) {
        (Some(bundle_id), Some(version)) => Ok(UnpackedApp {
            path,
            bundle_id,
            version,
        }),
        _ => Err(no_bundle()),
    }
}

fn no_bundle() -> InstallError {
    InstallError::NotInstallable("sem bundle dentro".into())
}

pub(super) fn stage(app: &UnpackedApp, staged: &Path) -> Result<(), InstallError> {
    let verified = succeeds(
        CODESIGN,
        &[
            OsStr::new("--verify"),
            OsStr::new("--deep"),
            OsStr::new("--strict"),
            app.path.as_os_str(),
        ],
    );
    if !verified {
        return Err(InstallError::BadCodeSignature);
    }
    if !succeeds(DITTO, &[app.path.as_os_str(), staged.as_os_str()]) {
        let folder = staged.parent().unwrap_or(staged).to_path_buf();
        return Err(InstallError::CannotWrite(folder));
    }
    Ok(())
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

/// A ferramenta do sistema, sem saída, e se ela terminou bem.
fn succeeds(program: &str, args: &[&OsStr]) -> bool {
    Command::new(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|status| status.success())
}
