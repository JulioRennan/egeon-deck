//! Grava, antes de o Claude subir, a confiança que a pasta herda do repositório
//! de onde saiu (ADR-071).
//!
//! Só mexe nas três chaves de uma entrada, num arquivo que os `claude` em
//! execução também gravam: lê, muda e troca o arquivo de uma vez, como o próprio
//! CLI faz. Dois gravando no mesmo instante é possível, e o pior caso é a
//! marcação sumir e o diálogo voltar — conversa e ajustes não correm risco.
//!
//! Quem herda de quem: worktree ligada herda do checkout principal; pasta fora
//! de git (a do multi-projeto), dos repositórios de dentro; checkout principal
//! não herda de ninguém.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use serde_json::Value;

use super::trust;

/// O `.claude.json` do `CLAUDE_CONFIG_DIR` dado (`None` = o padrão,
/// `~/.claude.json`).
pub fn config_file(config_dir: Option<&str>, home: &Path) -> PathBuf {
    match config_dir.filter(|d| !d.is_empty()) {
        None => home.join(".claude.json"),
        Some(dir) => crate::features::agent::model::expand_tilde(dir, home).join(".claude.json"),
    }
}

/// O caminho como o Claude grava a chave: `realpath`, que mantém o `/private`
/// de `/private/tmp`.
pub fn real(path: &Path) -> String {
    crate::commons::paths::canonicalize(path)
        .unwrap_or_else(|_| path.to_path_buf())
        .to_string_lossy()
        .into_owned()
}

/// O que o seeder precisa saber do git.
pub trait Worktrees {
    /// A raiz da worktree em que a pasta está (a ligada, se for uma); `None`
    /// fora de git.
    fn top_level(&self, path: &Path) -> Option<PathBuf>;
    /// O checkout principal do repositório de que a pasta faz parte.
    fn main_worktree(&self, path: &Path) -> Option<PathBuf>;
}

/// O `git` do PATH.
pub struct GitCli;

fn git(args: &[&str], dir: &Path) -> Option<String> {
    let out = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(args)
        .output()
        .ok()?;
    out.status
        .success()
        .then(|| String::from_utf8_lossy(&out.stdout).into_owned())
}

impl Worktrees for GitCli {
    fn top_level(&self, path: &Path) -> Option<PathBuf> {
        let out = git(&["rev-parse", "--show-toplevel"], path)?;
        let root = out.trim();
        (!root.is_empty()).then(|| PathBuf::from(root))
    }

    fn main_worktree(&self, path: &Path) -> Option<PathBuf> {
        let listing = git(&["worktree", "list", "--porcelain"], path)?;
        listing
            .lines()
            .find_map(|line| line.strip_prefix("worktree "))
            .map(PathBuf::from)
    }
}

/// A pasta que o Claude vai consultar e de onde ela herda: `(alvo, origens)`.
/// `None` para o checkout principal, que não herda de ninguém.
pub fn sources(cwd: &Path, git: &dyn Worktrees) -> Option<(String, Vec<String>)> {
    let path = real(cwd);
    let Some(top) = git.top_level(Path::new(&path)) else {
        return Some((path.clone(), repositories_inside(Path::new(&path), git)));
    };
    let target = real(&top);
    let main = git.main_worktree(Path::new(&path)).map(|m| real(&m))?;
    (main != target).then(|| (target, vec![main]))
}

/// O repositório principal de cada pasta git logo abaixo — o que o Claude
/// usaria de chave se subisse nela.
pub fn repositories_inside(folder: &Path, git: &dyn Worktrees) -> Vec<String> {
    git_children(folder)
        .iter()
        .filter_map(|child| git.main_worktree(child).map(|m| real(&m)))
        .collect()
}

/// As pastas que têm `.git` logo abaixo de `folder`, em ordem de nome.
pub fn git_children(folder: &Path) -> Vec<PathBuf> {
    let mut names: Vec<PathBuf> = fs::read_dir(folder)
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path())
        .collect();
    names.sort();
    names
        .into_iter()
        .filter(|p| p.join(".git").exists())
        .collect()
}

/// O que roda antes de o Claude subir (ADR-071, `ClaudeTrustSeeder.prepare`):
/// a pasta do nó herda a confiança do repositório de onde saiu e, além do
/// Swift (decisão do Julio), fica aceita de qualquer jeito — o CLI nunca
/// pergunta. Grava no `.claude.json` da config real do nó; a decisão 36 vale
/// só para as skills (`install.rs`). Devolve `true` quando gravou.
pub fn prepare_for_launch(
    cwd: &Path,
    config_dir: Option<&str>,
    user_home: &Path,
    git: &dyn Worktrees,
) -> bool {
    // O checkout principal não herda de ninguém: a chave é a raiz dele.
    let (target, origins) = sources(cwd, git).unwrap_or_else(|| {
        let top = git.top_level(Path::new(&real(cwd)));
        (real(top.as_deref().unwrap_or(cwd)), Vec::new())
    });
    let file = config_file(config_dir, user_home);
    let Some(root) = read_json(&file) else {
        return false;
    };
    let inherited = trust::inheriting(&root, &target, &origins);
    let base = inherited.as_ref().unwrap_or(&root);
    match (trust::accepting(base, &target), inherited.is_some()) {
        (Some(accepted), _) => write_json(
            &file,
            &accepted,
            &format!("confiança[claude]: {target} aceita em {}", file.display()),
        ),
        (None, true) => write_json(&file, base, &inherited_line(&target, &origins, &file)),
        (None, false) => false,
    }
}

fn read_json(file: &Path) -> Option<Value> {
    serde_json::from_slice::<Value>(&fs::read(file).ok()?).ok()
}

fn inherited_line(target: &str, origins: &[String], file: &Path) -> String {
    let names: Vec<String> = origins
        .iter()
        .map(|o| {
            Path::new(o)
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default()
        })
        .collect();
    format!(
        "confiança[claude]: {target} herdou de {} em {}",
        names.join(", "),
        file.display()
    )
}

/// Grava a herança. Devolve `true` quando o arquivo mudou.
pub fn prepare(target: &str, origins: &[String], file: &Path) -> bool {
    if origins.is_empty() {
        return false;
    }
    let Some(root) = read_json(file) else {
        return false;
    };
    let Some(updated) = trust::inheriting(&root, target, origins) else {
        return false;
    };
    write_json(file, &updated, &inherited_line(target, origins, file))
}

/// Troca o arquivo de uma vez, como o próprio CLI faz, e loga [line].
fn write_json(file: &Path, updated: &Value, line: &str) -> bool {
    let Ok(text) = serde_json::to_string_pretty(updated) else {
        return false;
    };
    let tmp = file.with_extension("json.tmp");
    // O `.claude.json` guarda credenciais e costuma ser 0600: o arquivo novo
    // nasce com a permissão do original, não com a do umask.
    let mode = fs::metadata(file).map(|m| m.permissions()).ok();
    let written = fs::write(&tmp, text)
        .and_then(|()| match mode {
            Some(mode) => fs::set_permissions(&tmp, mode),
            None => Ok(()),
        })
        .and_then(|()| fs::rename(&tmp, file));
    match written {
        Ok(()) => {
            crate::log!("{line}");
            true
        }
        Err(error) => {
            let _ = fs::remove_file(&tmp);
            crate::log!("confiança[claude]: não gravei {} — {error}", file.display());
            false
        }
    }
}
