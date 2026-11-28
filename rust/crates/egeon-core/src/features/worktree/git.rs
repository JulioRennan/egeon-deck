//! Chamar o `git`, como o `Worktree.run` do Swift.
//!
//! O ambiente do filho entra de fora (o driver o monta: PATH do shell do usuário
//! e sem as variáveis do Claude Code); o core só o repassa.

use std::ffi::OsString;
use std::fs::File;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

use super::model::Failure;

#[derive(Debug, Clone)]
pub struct Git {
    env: Vec<(OsString, OsString)>,
}

fn scratch_file() -> PathBuf {
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    std::env::temp_dir().join(format!(
        "egeon-git-{}-{}",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ))
}

impl Git {
    /// `env` é o ambiente completo do filho; vazio é um filho sem ambiente.
    pub fn new(env: Vec<(OsString, OsString)>) -> Git {
        Git { env }
    }

    /// O ambiente deste processo, como está. Para teste e para quem não tem o
    /// do driver.
    pub fn inheriting() -> Git {
        Git {
            env: std::env::vars_os().collect(),
        }
    }

    /// O ambiente que os filhos recebem.
    pub fn env(&self) -> &[(OsString, OsString)] {
        &self.env
    }

    fn command(&self, args: &[&str], dir: &Path) -> Command {
        let mut command = Command::new("git");
        command
            .args(args)
            .current_dir(dir)
            .env_clear()
            .envs(self.env.iter().map(|(k, v)| (k, v)))
            .stdin(Stdio::null());
        command
    }

    /// Roda e devolve a saída (stdout e stderr juntos, como no Swift); status
    /// diferente de zero é [`Failure::Git`] com essa saída.
    ///
    /// A saída vai para um arquivo temporário, e não para um pipe: o Swift
    /// travava 2min30 num `git rev-parse` porque a ponta de escrita do pipe era
    /// herdada pela cópia de `node_modules` que rodava ao lado (ADR-017). O
    /// `fork` do Rust fecha o que não é do filho, mas o arquivo é o mesmo custo
    /// e não deixa dúvida.
    pub fn run(&self, args: &[&str], dir: &Path) -> Result<String, Failure> {
        let fail = |output: String| Failure::Git {
            command: args.join(" "),
            output,
        };
        let scratch = scratch_file();
        let sink = File::create(&scratch)
            .map_err(|_| fail(format!("não consegui abrir {}", scratch.display())))?;
        let clone = sink
            .try_clone()
            .map_err(|e| fail(format!("não consegui abrir {}: {e}", scratch.display())))?;
        let status = self
            .command(args, dir)
            .stdout(Stdio::from(sink))
            .stderr(Stdio::from(clone))
            .status();
        let output = std::fs::read(&scratch)
            .map(|b| String::from_utf8_lossy(&b).into_owned())
            .unwrap_or_default();
        let _ = std::fs::remove_file(&scratch);
        match status {
            Err(error) => Err(fail(format!("{}: {error}", dir.display()))),
            Ok(status) if !status.success() => Err(fail(output.trim().to_owned())),
            Ok(_) => Ok(output),
        }
    }

    /// Só o stdout, em bytes, sem erro: `None` quando o git não roda ou falha.
    /// É o que o `-z` pede (nomes separados por NUL, sem o stderr no meio).
    pub fn stdout_bytes(&self, args: &[&str], dir: &Path) -> Option<Vec<u8>> {
        let out = self
            .command(args, dir)
            .stderr(Stdio::null())
            .output()
            .ok()?;
        out.status.success().then_some(out.stdout)
    }
}
