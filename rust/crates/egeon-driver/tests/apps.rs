//! Apps, sockets e containers de verdade, sem abrir nem fechar app nenhum do
//! usuário.

use std::collections::HashSet;
use std::fs;
use std::path::Path;
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use egeon_core::ports::procs::{AppDriver, SocketLinks};
use egeon_driver::SystemApps;

#[test]
fn lista_os_apps_abertos_com_bundle_e_pid() {
    let apps = SystemApps.running_apps();
    assert!(!apps.is_empty());
    assert!(apps.iter().all(|a| a.pid > 0 && !a.bundle.is_empty()));
    assert!(apps.iter().any(|a| a.bundle == "com.apple.finder"));
}

#[test]
fn pedir_saida_de_quem_nao_e_app_nao_faz_nada() {
    // O executável de teste não tem bundle: não é um `NSRunningApplication`.
    SystemApps.request_quit(std::process::id());
    SystemApps.request_quit(u32::MAX);
    assert!(Command::new("/usr/bin/true").status().is_ok());
}

/// Quem se conecta ao socket de um processo aparece ligado a ele no `lsof`.
#[test]
fn cliente_conectado_ao_socket_aparece_ligado_ao_dono() -> Result<(), String> {
    let dir = tempfile::tempdir().map_err(|e| e.to_string())?;
    let path = dir.path().join("s.sock");
    let listener = std::os::unix::net::UnixListener::bind(&path).map_err(|e| e.to_string())?;
    let mut client = Command::new("/usr/bin/nc")
        .arg("-U")
        .arg(&path)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| e.to_string())?;
    let (_accepted, _) = listener.accept().map_err(|e| e.to_string())?;

    let me = HashSet::from([std::process::id()]);
    let candidate = HashSet::from([client.id()]);
    let deadline = Instant::now() + Duration::from_secs(10);
    let linked = loop {
        let links: SocketLinks = SystemApps.socket_links().ok_or("lsof não respondeu")?;
        let found = links.connected(&candidate, &me);
        if !found.is_empty() || Instant::now() > deadline {
            break found;
        }
        thread::sleep(Duration::from_millis(100));
    };
    let _ = client.kill();
    let _ = client.wait();
    assert_eq!(linked, candidate);
    Ok(())
}

#[test]
fn processo_que_nao_fala_com_o_socket_nao_aparece() -> Result<(), String> {
    let links = SystemApps.socket_links().ok_or("lsof não respondeu")?;
    let me = HashSet::from([std::process::id()]);
    let stranger = HashSet::from([1_u32]);
    assert!(links.connected(&stranger, &me).is_empty());
    Ok(())
}

/// Um app Cocoa mínimo (sem ícone nem janela) compilado na hora, numa pasta
/// temporária: o único jeito de provar a lista e o pedido de saída sem tocar
/// em app do usuário.
fn build_probe(root: &Path, bundle_id: &str) -> Result<std::path::PathBuf, String> {
    let app = root.join("Sonda.app");
    let macos = app.join("Contents/MacOS");
    fs::create_dir_all(&macos).map_err(|e| e.to_string())?;
    let source = root.join("sonda.m");
    fs::write(
        &source,
        "#import <Cocoa/Cocoa.h>\nint main(void) { @autoreleasepool { [NSApplication sharedApplication]; \
         [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory]; [NSApp run]; } return 0; }\n",
    )
    .map_err(|e| e.to_string())?;
    let status = Command::new("/usr/bin/clang")
        .args(["-fobjc-arc", "-framework", "Cocoa", "-o"])
        .arg(macos.join("sonda"))
        .arg(&source)
        .status()
        .map_err(|e| e.to_string())?;
    if !status.success() {
        return Err("clang não compilou a sonda".into());
    }
    fs::write(
        app.join("Contents/Info.plist"),
        format!(
            r#"<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>{bundle_id}</string>
<key>CFBundleExecutable</key><string>sonda</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>"#
        ),
    )
    .map_err(|e| e.to_string())?;
    Ok(app)
}

fn wait_for<T>(what: &str, mut probe: impl FnMut() -> Option<T>) -> Result<T, String> {
    let deadline = Instant::now() + Duration::from_secs(20);
    loop {
        if let Some(found) = probe() {
            return Ok(found);
        }
        if Instant::now() > deadline {
            return Err(format!("esperava {what}"));
        }
        thread::sleep(Duration::from_millis(100));
    }
}

/// Mata a sonda pelo caminho do bundle ao sair do teste, mesmo se ela abriu e
/// não chegou a aparecer na lista.
struct Reaper(std::path::PathBuf);

impl Drop for Reaper {
    fn drop(&mut self) {
        let _ = Command::new("/usr/bin/pkill")
            .arg("-f")
            .arg(self.0.join("Contents/MacOS/sonda"))
            .status();
    }
}

/// A lista tem de acompanhar o sistema a partir de uma thread de fundo (que é
/// de onde o core chama), e não congelar na primeira leitura.
#[test]
#[ignore = "abre um app na tela do usuário; rodar com --ignored"]
fn app_aberto_aparece_na_lista_o_pedido_o_fecha_e_ele_some() -> Result<(), String> {
    let root = tempfile::tempdir().map_err(|e| e.to_string())?;
    let bundle_id = format!("dev.teste.sonda{}", std::process::id());
    let app = build_probe(root.path(), &bundle_id)?;
    let _reaper = Reaper(app.clone());
    // Primeira leitura antes de abrir: é a foto que uma lista congelada manteria.
    let before = SystemApps.running_apps();
    assert!(before.iter().all(|a| a.bundle != bundle_id));

    let opened = Command::new("/usr/bin/open")
        .args(["-g", "-n"])
        .arg(&app)
        .status()
        .map_err(|e| e.to_string())?;
    assert!(opened.success());

    let pid = wait_for("a sonda na lista", || {
        SystemApps
            .running_apps()
            .into_iter()
            .find(|a| a.bundle == bundle_id)
            .map(|a| a.pid)
    })?;
    SystemApps.request_quit(pid);
    wait_for("a sonda sair da lista", || {
        SystemApps
            .running_apps()
            .iter()
            .all(|a| a.bundle != bundle_id)
            .then_some(())
    })
    .inspect_err(|_| {
        // SAFETY: pid de uma sonda nossa que não quis sair; `kill` só lê os inteiros.
        unsafe { libc::kill(pid as i32, libc::SIGKILL) };
    })
}
