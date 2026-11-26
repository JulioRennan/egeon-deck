//! A troca do AppImage, tudo numa pasta temporária. O AppImage é um script que
//! imita o `--appimage-extract` do runtime: nada aqui monta nem abre app.
#![cfg(target_os = "linux")]

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant};

use egeon_core::ports::installer::{AppInstaller, InstallError, Swap};
use egeon_driver::SystemInstaller;

const BUNDLE_ID: &str = "dev.duckcoder.egeondeck.next";

/// Um AppImage falso: com `--appimage-extract`, escreve na pasta atual o
/// `squashfs-root` com os `.desktop` pedidos; sem argumento, diz a versão.
fn fake_appimage(path: &Path, version: &str, desktops: &[&str]) -> Result<(), String> {
    let mut script = String::from("#!/bin/sh\nif [ \"$1\" = --appimage-extract ]; then\n");
    script.push_str("  mkdir -p squashfs-root/usr/share/applications\n");
    for name in desktops {
        script.push_str(&format!(
            "  printf '[Desktop Entry]\\nName=Egeon Deck\\nX-AppImage-Version={version}\\n' \
             > squashfs-root/usr/share/applications/{name}.desktop\n  \
             ln -s usr/share/applications/{name}.desktop squashfs-root/{name}.desktop\n"
        ));
    }
    script.push_str(&format!("  exit 0\nfi\necho {version}\n"));
    fs::write(path, script).map_err(|e| e.to_string())?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())
}

/// Os testes rodam em threads: um `fork` de outro teste no meio da gravação
/// herda o fd de escrita, e o `exec` do script recém-gravado dá `ETXTBSY` até
/// esse filho fazer o dele.
fn version_of(app: &Path) -> Option<String> {
    for _ in 0..20 {
        match Command::new(app).output() {
            Ok(out) => return Some(String::from_utf8_lossy(&out.stdout).trim().to_string()),
            Err(e) if e.raw_os_error() == Some(libc::ETXTBSY) => {
                thread::sleep(Duration::from_millis(50));
            }
            Err(_) => return None,
        }
    }
    None
}

#[test]
fn le_identificador_e_versao_do_desktop_da_raiz() -> Result<(), String> {
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    let download = root.path().join("EgeonDeck-linux-x86_64.AppImage");
    fake_appimage(&download, "2.1.0", &[BUNDLE_ID])?;
    let app = SystemInstaller
        .unpack(&download, &root.path().join("x"))
        .map_err(|e| e.to_string())?;
    assert_eq!(app.bundle_id, BUNDLE_ID);
    assert_eq!(app.version, "2.1.0");
    assert!(app.path.starts_with(root.path().join("x")));
    assert_eq!(version_of(&app.path).as_deref(), Some("2.1.0"));
    Ok(())
}

#[test]
fn sem_um_desktop_so_na_raiz_nao_e_app() -> Result<(), String> {
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    for (name, desktops) in [("nenhum", vec![]), ("dois", vec!["a.b", "c.d"])] {
        let download = root.path().join(format!("{name}.AppImage"));
        fake_appimage(&download, "2.1.0", &desktops)?;
        let result = SystemInstaller.unpack(&download, &root.path().join(name));
        assert!(
            matches!(result, Err(InstallError::NotInstallable(_))),
            "{name}"
        );
    }
    Ok(())
}

#[test]
fn arquivo_que_nao_e_appimage_nao_e_app() -> Result<(), String> {
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    let download = root.path().join("lixo.AppImage");
    fs::write(&download, "não é executável").map_err(|e| e.to_string())?;
    let result = SystemInstaller.unpack(&download, &root.path().join("x"));
    assert!(matches!(result, Err(InstallError::NotInstallable(_))));
    Ok(())
}

#[test]
fn stage_copia_executavel_e_pasta_sem_escrita_e_erro() -> Result<(), String> {
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    let download = root.path().join("novo.AppImage");
    fake_appimage(&download, "2.1.0", &[BUNDLE_ID])?;
    let app = SystemInstaller
        .unpack(&download, &root.path().join("x"))
        .map_err(|e| e.to_string())?;
    let staged = root.path().join("EgeonDeck.AppImage.novo");
    SystemInstaller
        .stage(&app, &staged)
        .map_err(|e| e.to_string())?;
    assert_eq!(version_of(&staged).as_deref(), Some("2.1.0"));

    let locked = root.path().join("travada");
    fs::create_dir(&locked).map_err(|e| e.to_string())?;
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o555)).map_err(|e| e.to_string())?;
    let result = SystemInstaller.stage(&app, &locked.join("EgeonDeck.AppImage.novo"));
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())?;
    // Como root (o container) a pasta travada ainda se escreve.
    // SAFETY: `geteuid` não tem pré-condição.
    if unsafe { libc::geteuid() } != 0 {
        assert!(matches!(result, Err(InstallError::CannotWrite(folder)) if folder == locked));
    }
    Ok(())
}

#[test]
fn fora_de_um_appimage_nao_se_troca() -> Result<(), String> {
    // O executável de teste não roda de um AppImage, como no `.deb`.
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    let app = root.path().join("EgeonDeck-linux-x86_64.AppImage");
    fs::write(&app, "x").map_err(|e| e.to_string())?;
    if std::env::var_os("APPIMAGE").is_none() {
        assert!(!SystemInstaller.can_install(&app));
    }
    Ok(())
}

fn wait_for_log(log: &Path, needle: &str) -> Result<String, String> {
    let deadline = Instant::now() + Duration::from_secs(15);
    loop {
        let text = fs::read_to_string(log).unwrap_or_default();
        if text.contains(needle) {
            return Ok(text);
        }
        if Instant::now() > deadline {
            return Err(format!("esperava {needle:?} no log; veio {text:?}"));
        }
        thread::sleep(Duration::from_millis(50));
    }
}

fn two_appimages(root: &Path) -> Result<(PathBuf, PathBuf), String> {
    let destination = root.join("EgeonDeck-linux-x86_64.AppImage");
    let staged = root.join("EgeonDeck-linux-x86_64.AppImage.novo");
    fake_appimage(&destination, "2.0.0", &[BUNDLE_ID])?;
    fake_appimage(&staged, "2.1.0", &[BUNDLE_ID])?;
    Ok((destination, staged))
}

#[test]
fn troca_o_appimage_e_nao_deixa_nada_para_tras() -> Result<(), String> {
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    let (destination, staged) = two_appimages(root.path())?;
    let log = root.path().join("troca.log");
    // Pid que já não existe: a espera passa direto.
    SystemInstaller
        .launch_swap(Swap {
            app_pid: 999_999,
            staged: &staged,
            destination: &destination,
            reopen: false,
            log: &log,
        })
        .map_err(|e| e.to_string())?;
    wait_for_log(&log, "atualizado:")?;
    assert_eq!(version_of(&destination).as_deref(), Some("2.1.0"));
    assert!(!staged.exists());
    Ok(())
}

#[test]
fn a_troca_espera_o_app_sair() -> Result<(), String> {
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    let (destination, staged) = two_appimages(root.path())?;
    let log = root.path().join("troca.log");
    let mut holder = Command::new("sleep")
        .arg("1")
        .spawn()
        .map_err(|e| e.to_string())?;
    SystemInstaller
        .launch_swap(Swap {
            app_pid: holder.id(),
            staged: &staged,
            destination: &destination,
            reopen: false,
            log: &log,
        })
        .map_err(|e| e.to_string())?;
    thread::sleep(Duration::from_millis(400));
    assert_eq!(
        version_of(&destination).as_deref(),
        Some("2.0.0"),
        "trocou com o app ainda de pé"
    );
    holder.wait().map_err(|e| e.to_string())?;
    wait_for_log(&log, "atualizado:")?;
    assert_eq!(version_of(&destination).as_deref(), Some("2.1.0"));
    Ok(())
}

#[test]
fn sem_o_novo_o_antigo_fica() -> Result<(), String> {
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    let (destination, _) = two_appimages(root.path())?;
    let log = root.path().join("troca.log");
    SystemInstaller
        .launch_swap(Swap {
            app_pid: 999_999,
            staged: &root.path().join("nao-existe.novo"),
            destination: &destination,
            reopen: false,
            log: &log,
        })
        .map_err(|e| e.to_string())?;
    wait_for_log(&log, "o atual ficou")?;
    assert_eq!(version_of(&destination).as_deref(), Some("2.0.0"));
    Ok(())
}
