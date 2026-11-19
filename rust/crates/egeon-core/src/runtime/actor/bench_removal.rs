//! Dono: `org`. Os dois levantamentos do diálogo "Remover bancada…", na ordem
//! do Swift (`confirmRemoveWorkbench`/`askRemoveWorkbench`): primeiro as
//! worktrees (só `rev-parse`/`worktree list`, rápido), e o que se perde
//! (`git status`/`ls-files`, lento com `node_modules`) só depois que a caixa de
//! apagar foi marcada, com a cortina de pé.
//!
//! Comandos do `/ui` que chegam aqui: plan_remove_workbench e removal_losses.

use serde_json::{Value, json};

use super::node_commands::unknown_bench;
use super::{Actor, ClientId};
use crate::features::worktree::removal_plan::{involved, loss_lines};
use crate::protocol::message::Reply;
use crate::protocol::org::WorkbenchRef;

/// A cortina enquanto o `git status` corre (`setRemoving(…, label:)`).
pub(super) const CHECKING_LOSSES: &str = "Conferindo o que se perde…";

impl Actor {
    /// O que remover a bancada leva: as worktrees que ela usa e se ela tem
    /// terminais de pé. Git em cada pasta, fora do ator.
    pub(super) fn plan_remove(
        &mut self,
        client: ClientId,
        re: u64,
        r: WorkbenchRef,
    ) -> Option<Reply> {
        let Some(index) = self.org.index_of(&r.workbench) else {
            return Some(unknown_bench(re, &r.workbench));
        };
        let bench = self.org.state.workbenches[index].clone();
        let live = self.org.live.contains(&bench.id);
        let context = self.removal_context(&bench);
        let (git, home) = (self.user_git(), self.org.home.clone());
        self.blocking(
            move || {
                involved(&git, &bench, &context, &home)
                    .iter()
                    .map(|w| {
                        json!({
                            "path": w.path, "repo": w.repo, "branch": w.branch,
                            "owners": w.owners, "used_by": w.used_by,
                        })
                    })
                    .collect::<Vec<Value>>()
            },
            Box::new(move |actor: &mut Actor, done: Result<Vec<Value>, String>| {
                let reply = match done {
                    Ok(worktrees) => {
                        Reply::with(re, &json!({"live": live, "worktrees": worktrees}))
                    }
                    Err(error) => Reply::err(re, error),
                };
                actor.send_reply(client, &reply);
            }),
        );
        None
    }

    /// O texto da 2ª confirmação: o trabalho não commitado que apagar as
    /// worktrees da bancada leva, uma seção por worktree, só das que nenhuma
    /// outra bancada usa (`lossLines(deletable)`). Vazio, não há o que
    /// perguntar. A cortina cobre a bancada enquanto o git corre.
    pub(super) fn removal_losses(
        &mut self,
        client: ClientId,
        re: u64,
        r: WorkbenchRef,
    ) -> Option<Reply> {
        let Some(index) = self.org.index_of(&r.workbench) else {
            return Some(unknown_bench(re, &r.workbench));
        };
        let bench = self.org.state.workbenches[index].clone();
        let id = bench.id.clone();
        let context = self.removal_context(&bench);
        let (git, home) = (self.user_git(), self.org.home.clone());
        self.org.busy.insert(id.clone(), CHECKING_LOSSES.to_owned());
        self.publish_org();
        self.blocking(
            move || {
                let deletable: Vec<_> = involved(&git, &bench, &context, &home)
                    .into_iter()
                    .filter(|w| w.used_by.is_none())
                    .collect();
                loss_lines(&git, &deletable)
            },
            Box::new(
                move |actor: &mut Actor, done: Result<Vec<String>, String>| {
                    // Só a nossa: outra fase (a limpeza) pode ter posto a dela.
                    if actor.org.busy.get(&id).map(String::as_str) == Some(CHECKING_LOSSES) {
                        actor.org.busy.remove(&id);
                        actor.publish_org();
                    }
                    let reply = match done {
                        Ok(losses) => Reply::with(re, &json!({"losses": losses})),
                        Err(error) => Reply::err(re, error),
                    };
                    actor.send_reply(client, &reply);
                },
            ),
        );
        None
    }
}
