//! De quais bancadas são os containers rodando no Docker (ADR-084), pelo
//! rótulo `com.docker.compose.project.working_dir` — a pasta de onde o compose
//! subiu. Container não segura conexão com ninguém: `up -d` e o terminal está
//! livre, mas fechar o Docker ainda derruba o banco da bancada ao lado.

use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ContainerOwners {
    pub benches: BTreeSet<String>,
    /// Container sem rótulo, ou de pasta que não é de bancada nenhuma: não dá
    /// para dizer de quem é, então segura o Docker aberto.
    pub unknown: bool,
}

impl ContainerOwners {
    /// `working_dirs`: uma linha por container. `paths`: bancada → pastas (a
    /// dela e a de cada nó em worktree própria), já expandidas. A pasta mais
    /// funda ganha: worktree pode morar dentro da pasta de outra bancada.
    pub fn new(working_dirs: &[String], paths: &BTreeMap<String, Vec<String>>) -> Self {
        let pairs: Vec<(&str, &str)> = paths
            .iter()
            .flat_map(|(bench, dirs)| dirs.iter().map(move |d| (bench.as_str(), d.as_str())))
            .collect();
        let mut owners = ContainerOwners::default();
        for dir in working_dirs {
            let dir = dir.trim_matches(|c| c == ' ' || c == '\t');
            let mut owner: Option<(&str, &str)> = None;
            for &(bench, path) in &pairs {
                let prefix = if path.ends_with('/') {
                    path.to_owned()
                } else {
                    format!("{path}/")
                };
                if dir != path && !dir.starts_with(&prefix) {
                    continue;
                }
                // Empate de tamanho: fica o primeiro, como o `max(by:)`.
                if owner.is_none_or(|(_, best)| best.chars().count() < path.chars().count()) {
                    owner = Some((bench, path));
                }
            }
            match owner {
                Some((bench, _)) => {
                    owners.benches.insert(bench.to_owned());
                }
                None => owners.unknown = true,
            }
        }
        owners
    }
}
