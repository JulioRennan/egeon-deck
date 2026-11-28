//! O que o campo de pasta do terminal oferece: as subpastas da bancada que são
//! repositório — em multi-projeto, um repo por subpasta —, sempre relativas.
//! Porte do `FolderSuggestions` e das regras da lista do `NodeTemplateDialog`.
//!
//! Só de dentro. Relativo é o que vale em qualquer checkout: na worktree, cada
//! subpasta é a worktree daquele repo. Oferecer o checkout principal de outro
//! projeto na lista seria convidar o terminal a trabalhar fora da branch da
//! bancada; quem precisa disso digita ou usa o "Escolher…" (ADR-017/065).

use std::path::Path;

/// A raiz na lista. Grava vazio, que é como o resto do app diz "a raiz".
pub const ROOT_OPTION: &str = "root";

pub fn list(repo_children: &[String]) -> Vec<String> {
    let mut out = repo_children.to_vec();
    out.sort();
    out
}

/// Subpastas da raiz que são repositório — pasta com `.git` (checkout ou
/// worktree) ou link para uma.
pub fn repo_children(root: &Path) -> Vec<String> {
    let Ok(entries) = std::fs::read_dir(root) else {
        return Vec::new();
    };
    entries
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .filter(|name| !name.starts_with('.') && root.join(name).join(".git").exists())
        .collect()
}

/// O texto de uma pasta na lista: a raiz aparece como `root`.
pub fn shown(cwd: Option<&str>) -> &str {
    match cwd {
        Some(value) if !value.is_empty() => value,
        _ => ROOT_OPTION,
    }
}

/// As opções da lista de pasta: a raiz, as subpastas da bancada, e a pasta
/// atual do nó quando ela não é nenhuma dessas — sem ela, editar um nó
/// customizado mostraria uma escolha que não é a dele.
pub fn folder_options(current: &str, suggestions: &[String]) -> Vec<String> {
    let mut out = vec![String::new()];
    out.extend(suggestions.iter().filter(|s| !s.is_empty()).cloned());
    if !out.iter().any(|o| o == current) {
        out.push(current.to_owned());
    }
    out
}
