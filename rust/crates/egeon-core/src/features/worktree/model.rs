//! Os tipos da worktree: o que o git diz do repositório, o que pode dar errado
//! e o destino de um nome de branch. Porte do `Worktree` (as structs) e das
//! extensões de texto do `BranchPlan`.

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

use crate::features::path_text;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Status {
    pub repo_root: String,
    pub branch: String,
    /// Mudanças em arquivos já rastreados.
    pub has_dirty_tracked: bool,
    /// Arquivos novos, não rastreados e não ignorados.
    pub untracked: Vec<String>,
}

impl Status {
    pub fn is_dirty(&self) -> bool {
        self.has_dirty_tracked || !self.untracked.is_empty()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum Failure {
    #[error("{0} não é um repositório git.")]
    NotARepo(String),
    #[error("Já existe algo em {0} — apague a pasta ou escolha outro caminho.")]
    DestinationExists(String),
    #[error("git {command} falhou:\n{output}")]
    Git { command: String, output: String },
    #[error(
        "O git já desfez o registro da worktree, mas a pasta {path} não pôde ser apagada — \
         {reason}. Apague-a à mão."
    )]
    Leftovers { path: String, reason: String },
}

/// O destino de um nome de branch, antes de mexer em disco.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BranchPlan {
    /// Não existe em lugar nenhum: nasce do HEAD do repositório de origem.
    New,
    /// Já existe local e está livre: a worktree abre nela, no commit dela.
    ExistingLocal,
    /// Só existe no remoto. A local nasce seguindo essa ref.
    Remote(String),
    /// Já está aberta numa worktree. Não há o que criar — é aquela pasta.
    AlreadyCheckedOut(String),
}

/// Retrato das branches do repositório, lido de uma vez.
///
/// O formulário precisa dizer, a cada tecla, o que vai acontecer com o nome
/// digitado. Perguntar ao git por caractere são três processos por tecla.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct BranchIndex {
    pub local: BTreeSet<String>,
    /// branch → ref remota (`origin/x`) de quem ainda não existe local.
    pub remote: BTreeMap<String, String>,
    /// branch → pasta da worktree que já a tem aberta.
    pub checked_out: BTreeMap<String, String>,
}

impl BranchIndex {
    pub fn plan(&self, branch: &str) -> BranchPlan {
        if let Some(path) = self.checked_out.get(branch) {
            return BranchPlan::AlreadyCheckedOut(path.clone());
        }
        if self.local.contains(branch) {
            return BranchPlan::ExistingLocal;
        }
        if let Some(reference) = self.remote.get(branch) {
            return BranchPlan::Remote(reference.clone());
        }
        BranchPlan::New
    }
}

impl BranchPlan {
    /// A branch nasce agora, e portanto sai do HEAD da origem.
    pub fn is_fresh(&self) -> bool {
        matches!(self, BranchPlan::New)
    }

    /// Uma linha, para a lista de terminais do formulário de duplicação.
    pub fn short(&self, home: &str) -> String {
        match self {
            BranchPlan::New => "branch nova".to_owned(),
            BranchPlan::ExistingLocal => "abre na branch que já existe".to_owned(),
            BranchPlan::Remote(reference) => format!("nasce seguindo {reference}"),
            BranchPlan::AlreadyCheckedOut(path) => {
                format!("já aberta em {}", path_text::abbreviate_tilde(path, home))
            }
        }
    }

    /// O que o formulário mostra embaixo do campo de branch, a cada tecla.
    ///
    /// Existe porque as quatro saídas são diferentes o bastante para mudar o
    /// que o botão "Criar" faz — de "nasce do commit atual" a "não cria nada,
    /// usa aquela pasta". Descobrir isso depois, no log, é o defeito que o
    /// ADR-018 conserta.
    pub fn summary(&self, coming_from: &str, dirty: bool, home: &str) -> String {
        let stays = format!(" As mudanças não commitadas de {coming_from} ficam onde estão.");
        match self {
            BranchPlan::New => {
                let carried = if dirty {
                    " As mudanças não commitadas vão junto."
                } else {
                    ""
                };
                format!("Branch nova · sai de {coming_from}, no commit atual.{carried}")
            }
            BranchPlan::ExistingLocal => format!(
                "Esta branch já existe · a worktree abre nela, no commit dela.{}",
                if dirty { stays.as_str() } else { "" }
            ),
            BranchPlan::Remote(reference) => format!(
                "Só existe em {reference} · a branch local nasce seguindo o remoto.{}",
                if dirty { stays.as_str() } else { "" }
            ),
            BranchPlan::AlreadyCheckedOut(path) => format!(
                "Já está aberta em {} · nada é criado, e é essa pasta que vai ser usada.",
                path_text::abbreviate_tilde(path, home)
            ),
        }
    }
}

/// O resultado de abrir uma worktree.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Created {
    pub path: String,
    pub branch: String,
    /// Se as modificações em arquivos rastreados vieram junto, para relatar sem
    /// inventar.
    pub carried_tracked_changes: bool,
    /// A worktree já existia e foi reaproveitada — nada foi criado em disco.
    pub reused: bool,
}

/// O que desaparece se uma worktree for apagada.
///
/// Commits sem upstream contam: eles vivem na branch, que sobrevive à remoção
/// — mas se ninguém souber que existem, ninguém vai buscá-los.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Losses {
    pub modified: Vec<String>,
    pub untracked: Vec<String>,
    pub unpushed_commits: u32,
}

impl Losses {
    pub fn is_empty(&self) -> bool {
        self.modified.is_empty() && self.untracked.is_empty() && self.unpushed_commits == 0
    }
}

/// O texto sem espaço nas pontas.
pub(crate) fn lines(text: &str) -> Vec<String> {
    text.lines()
        .map(str::to_owned)
        .filter(|l| !l.is_empty())
        .collect()
}

pub(crate) fn exists(path: &str) -> bool {
    Path::new(path).exists()
}
