//! Dono: `chat-rs`. A confiança que a pasta do nó herda do repositório, gravada
//! antes de o Claude subir (ADR-071).

use std::path::PathBuf;

use super::{Actor, Msg};
use crate::features::agent::claude::trust_seeder::{self, GitCli};

impl Actor {
    /// Grava a herança fora do laço do ator — o `git` é processo filho — e só
    /// então roda `then`, que sobe o terminal: o Claude lê o arquivo ao
    /// começar, então a gravação tem de vir antes. Se o job morrer, `then`
    /// roda assim mesmo: um terminal que pergunta de novo é melhor que um que
    /// não sobe.
    ///
    /// `own_home` restringe a gravação à pasta de dados (decisão 36); ver
    /// [`trust_seeder::prepare_for_launch`].
    pub(super) fn seed_trust_then(
        &self,
        cwd: PathBuf,
        config_dir: Option<String>,
        own_home: Option<PathBuf>,
        then: impl FnOnce(&mut Actor) + Send + 'static,
    ) {
        let inbox = self.inbox.clone();
        let user_home = PathBuf::from(&self.org.home);
        tokio::spawn(async move {
            let seeded = tokio::task::spawn_blocking(move || {
                trust_seeder::prepare_for_launch(
                    &cwd,
                    config_dir.as_deref(),
                    &user_home,
                    own_home.as_deref(),
                    &GitCli,
                )
            })
            .await;
            if seeded.is_err() {
                crate::log!("confiança[claude]: a gravação não terminou");
            }
            let _ = inbox.send(Msg::Run(Box::new(then))).await;
        });
    }
}
