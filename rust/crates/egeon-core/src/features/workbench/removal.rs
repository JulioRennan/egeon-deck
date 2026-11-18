//! A parte da remoção da bancada que mexe em disco: apagar as worktrees, uma a
//! uma. Porte do `WorkbenchRemoval`.
//!
//! Roda FORA do ator. `worktree remove --force` numa árvore com `node_modules`
//! leva segundos — às vezes minutos —, e no Swift isso era o app inteiro
//! congelado com a bancada ainda na tela. Sem estado próprio: quem apaga entra
//! como função, e é o que deixa a contagem de falhas e sobras testável sem git.
//!
//! A fila serial da remoção (`egeon.workbench-removal`) é do core: duas
//! bancadas removidas em seguida que dividem repositório disputariam o
//! `.git/worktrees` do mesmo checkout.

use crate::features::worktree::model::Failure;
use crate::features::worktree::service;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RemovalTarget {
    pub path: String,
    /// Como a worktree aparece no alerta e no log: `repo · branch`.
    pub label: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Removal {
    pub removed: Vec<RemovalTarget>,
    /// Pastas que o git já desregistrou mas não terminou de apagar — a faxina
    /// delas vem depois que os processos da bancada morrerem (ADR-060).
    pub leftovers: Vec<String>,
    pub failures: Vec<(RemovalTarget, Failure)>,
}

impl Removal {
    pub fn succeeded(&self) -> bool {
        self.failures.is_empty()
    }
}

/// Apaga cada worktree. Uma falha não para as outras: o alerta diz o que já foi
/// e o que resistiu.
pub fn purge(
    targets: &[RemovalTarget],
    mut remove: impl FnMut(&str) -> Result<(), Failure>,
) -> Removal {
    let mut outcome = Removal::default();
    for target in targets {
        match remove(&target.path) {
            Ok(()) => outcome.removed.push(target.clone()),
            Err(Failure::Leftovers { path, reason }) => {
                // O registro já foi: a worktree acabou, o que sobrou é pasta.
                // Segurar a bancada por causa dela seria segurar por um problema
                // que a própria remoção resolve — quem escreve lá dentro são os
                // processos DESTA bancada, e eles morrem junto com ela.
                crate::log!(
                    "worktree: {path} — {reason}; a pasta fica para a faxina depois que os \
                     processos da bancada morrerem"
                );
                outcome.removed.push(target.clone());
                outcome.leftovers.push(path);
            }
            Err(error) => {
                // No log também: o alerta some com um OK, e é a mensagem do git
                // que diz por que a pasta resistiu.
                crate::log!("worktree: falha ao apagar {} — {error}", target.path);
                outcome.failures.push((target.clone(), error));
            }
        }
    }
    outcome
}

/// A segunda passada nas sobras, já com os processos da bancada mortos.
/// Insiste com espera (`finish_removal`): chamar de fora do ator.
pub fn sweep(paths: &[String]) {
    for path in paths {
        match service::finish_removal(path, false, 5) {
            Ok(_) => crate::log!("worktree: {path} apagada na segunda passada"),
            Err(error) => crate::log!("worktree: {path} resistiu — {error}"),
        }
    }
}
