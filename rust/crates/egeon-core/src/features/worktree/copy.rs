//! Levar para a worktree nova o que o git não versiona. Porte do
//! `UnversionedCopy` e da parte de cópia do `Worktree`.
//!
//! O `cp -Rc` do script clona ARQUIVO por arquivo: um `node_modules` de 54 mil
//! itens levava 7,5 s. Clonar a pasta inteira de uma vez leva 1,4 s para o
//! mesmo `node_modules` — por isso a cópia é por entrada, em paralelo, e o
//! clone é do [`FileCloner`] (o driver).

use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Instant;

use super::git::Git;
use crate::ports::file_clone::FileCloner;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Outcome {
    pub copied: usize,
    pub failed: Vec<String>,
}

/// O que `git ls-files --others --directory` devolve: os arquivos novos E os
/// ignorados, com `node_modules/` como uma entrada só. `.git` nunca.
pub fn entries(git: &Git, source: &str) -> Vec<String> {
    let Some(bytes) = git.stdout_bytes(
        &["ls-files", "--others", "--directory", "-z"],
        Path::new(source),
    ) else {
        return Vec::new();
    };
    bytes
        .split(|&b| b == 0)
        .filter(|chunk| !chunk.is_empty())
        .filter_map(|chunk| String::from_utf8(chunk.to_vec()).ok())
        .filter(|entry| entry != ".git" && entry != ".git/")
        .collect()
}

/// Clona cada entrada para o mesmo caminho dentro de `destination`. Em
/// paralelo: o clone é metadado, e uma pasta `__pycache__` por vez era tempo de
/// fila, não de disco.
pub fn copy(
    entries: &[String],
    source: &str,
    destination: &str,
    cloner: &dyn FileCloner,
) -> Outcome {
    let outcome = Mutex::new(Outcome {
        copied: 0,
        failed: Vec::new(),
    });
    let next = std::sync::atomic::AtomicUsize::new(0);
    let workers = std::thread::available_parallelism()
        .map_or(4, usize::from)
        .min(entries.len().max(1));
    std::thread::scope(|scope| {
        for _ in 0..workers {
            scope.spawn(|| {
                loop {
                    let i = next.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                    let Some(item) = entries.get(i) else { break };
                    let relative = item.strip_suffix('/').unwrap_or(item);
                    let from = Path::new(source).join(relative);
                    let to = Path::new(destination).join(relative);
                    let ok = clone(&from, &to, cloner);
                    if let Ok(mut out) = outcome.lock() {
                        if ok {
                            out.copied += 1;
                        } else {
                            out.failed.push(item.clone());
                        }
                    }
                }
            });
        }
    });
    let mut out = outcome.into_inner().unwrap_or(Outcome {
        copied: 0,
        failed: Vec::new(),
    });
    out.failed.sort();
    out
}

/// Clona uma entrada. O que já existe no destino fica: a worktree pode ter sido
/// reaproveitada com coisa sua dentro.
pub fn clone(from: &Path, to: &Path, cloner: &dyn FileCloner) -> bool {
    if to.exists() {
        return true;
    }
    if let Some(parent) = to.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    cloner.clone_entry(from, to).is_ok()
}

/// O script ainda é o que o app escreveu, só com outro cabeçalho? Aí a cópia
/// rápida faz o mesmo que ele. Mexeu na lógica — pulou uma pasta, rodou um
/// `npm ci` —, vale o script, que é para isso que ele existe.
pub fn is_stock_script(text: &str) -> bool {
    body(text) == body(STOCK_SCRIPT)
}

fn body(text: &str) -> Vec<String> {
    text.lines()
        .map(|line| line.trim_matches([' ', '\t']).to_owned())
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .collect()
}

/// O script que o app escreve. O corpo dele é o que a cópia rápida faz
/// ([`is_stock_script`]).
pub const STOCK_SCRIPT: &str = r#"#!/usr/bin/env bash
# Egeon Deck — leva para a worktree nova tudo que o git não versiona.
#
# `git ls-files --others --directory` (sem --exclude-standard) lista de uma
# vez os arquivos novos E os ignorados, e `--directory` devolve
# `node_modules/` como uma entrada em vez de cem mil.
#
# `cp -c` usa clonefile do APFS: a cópia é instantânea e não ocupa disco
# até que um dos lados escreva. É o que torna copiar node_modules viável.
# Fora de APFS o clone falha e a cópia comum assume.
set -uo pipefail

SRC="${1:?uso: worktree-copy.sh <origem> <destino>}"
DST="${2:?uso: worktree-copy.sh <origem> <destino>}"

cd "$SRC" || exit 1

copiados=0
while IFS= read -r -d '' item; do
  case "$item" in
    .git/|.git) continue ;;
  esac
  destino="$DST/$item"
  mkdir -p "$(dirname "${destino%/}")"
  if cp -Rc "$SRC/$item" "${destino%/}" 2>/dev/null \
     || cp -R "$SRC/$item" "${destino%/}" 2>/dev/null; then
    copiados=$((copiados + 1))
    echo "  $item"
  else
    echo "  FALHOU: $item" >&2
  fi
done < <(git ls-files --others --directory -z)

echo "$copiados entrada(s) copiada(s) de $SRC para $DST"
"#;

/// Escreve o script de cópia, uma vez. Reescrever por cima apagaria ajustes do
/// usuário. `make_executable` é do sistema (`chmod 755`).
///
/// Fica num script à parte, e não embutido no app, porque é o passo que cada
/// projeto quer ajustar — e porque uma cópia de gigabytes tem que ser legível e
/// editável por quem espera por ela.
pub fn install_script(path: &Path, make_executable: &dyn Fn(&Path)) {
    if path.exists() {
        return;
    }
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if std::fs::write(path, STOCK_SCRIPT).is_ok() {
        make_executable(path);
        crate::log!("worktree: script de cópia escrito em {}", path.display());
    }
}

/// O bash que roda o script do usuário: o `/bin/bash` onde ele existe (macOS
/// e Linux, como no Swift); senão o do Git for Windows, achado pelo `git` do
/// `PATH`. Nunca o `bash` solto: no Windows a busca do sistema olha o
/// System32 antes do `PATH`, e o `bash.exe` de lá roda o script dentro do
/// Linux do WSL. `None` quando não há nenhum dos dois.
fn script_bash(env: &[(OsString, OsString)]) -> Option<PathBuf> {
    const SYSTEM_BASH: &str = "/bin/bash";
    if Path::new(SYSTEM_BASH).is_file() {
        return Some(PathBuf::from(SYSTEM_BASH));
    }
    let path = env
        .iter()
        .find(|(key, _)| key.eq_ignore_ascii_case("PATH"))
        .map(|(_, value)| value.as_os_str())?;
    git_bash(path)
}

/// O `bash.exe` que vem com o Git for Windows. O instalador padrão só põe a
/// pasta `Git\cmd` no `PATH`; o bash mora ao lado, em `Git\bin`.
fn git_bash(path: &OsStr) -> Option<PathBuf> {
    std::env::split_paths(path).find_map(|dir| {
        if !["git.exe", "git"]
            .iter()
            .any(|name| dir.join(name).is_file())
        {
            return None;
        }
        let bash = dir.parent()?.join("bin").join("bash.exe");
        bash.is_file().then_some(bash)
    })
}

/// Copia para a worktree tudo que o git não versiona: arquivos novos e também
/// os ignorados — `.env`, `node_modules`, `.dart_tool`, `Pods`, `build`. Sem
/// isso a worktree nasce sem configuração e sem dependências, e a "segunda
/// frente" custa um `pub get` e um `pod install` antes de existir.
///
/// Devolve o resumo de uma linha para a faixa. Síncrono e demorado (minutos
/// com `node_modules` grande e sem clone): chamar de `spawn_blocking`.
pub fn copy_unversioned(
    git: &Git,
    script: &Path,
    source: &str,
    destination: &str,
    cloner: &dyn FileCloner,
    make_executable: &dyn Fn(&Path),
) -> String {
    install_script(script, make_executable);

    let text = std::fs::read_to_string(script).unwrap_or_default();
    if is_stock_script(&text) {
        let started = Instant::now();
        let found = entries(git, source);
        let outcome = copy(&found, source, destination, cloner);
        let seconds = started.elapsed().as_secs_f64();
        let failed = if outcome.failed.is_empty() {
            String::new()
        } else {
            format!(" — falharam: {}", outcome.failed.join(", "))
        };
        let summary = format!(
            "{} entrada(s) clonada(s) em {seconds:.1} s{failed}",
            outcome.copied
        );
        crate::log!("worktree: cópia de {source} para {destination} — {summary}");
        return summary;
    }

    // O script do usuário: roda como ele escreveu, e a última linha é o resumo.
    let Some(bash) = script_bash(git.env()) else {
        crate::log!("worktree: sem bash para rodar {}", script.display());
        return "sem bash para rodar o script de cópia".to_owned();
    };
    let slashes = |p: &str| crate::features::path_text::with_slashes(p);
    let output = std::process::Command::new(bash)
        .arg(slashes(&script.to_string_lossy()))
        .arg(slashes(source))
        .arg(slashes(destination))
        .env_clear()
        .envs(git.env().iter().map(|(k, v)| (k, v)))
        .stdin(std::process::Stdio::null())
        .output();
    let Ok(output) = output else {
        return "erro ao rodar o script".to_owned();
    };
    let mut text = String::from_utf8_lossy(&output.stdout).into_owned();
    text.push_str(&String::from_utf8_lossy(&output.stderr));
    let text = text.trim();
    crate::log!("worktree: cópia de arquivos não versionados terminou\n{text}");
    text.lines()
        .last()
        .map_or_else(|| "cópia concluída".to_owned(), str::to_owned)
}

#[cfg(test)]
mod bash_tests {
    use super::*;

    /// Uma instalação falsa do Git for Windows: `Git\cmd\git.exe` no `PATH` e
    /// o `bash.exe` em `Git\bin`.
    #[test]
    fn o_bash_vem_do_git_do_path_e_nunca_solto() -> std::io::Result<()> {
        let dir = tempfile::tempdir()?;
        let git = dir.path().join("Git");
        std::fs::create_dir_all(git.join("cmd"))?;
        std::fs::create_dir_all(git.join("bin"))?;
        std::fs::write(git.join("cmd").join("git.exe"), "")?;
        let elsewhere = dir.path().join("outra");
        std::fs::create_dir_all(&elsewhere)?;
        let path = std::env::join_paths([elsewhere.clone(), git.join("cmd")]).unwrap_or_default();

        // Sem o bash ao lado: nada, em vez de um `bash` qualquer.
        assert_eq!(git_bash(&path), None);
        std::fs::write(git.join("bin").join("bash.exe"), "")?;
        assert_eq!(git_bash(&path), Some(git.join("bin").join("bash.exe")));
        // Sem git no PATH, também nada.
        assert_eq!(git_bash(elsewhere.as_os_str()), None);
        Ok(())
    }
}
