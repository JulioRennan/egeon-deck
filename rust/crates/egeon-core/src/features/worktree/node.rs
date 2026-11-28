//! O que acontece com a pasta de um terminal quando a bancada vira worktree.
//! Porte do `NodeWorktree` e do `NodeWorktreePlanner` (sem o diálogo).
//!
//! Existe porque uma frente de trabalho raramente é um repositório só: o card
//! do frontend abre no repo da bancada, e o do backend abre num repo vizinho.
//! Uma branch nova precisa dos DOIS em worktree, senão o agente do backend
//! continua commitando no checkout principal enquanto o do frontend trabalha
//! na branch nova.

use std::collections::BTreeMap;
use std::path::Path;

use super::git::Git;
use super::service;
use crate::commons::ids::BranchName;
use crate::features::node::model::NodeKind;
use crate::features::path_text;
use crate::features::workbench::model::WorkbenchConfig;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NodeWorktree {
    pub node_id: String,
    /// Onde este nó abre hoje, já resolvido.
    pub current_path: String,
    /// Raiz do repositório em que `current_path` cai. `None` quando não é git.
    pub repo_root: Option<String>,
    /// A pasta está dentro da pasta da bancada?
    ///
    /// Quem está dentro e fica na MESMA branch não precisa de worktree própria:
    /// o `cwd` relativo já o leva para a pasta equivalente da worktree da
    /// bancada. Por contenção de caminho, e não por identidade de repositório:
    /// é essa a regra que o reapontamento de fato aplica, e duas worktrees do
    /// MESMO repo são pastas diferentes.
    pub inside_workbench: bool,
    /// Criar worktree própria para este terminal? Derivado da branch, não
    /// escolhido em caixinha: ver [`NodeWorktree::decided`].
    pub enabled: bool,
    /// Branch deste terminal. Nasce igual à da bancada: igual significa "vai
    /// junto com ela"; diferente, worktree própria; vazia, "não me leve".
    pub branch: String,
    /// Você editou a branch deste terminal à mão? Governa o re-sugerir: mudar a
    /// branch da bancada reescreve as linhas que você não tocou.
    pub touched: bool,
}

impl NodeWorktree {
    pub fn repo_name(&self) -> String {
        path_text::last_component(self.repo_root.as_deref().unwrap_or(&self.current_path))
    }

    /// Onde a worktree deste terminal nasce. Mesma convenção da bancada.
    pub fn destination(&self) -> Option<String> {
        let repo_root = self.repo_root.as_deref().filter(|_| self.enabled)?;
        let branch = BranchName::new(self.branch.as_str()).ok()?;
        Some(service::suggested_path(repo_root, &branch))
    }

    /// O plano deste terminal depois de saber a branch da bancada.
    ///
    /// Uma regra só, e é a branch que a diz: repositório outro, ou branch outra,
    /// pede worktree própria. Dentro da bancada e na mesma branch, ir junto é o
    /// suficiente — criar uma segunda worktree ali seriam duas pastas para a
    /// mesma branch do mesmo repo, e o git recusa a segunda.
    pub fn decided(&self, workbench_branch: &str) -> NodeWorktree {
        let mut copy = self.clone();
        copy.enabled = self.repo_root.is_some()
            && !self.branch.is_empty()
            && (!self.inside_workbench || self.branch != workbench_branch);
        copy
    }
}

/// Levanta o estado de cada nó que tem pasta. Nó `web` fica fora: ele não abre
/// pasta nenhuma.
pub fn inspect(
    git: &Git,
    config: &WorkbenchConfig,
    workbench_root: &str,
    branch: &str,
    home: &str,
) -> Vec<NodeWorktree> {
    config
        .nodes
        .iter()
        .filter(|node| node.kind != NodeKind::Web)
        .map(|node| {
            let path = config.resolved_directory(node, home);
            let inside =
                path == workbench_root || path_text::inside(&path, workbench_root).is_some();
            // Pasta que não existe não tem repositório para inspecionar, e
            // chamar o git nela só produziria erro. O nó aparece na lista de
            // qualquer jeito: é a chance de você ver que ele está quebrado.
            //
            // Pelo checkout PRINCIPAL: um terminal que já está numa worktree, se
            // partisse dela, aninharia worktree dentro de worktree.
            let root = if Path::new(&path).exists() {
                service::main_repo(git, &path)
            } else {
                None
            };
            NodeWorktree {
                node_id: node.id.clone(),
                current_path: path,
                // Todo terminal com repositório vai: repo vizinho ganha worktree
                // própria, e quem está dentro da bancada vai junto com ela.
                enabled: !inside && root.is_some(),
                repo_root: root,
                inside_workbench: inside,
                branch: branch.to_owned(),
                touched: false,
            }
        })
        .collect()
}

/// Cria as worktrees dos terminais e devolve, por nó, o `cwd` novo.
///
/// Nós que caem no mesmo `destination` — mesmo repo e mesma branch —
/// compartilham uma worktree, e o git só é chamado uma vez. Nomes diferentes no
/// mesmo repo viram worktrees diferentes, que é o que a customização por
/// terminal significa.
///
/// O que falha não derruba o resto: o terminal fica apontando para o
/// repositório original, que é onde ele estava, e o erro vai para o log.
/// `on_create(repo, worktree)` roda para cada worktree NOVA (a reaproveitada
/// tem trabalho dentro, e copiar `.env` por cima seria sobrescrever
/// configuração de alguém que não pediu nada).
pub fn materialize(
    git: &Git,
    plans: &[NodeWorktree],
    home: &str,
    mut on_create: impl FnMut(&str, &str),
) -> BTreeMap<String, String> {
    let mut created: BTreeMap<String, String> = BTreeMap::new();
    let mut cwd_by_node = BTreeMap::new();

    for plan in plans {
        let (true, Some(repo_root), Some(destination)) =
            (plan.enabled, plan.repo_root.as_deref(), plan.destination())
        else {
            continue;
        };

        if let Some(ready) = created.get(&destination) {
            cwd_by_node.insert(plan.node_id.clone(), short(ready, home));
            crate::log!(
                "worktree por terminal: \"{}\" divide {destination} com outro terminal",
                plan.node_id
            );
            continue;
        }

        // O nome que você escreveu, sem sufixo somado por baixo: se a branch já
        // existe, é nela que o terminal abre. Ver ADR-018.
        match service::create(git, repo_root, &plan.branch, &destination, true) {
            Ok(result) => {
                created.insert(destination.clone(), result.path.clone());
                cwd_by_node.insert(plan.node_id.clone(), short(&result.path, home));
                if !result.reused {
                    on_create(repo_root, &result.path);
                }
                crate::log!(
                    "worktree por terminal: \"{}\" → {}{}",
                    plan.node_id,
                    result.path,
                    if result.reused {
                        " (worktree que já existia)"
                    } else {
                        ""
                    }
                );
            }
            Err(error) => {
                crate::log!(
                    "worktree por terminal: \"{}\" falhou em {} — {error}. Segue apontando para \
                     {repo_root}",
                    plan.node_id,
                    plan.repo_name()
                );
                cwd_by_node.insert(plan.node_id.clone(), short(repo_root, home));
            }
        }
    }
    cwd_by_node
}

/// `/Users/você/x` → `~/x`. O que vai para o `workbenches.json` é feito para
/// ser lido e editado à mão.
pub fn short(path: &str, home: &str) -> String {
    match path.strip_prefix(home) {
        Some(rest) if !home.is_empty() => format!("~{rest}"),
        _ => path.to_owned(),
    }
}
