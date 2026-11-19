//! Dono: `org`. A cópia do que o git não versiona para as worktrees novas, com
//! a faixa do shell dizendo o que está sendo copiado (`copyUnversioned` do
//! `main.swift`).

use std::time::Duration;

use super::{Actor, Msg};
use crate::features::path_text::last_component;

/// Quanto o resumo da última cópia fica na faixa antes de sumir.
const SUMMARY_LINGERS: Duration = Duration::from_secs(4);

impl Actor {
    /// Copia o que o git não versiona (`.env`, `node_modules`, `Pods`…) para
    /// cada worktree criada, uma depois da outra — com clone do APFS cada uma
    /// leva um ou dois segundos. Worktree reaproveitada nem chega aqui.
    ///
    /// Pelo id da bancada, e não pela posição: a cópia leva segundos, e se uma
    /// bancada de cima sai da lista nesse meio-tempo, a posição guardada passa a
    /// ser de outra — e a faixa da que pediu nunca era apagada.
    pub(super) fn copy_unversioned(&mut self, bench: &str, mut pending: Vec<(String, String)>) {
        if pending.is_empty() {
            self.set_banner(bench, None);
            return;
        }
        let (repo, path) = pending.remove(0);
        let name = last_component(&repo);
        let more = if pending.is_empty() {
            String::new()
        } else {
            format!(" — e mais {}", pending.len())
        };
        self.set_banner(
            bench,
            Some(format!(
                "Copiando o que o git não versiona em {name} (.env, node_modules, build…){more}"
            )),
        );
        crate::log!("worktree: copiando o que o git não versiona em {name}");
        let script = self.config.paths.config("worktree-copy.sh");
        let (git, cloner, links) = (
            self.user_git(),
            self.drivers.cloner.clone(),
            self.drivers.links.clone(),
        );
        let bench = bench.to_owned();
        self.blocking(
            move || {
                crate::features::worktree::copy::copy_unversioned(
                    &git,
                    &script,
                    &repo,
                    &path,
                    &*cloner,
                    &|file| {
                        let _ = links.make_executable(file);
                    },
                )
            },
            Box::new(move |actor: &mut Actor, done: Result<String, String>| {
                let summary = done.unwrap_or_else(|error| {
                    crate::log!("worktree: a cópia do que o git não versiona falhou — {error}");
                    error
                });
                let line = format!("{name}: {summary}");
                actor.set_banner(&bench, Some(line.clone()));
                if pending.is_empty() {
                    actor.clear_banner_later(bench, line);
                } else {
                    actor.copy_unversioned(&bench, pending);
                }
            }),
        );
    }

    /// Apaga a faixa depois de um tempo, se ela ainda diz o mesmo: uma cópia
    /// nova na mesma bancada não pode perder a faixa dela.
    fn clear_banner_later(&self, bench: String, line: String) {
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            tokio::time::sleep(SUMMARY_LINGERS).await;
            let job = move |actor: &mut Actor| {
                if actor.org.banners.get(&bench) == Some(&line) {
                    actor.set_banner(&bench, None);
                }
            };
            let _ = inbox.send(Msg::Run(Box::new(job))).await;
        });
    }

    pub(super) fn set_banner(&mut self, bench: &str, text: Option<String>) {
        let changed = match text {
            Some(text) => self.org.banners.insert(bench.to_owned(), text.clone()) != Some(text),
            None => self.org.banners.remove(bench).is_some(),
        };
        if changed {
            self.publish_org();
        }
    }
}
