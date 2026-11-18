//! Apps abertos, sockets e containers: implementa `ports::procs::AppDriver`.

use std::ffi::OsStr;
use std::path::Path;
use std::process::{Command, Stdio};

use egeon_core::ports::procs::{AppDriver, RunningApp, SocketLinks};

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
use macos as platform;

/// O driver de apps do sistema em que o programa roda.
#[derive(Debug, Clone, Copy, Default)]
pub struct SystemApps;

impl AppDriver for SystemApps {
    fn running_apps(&self) -> Vec<RunningApp> {
        platform::running_apps()
    }

    fn request_quit(&self, pid: u32) {
        platform::request_quit(pid);
    }

    fn socket_links(&self) -> Option<SocketLinks> {
        let output = run(Path::new(platform::LSOF), &["-U", "-F", "pdn"], false)?;
        Some(parse_lsof(&output))
    }

    fn container_working_dirs(&self) -> Option<Vec<String>> {
        container_dirs(Path::new(platform::DOCKER))
    }
}

/// A saída de `docker ps`: uma linha por container, vazia quando ele não tem o
/// rótulo.
fn container_dirs(docker: &Path) -> Option<Vec<String>> {
    let output = run(
        docker,
        &[
            "ps",
            "--format",
            r#"{{.Label "com.docker.compose.project.working_dir"}}"#,
        ],
        true,
    )?;
    let mut lines: Vec<String> = output.split('\n').map(str::to_string).collect();
    if lines.last().is_some_and(String::is_empty) {
        lines.pop();
    }
    Some(lines)
}

/// Os sockets unix de cada processo, da saída `lsof -U -F pdn`: o endereço do
/// próprio socket (`d`) e, se conectado, o do outro lado (`n->0x…`).
fn parse_lsof(output: &str) -> SocketLinks {
    let mut links = SocketLinks::default();
    let mut pid = 0;
    for line in output.split('\n') {
        let Some(tag) = line.chars().next() else {
            continue;
        };
        let value = &line[tag.len_utf8()..];
        match tag {
            'p' => pid = value.parse().unwrap_or(0),
            'd' => {
                links.own.entry(pid).or_default().insert(value.to_string());
            }
            'n' if value.starts_with("->0x") => {
                links
                    .peers
                    .entry(pid)
                    .or_default()
                    .insert(value[2..].to_string());
            }
            _ => {}
        }
    }
    links
}

/// Roda a ferramenta e devolve a saída. `None` se ela não abre — e, com
/// `require_success`, se sai com erro.
fn run(program: &Path, args: &[&str], require_success: bool) -> Option<String> {
    let output = Command::new(program)
        .args(args.iter().map(OsStr::new))
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if require_success && !output.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&output.stdout).into_owned())
}

#[cfg(test)]
mod tests {
    use std::os::unix::fs::PermissionsExt;

    use super::*;

    /// O `docker` do macOS fica num caminho fixo; aqui ele é um script que
    /// imita a saída dele.
    fn fake_docker(body: &str) -> Result<Option<Vec<String>>, String> {
        let dir = tempfile::tempdir().map_err(|e| e.to_string())?;
        let script = dir.path().join("docker");
        std::fs::write(&script, format!("#!/bin/sh\n{body}\n")).map_err(|e| e.to_string())?;
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755))
            .map_err(|e| e.to_string())?;
        Ok(container_dirs(&script))
    }

    #[test]
    fn containers_sem_rotulo_contam_como_linha_vazia() -> Result<(), String> {
        let dirs = fake_docker("printf '/p/a\\n\\n/p/b\\n'")?;
        assert_eq!(dirs, Some(["/p/a", "", "/p/b"].map(String::from).to_vec()));
        Ok(())
    }

    #[test]
    fn docker_que_nao_responde_e_desconhecido() -> Result<(), String> {
        assert_eq!(fake_docker("exit 1")?, None);
        assert_eq!(container_dirs(Path::new("/nao/existe/docker")), None);
        Ok(())
    }

    #[test]
    fn lsof_liga_cada_socket_ao_processo_dono() {
        let lsof = "p10\nf3\nd0xaaa\nn/tmp/s.sock\nf4\nd0xbbb\nn->0xccc\n\
                    p20\nf5\nd0xccc\nn/tmp/s.sock\np30\nf3\nd0xddd\nn->0xeee\n";
        let links = parse_lsof(lsof);
        assert_eq!(links.own[&10].len(), 2);
        assert!(links.peers[&10].contains("0xccc"));
        assert!(links.own[&20].contains("0xccc"));
        assert!(!links.peers.contains_key(&20));
        assert!(links.peers[&30].contains("0xeee"));
    }
}
