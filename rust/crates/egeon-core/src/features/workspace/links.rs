//! Mantém a pasta de um multi-projeto com um link por repositório. Porte do
//! `MultiProjectLinks`.
//!
//! Link, e não cópia nem worktree: no checkout principal o que se quer é o
//! repositório de verdade, só que ao lado do outro. O isolamento de branch é da
//! bancada em worktree, que tem pasta própria (ADR-065).
//!
//! Criar o link é a única chamada que muda por sistema (`symlink` no Unix, outro
//! par de chamadas no Windows); por isso `make_link(alvo, link)` entra como
//! parâmetro, e quem liga isto ao driver é o core.

use std::io;
use std::path::Path;

use super::model::WorkspaceConfig;
use super::multi::{LinkName, link_names};

/// `Some(destino)` quando `path` é um link simbólico.
fn link_target(path: &Path) -> Option<String> {
    std::fs::read_link(path)
        .ok()
        .map(|t| t.to_string_lossy().into_owned())
}

fn is_link(path: &Path) -> bool {
    std::fs::symlink_metadata(path).is_ok_and(|m| m.file_type().is_symlink())
}

/// Deixa `directory` com exatamente estes links. Só apaga o que é link: um
/// arquivo que você pôs ali à mão não é do app. Devolve o que não deu para
/// fazer, em texto para o log.
pub fn sync(
    directory: &Path,
    links: &[LinkName],
    make_link: &dyn Fn(&Path, &Path) -> io::Result<()>,
) -> Vec<String> {
    if let Err(error) = std::fs::create_dir_all(directory) {
        return vec![format!(
            "não consegui criar {} — {error}",
            directory.display()
        )];
    }
    let mut problems = Vec::new();

    // O primeiro nome vale, se o mesmo vier duas vezes.
    let mut wanted: Vec<(&str, &str)> = Vec::new();
    for link in links {
        if !wanted.iter().any(|(name, _)| *name == link.name) {
            wanted.push((&link.name, &link.target));
        }
    }
    if let Ok(entries) = std::fs::read_dir(directory) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            let Some(current) = link_target(&entry.path()) else {
                continue;
            };
            let keep = wanted
                .iter()
                .any(|(n, target)| *n == name && *target == current);
            if !keep {
                let _ = std::fs::remove_file(entry.path());
            }
        }
    }
    for link in links {
        let path = directory.join(&link.name);
        if link_target(&path).as_deref() == Some(link.target.as_str()) {
            continue;
        }
        if path.exists() {
            problems.push(format!(
                "{} já existe e não é link — deixei como está",
                path.display()
            ));
            continue;
        }
        if let Err(error) = make_link(Path::new(&link.target), &path) {
            problems.push(format!("link {} → {}: {error}", link.name, link.target));
        }
    }
    problems
}

/// Todos os multi-projetos dos workspaces, de uma vez: na carga e depois de
/// salvar o formulário. Devolve as linhas de log.
pub fn sync_all(
    workspaces: &[WorkspaceConfig],
    home: &str,
    make_link: &dyn Fn(&Path, &Path) -> io::Result<()>,
) -> Vec<String> {
    let mut log = Vec::new();
    for space in workspaces {
        for project in space.projects.iter().filter(|p| p.is_multi()) {
            let links = link_names(&space.members_of(project), home);
            let directory = project.url_path(home);
            for problem in sync(Path::new(&directory), &links, make_link) {
                log.push(format!("multi-projeto \"{}\": {problem}", project.name));
            }
        }
    }
    log
}

/// Subpastas de verdade, sem os links: é onde moram as worktrees de uma
/// bancada multi-projeto.
pub fn real_subfolders(directory: &Path) -> Vec<String> {
    let Ok(entries) = std::fs::read_dir(directory) else {
        return Vec::new();
    };
    let mut names: Vec<String> = entries
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .collect();
    names.sort();
    names
        .into_iter()
        .filter_map(|name| {
            let path = directory.join(name);
            (!is_link(&path) && path.is_dir()).then(|| path.to_string_lossy().into_owned())
        })
        .collect()
}

/// Apaga a pasta-mãe quando só sobraram links e lixo do Finder nela. Com
/// qualquer outra coisa dentro — worktree que resistiu, arquivo seu — fica.
/// Devolve a linha de log do que fez, se fez alguma coisa.
pub fn prune_root(directory: &Path) -> Option<String> {
    if !directory.exists() {
        return None;
    }
    // Tudo ou nada, como o Swift: uma entrada que não deu para ler pode ser um
    // arquivo seu, e na dúvida a pasta não é apagada.
    let Ok(entries) = std::fs::read_dir(directory).and_then(|rd| rd.collect::<Result<Vec<_>, _>>())
    else {
        return None;
    };
    let disposable = entries
        .iter()
        .all(|e| e.file_name() == ".DS_Store" || is_link(&e.path()));
    if !disposable {
        return None;
    }
    Some(match std::fs::remove_dir_all(directory) {
        Ok(()) => format!("multi-projeto: pasta {} apagada", directory.display()),
        Err(error) => format!(
            "multi-projeto: não consegui apagar {} — {error}",
            directory.display()
        ),
    })
}
