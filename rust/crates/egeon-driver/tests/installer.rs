//! Troca do app, tudo numa pasta temporária: nada aqui instala nem troca o
//! app em `/Applications`.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use egeon_core::ports::installer::{AppInstaller, InstallError, Swap, UnpackedApp};
use egeon_driver::SystemInstaller;

const BUNDLE_ID: &str = "dev.teste.egeon";

fn tool(program: &str, args: &[&Path]) -> Result<(), String> {
    let status = Command::new(program)
        .args(args)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|e| e.to_string())?;
    status
        .success()
        .then_some(())
        .ok_or(format!("{program} falhou"))
}

fn codesign(app: &Path) -> Result<(), String> {
    let status = Command::new("/usr/bin/codesign")
        .args(["--force", "--sign", "-"])
        .arg(app)
        .stderr(Stdio::null())
        .status()
        .map_err(|e| e.to_string())?;
    status
        .success()
        .then_some(())
        .ok_or("codesign falhou".into())
}

fn make_app(at: &Path, version: &str, id: &str, sign: bool) -> Result<(), String> {
    let macos = at.join("Contents/MacOS");
    fs::create_dir_all(&macos).map_err(|e| e.to_string())?;
    fs::copy("/usr/bin/true", macos.join("EgeonDeck")).map_err(|e| e.to_string())?;
    let info = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>{id}</string>
<key>CFBundleShortVersionString</key><string>{version}</string>
<key>CFBundleExecutable</key><string>EgeonDeck</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>"#
    );
    fs::write(at.join("Contents/Info.plist"), info).map_err(|e| e.to_string())?;
    if sign { codesign(at) } else { Ok(()) }
}

fn make_zip(
    root: &Path,
    name: &str,
    apps: &[(&str, &str)],
    tamper: bool,
) -> Result<PathBuf, String> {
    let folder = root.join(format!("pacote-{name}"));
    fs::create_dir_all(&folder).map_err(|e| e.to_string())?;
    for (app, version) in apps {
        let path = folder.join(app);
        make_app(&path, version, BUNDLE_ID, true)?;
        if tamper {
            fs::write(path.join("Contents/MacOS/EgeonDeck"), "adulterado")
                .map_err(|e| e.to_string())?;
        }
    }
    let zip = root.join(format!("{name}.zip"));
    let sources: Vec<PathBuf> = apps.iter().map(|(app, _)| folder.join(app)).collect();
    if let [only] = sources.as_slice() {
        tool(
            "/usr/bin/ditto",
            &[
                Path::new("-c"),
                Path::new("-k"),
                Path::new("--keepParent"),
                only,
                &zip,
            ],
        )?;
    } else {
        tool(
            "/usr/bin/ditto",
            &[Path::new("-c"), Path::new("-k"), &folder, &zip],
        )?;
    }
    Ok(zip)
}

fn unpack(zip: &Path, root: &Path) -> Result<UnpackedApp, InstallError> {
    let into = root.join("x");
    SystemInstaller.unpack(zip, &into)
}

#[test]
fn desempacota_o_app_e_le_identificador_e_versao() -> Result<(), String> {
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    let zip = make_zip(root.path(), "um", &[("EgeonDeck.app", "1.7.0")], false)?;
    let app = unpack(&zip, root.path()).map_err(|e| e.to_string())?;
    assert_eq!(app.bundle_id, BUNDLE_ID);
    assert_eq!(app.version, "1.7.0");
    assert_eq!(
        app.path.file_name().and_then(|n| n.to_str()),
        Some("EgeonDeck.app")
    );
    Ok(())
}

#[test]
fn zip_que_nao_e_zip_ou_sem_um_so_app_nao_serve() -> Result<(), String> {
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    let garbage = root.path().join("lixo.zip");
    fs::write(&garbage, "isto não é um zip").map_err(|e| e.to_string())?;
    assert!(matches!(
        unpack(&garbage, root.path()),
        Err(InstallError::NotInstallable(_))
    ));

    let two = make_zip(
        root.path(),
        "dois",
        &[("A.app", "1.0.0"), ("B.app", "1.0.0")],
        false,
    )?;
    assert!(matches!(
        SystemInstaller.unpack(&two, &root.path().join("y")),
        Err(InstallError::NotInstallable(_))
    ));
    Ok(())
}

#[test]
fn prepara_o_app_assinado_ao_lado_do_destino() -> Result<(), String> {
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    let zip = make_zip(root.path(), "bom", &[("EgeonDeck.app", "1.7.0")], false)?;
    let app = unpack(&zip, root.path()).map_err(|e| e.to_string())?;
    let staged = root.path().join("Egeon Deck.app.novo");
    SystemInstaller
        .stage(&app, &staged)
        .map_err(|e| e.to_string())?;
    tool(
        "/usr/bin/codesign",
        &[
            Path::new("--verify"),
            Path::new("--deep"),
            Path::new("--strict"),
            &staged,
        ],
    )
}

#[test]
fn app_adulterado_nao_chega_ao_destino() -> Result<(), String> {
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    let zip = make_zip(root.path(), "ruim", &[("EgeonDeck.app", "1.7.0")], true)?;
    let app = unpack(&zip, root.path()).map_err(|e| e.to_string())?;
    let staged = root.path().join("Egeon Deck.app.novo");
    assert!(matches!(
        SystemInstaller.stage(&app, &staged),
        Err(InstallError::BadCodeSignature)
    ));
    assert!(!staged.exists());
    Ok(())
}

#[test]
fn sem_escrita_ao_lado_do_destino_o_app_novo_nao_e_copiado() -> Result<(), String> {
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    let zip = make_zip(root.path(), "bom", &[("EgeonDeck.app", "1.7.0")], false)?;
    let app = unpack(&zip, root.path()).map_err(|e| e.to_string())?;
    let locked = root.path().join("travada");
    fs::create_dir(&locked).map_err(|e| e.to_string())?;
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o555)).map_err(|e| e.to_string())?;
    let result = SystemInstaller.stage(&app, &locked.join("Egeon Deck.app.novo"));
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())?;
    assert!(matches!(result, Err(InstallError::CannotWrite(folder)) if folder == locked));
    Ok(())
}

#[test]
fn app_translocado_ou_em_pasta_sem_escrita_nao_se_troca() -> Result<(), String> {
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    assert!(SystemInstaller.can_install(&root.path().join("Egeon Deck.app")));
    assert!(!SystemInstaller.can_install(Path::new(
        "/private/var/folders/x/AppTranslocation/ABC/d/Egeon Deck.app"
    )));
    assert!(!SystemInstaller.can_install(&root.path().join("nao-existe/Egeon Deck.app")));

    let locked = root.path().join("travada");
    fs::create_dir(&locked).map_err(|e| e.to_string())?;
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o555)).map_err(|e| e.to_string())?;
    let writable = SystemInstaller.can_install(&locked.join("Egeon Deck.app"));
    fs::set_permissions(&locked, fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())?;
    assert!(!writable);
    Ok(())
}

fn version_of(app: &Path) -> Option<String> {
    let info = plist_text(&app.join("Contents/Info.plist"))?;
    let after = info
        .split("<key>CFBundleShortVersionString</key><string>")
        .nth(1)?;
    Some(after.split('<').next()?.to_string())
}

fn plist_text(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok()
}

/// Espera o log da troca dizer que acabou.
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

fn two_bundles(root: &Path) -> Result<(PathBuf, PathBuf), String> {
    let destination = root.join("Egeon Deck.app");
    let staged = root.join("Egeon Deck.app.novo");
    make_app(&destination, "1.6.0", BUNDLE_ID, false)?;
    make_app(&staged, "1.7.0", BUNDLE_ID, false)?;
    Ok((destination, staged))
}

#[test]
fn troca_o_bundle_e_nao_deixa_nada_para_tras() -> Result<(), String> {
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    let (destination, staged) = two_bundles(root.path())?;
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

    assert_eq!(version_of(&destination).as_deref(), Some("1.7.0"));
    let left: Vec<String> = fs::read_dir(root.path())
        .map_err(|e| e.to_string())?
        .filter_map(Result::ok)
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|name| name.contains(".novo") || name.contains(".antigo"))
        .collect();
    assert!(left.is_empty(), "sobrou {left:?}");
    Ok(())
}

#[test]
fn a_troca_espera_o_app_sair() -> Result<(), String> {
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    let (destination, staged) = two_bundles(root.path())?;
    let log = root.path().join("troca.log");
    let mut holder = Command::new("/bin/sleep")
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
        Some("1.6.0"),
        "trocou com o app ainda de pé"
    );
    holder.wait().map_err(|e| e.to_string())?;
    wait_for_log(&log, "atualizado:")?;
    assert_eq!(version_of(&destination).as_deref(), Some("1.7.0"));
    Ok(())
}
