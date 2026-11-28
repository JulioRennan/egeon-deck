//! O fish de verdade (decisão 53): o agente sobe pelo fish de login, que monta o
//! PATH do `config.fish`, e a linha do Egeon (aspas, `||`) roda num `sh`.
//! A imagem de desenvolvimento não traz o fish:
//! `apt-get install -y fish && cargo test -p egeon-driver --test fish_shell -- --ignored`.
#![cfg(unix)]

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use egeon_core::features::terminal::shell::{LaunchShell, Role};
use egeon_core::ports::pty::{PtyDriver, PtyEvent, PtySize, PtySpec};
use egeon_driver::SystemPty;

const FISH: &str = "/usr/bin/fish";

fn write(path: &Path, body: &str, executable: bool) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    fs::write(path, body).map_err(|e| e.to_string())?;
    if executable {
        fs::set_permissions(path, fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tokio::test]
#[ignore = "precisa do fish instalado em /usr/bin/fish"]
async fn agente_no_fish_ve_o_path_do_config_fish_e_a_linha_roda_no_sh() -> Result<(), String> {
    let home = tempfile::tempdir().map_err(|e| e.to_string())?;
    let root = home.path();
    // O PATH que só o fish monta: o `sh -l` sozinho não o veria.
    write(
        &root.join(".config/fish/config.fish"),
        "set -gx PATH $HOME/fishbin $PATH\n",
        false,
    )?;
    write(
        &root.join("fishbin/claude"),
        "#!/bin/sh\necho claude-do-fish \"$@\"\n",
        true,
    )?;
    let launch = LaunchShell::new(PathBuf::from(FISH)).launch(
        root,
        Some("echo \"aspas-'simples'\"; false || claude --model 'opus'"),
        Role::Agent,
        &root.join("dados/bash"),
    );
    let child = SystemPty
        .spawn(PtySpec {
            program: launch.program,
            args: launch.args,
            env: vec![
                ("HOME".into(), root.display().to_string()),
                ("PATH".into(), "/usr/bin:/bin".into()),
                ("TERM".into(), "xterm-256color".into()),
            ],
            cwd: None,
            size: PtySize {
                cols: 200,
                rows: 50,
            },
        })
        .map_err(|e| e.to_string())?;
    let mut events = child.events;
    let mut output = String::new();
    let deadline = Instant::now() + Duration::from_secs(15);
    while !output.contains("claude-do-fish --model opus") {
        let left = deadline.saturating_duration_since(Instant::now());
        match tokio::time::timeout(left, events.recv()).await {
            Ok(Some(PtyEvent::Output(bytes))) => output.push_str(&String::from_utf8_lossy(&bytes)),
            _ => return Err(format!("o claude do fish não subiu; veio {output:?}")),
        }
    }
    assert!(output.contains("aspas-'simples'"), "{output}");
    Ok(())
}
