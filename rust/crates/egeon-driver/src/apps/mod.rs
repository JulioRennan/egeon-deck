//! Apps abertos, sockets e containers: implementa `ports::procs::AppDriver`.

use std::ffi::OsStr;
use std::path::Path;
use std::process::{Command, Stdio};

use egeon_core::ports::procs::{AppDriver, RunningApp, SocketLinks};

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
use macos as platform;
#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "linux")]
use linux as platform;
#[cfg(windows)]
mod windows;
#[cfg(windows)]
use windows as platform;

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
        platform::socket_links()
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

// O `docker` falso é um script de shell.
#[cfg(all(test, unix))]
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
}
