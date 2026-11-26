//! Dono: `cli`. Liga ao ator a atualização do app e a rota /update.
//!
//! O [`UpdateController`] decide e devolve [`Effect`]s. A consulta e o
//! download saem do ator por `tokio::spawn` (o [`UpdateClient`] é a rede) e
//! voltam por `Msg::Run` como uma [`Completion`]. O aviso, a mensagem e o
//! pedido para encerrar o app são da UI, e o canal `/ui` ainda não tem evento
//! para eles: ficam no log até o protocolo ganhar um.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::SystemTime;

use super::{Actor, Msg, Replier, not_ported};
use crate::features::update::controller::State;
use crate::features::update::controller::{
    CHECK_EVERY, Effect, FEED, FIRST_CHECK_AFTER, UpdateConfig, UpdateController,
};
use crate::features::update::fetch::UpdateClient;
use crate::features::update::installer::UpdateInstaller;
use crate::features::update::policy::Reason;
use crate::features::update::prompt;
use crate::features::update::release::{AssetNames, AvailableUpdate, NEXT_BUNDLE_ID};
use crate::features::update::routes::update;
use crate::protocol::app::{AppEffect, UpdateAnswer, UpdatePhase, UpdateView};
use crate::protocol::handler::RouteRequest;
use crate::protocol::routes::FeatureRoute;

/// O estado da atualização dentro do ator. Nasce vazio e se completa no
/// primeiro uso, a partir da `Config`.
#[derive(Default)]
pub(super) struct UpdateState {
    inner: Option<Inner>,
    /// Outro endereço de consulta, só no teste: o padrão é o GitHub.
    #[cfg(test)]
    pub(super) feed_override: Option<String>,
}

struct Inner {
    controller: UpdateController,
    /// Só existe quando o cliente HTTPS subiu; sem ele nada é consultado.
    client: Option<Arc<UpdateClient>>,
    /// A primeira consulta, [`FIRST_CHECK_AFTER`] depois de abrir.
    launch_at: Option<SystemTime>,
    /// A próxima consulta periódica.
    periodic_at: Option<SystemTime>,
    /// O agendamento já foi decidido (uma vez por vida do ator).
    scheduled: bool,
    /// `EGEON_NO_UPDATE_CHECK=1`: sem consulta ao feed na partida nem de
    /// tempos em tempos (testes e e2e). A consulta pedida (menu, `/update`)
    /// segue valendo.
    checks_off: bool,
    /// A versão do aviso que está na tela, para a resposta dele (`update_answer`).
    prompted: Option<AvailableUpdate>,
}

/// O app instalado, que a troca substitui: o `.app` que contém este
/// executável, ou o AppImage de onde ele roda — dentro do AppImage o
/// executável está numa montagem só de leitura, e o arquivo a trocar é o que o
/// runtime aponta em `$APPIMAGE`. Fora dos dois (`cargo run`, teste, `.deb`) o
/// caminho cai no executável, e `can_install` o recusa.
fn app_bundle() -> PathBuf {
    installed_app(
        std::env::var_os("APPIMAGE").as_deref(),
        std::env::current_exe().unwrap_or_default(),
    )
}

fn installed_app(appimage: Option<&std::ffi::OsStr>, exe: PathBuf) -> PathBuf {
    if let Some(appimage) = appimage.filter(|a| !a.is_empty()) {
        return PathBuf::from(appimage);
    }
    let bundle = exe
        .ancestors()
        .find(|p| p.extension().is_some_and(|e| e == "app"))
        .map(Path::to_path_buf);
    bundle.unwrap_or(exe)
}

/// O interruptor das consultas automáticas: só `1` liga, como as outras
/// variáveis do app.
fn no_update_check(get: impl Fn(&str) -> Option<String>) -> bool {
    get("EGEON_NO_UPDATE_CHECK").is_some_and(|v| v == "1")
}

/// Teste nunca vai ao feed: o estável consultaria o GitHub 4 s depois de
/// abrir, e o `Harness` do runtime não define o interruptor.
#[cfg(test)]
fn checks_off_at_start() -> bool {
    true
}

#[cfg(not(test))]
fn checks_off_at_start() -> bool {
    no_update_check(|key| std::env::var(key).ok())
}

impl Actor {
    fn update_inner(&mut self) -> &mut Inner {
        let config = &self.config;
        let platform = self.drivers.installer.clone();
        #[cfg(test)]
        let feed = self
            .update
            .feed_override
            .clone()
            .unwrap_or_else(|| FEED.to_owned());
        #[cfg(not(test))]
        let feed = FEED.to_owned();
        self.update.inner.get_or_insert_with(|| {
            let installer = Arc::new(UpdateInstaller::new(
                app_bundle(),
                NEXT_BUNDLE_ID,
                config.version.clone(),
                std::env::temp_dir(),
                platform,
            ));
            let controller = UpdateController::new(
                installer,
                UpdateConfig {
                    installed_version: config.version.clone(),
                    display_name: config.flavor.display_name().to_owned(),
                    is_dev: config.flavor.is_dev(),
                    app_pid: std::process::id(),
                    settings_file: config.paths.config(crate::features::update::settings::FILE),
                    swap_log: config.paths.config("update.log"),
                    feed,
                    assets: AssetNames::default(),
                },
            );
            let client = UpdateClient::new(&config.version, config.flavor.is_dev())
                .map_err(|error| crate::log!("atualização: sem cliente HTTPS — {error}"))
                .ok()
                .map(Arc::new);
            Inner {
                controller,
                client,
                launch_at: None,
                periodic_at: None,
                scheduled: false,
                checks_off: checks_off_at_start(),
                prompted: None,
            }
        })
    }

    pub(super) fn update_route(
        &mut self,
        route: FeatureRoute,
        request: RouteRequest,
        reply: Replier,
    ) {
        if route != FeatureRoute::Update {
            return not_ported(route, reply);
        }
        let (answer, effects) = update(
            &mut self.update_inner().controller,
            &request,
            SystemTime::now(),
        );
        let _ = reply.send(answer);
        self.update_apply(effects);
    }

    /// O aviso de versão nova, com o texto pronto: as novidades cortadas, o
    /// custo de reiniciar (quantos agentes abertos) e o que o clique autoriza.
    fn update_prompt(&mut self, update: AvailableUpdate) {
        let dispatcher = &self.dispatch.coordination.dispatcher;
        let agents = dispatcher
            .addresses()
            .iter()
            .filter(|a| dispatcher.target(a).is_some_and(|t| t.profile().is_some()))
            .count();
        let inner = self.update_inner();
        let effect = AppEffect::UpdatePrompt {
            version: update.version.clone(),
            title: format!("Versão {} do Egeon Deck disponível", update.version),
            text: prompt::text(&update.notes, agents),
            auto: inner.controller.auto(),
            auto_label: "Atualizar automaticamente: baixar sozinho e trocar quando eu fechar o app"
                .to_owned(),
            accept_label: "Atualizar e reiniciar".to_owned(),
            later_label: "Depois".to_owned(),
        };
        inner.prompted = Some(update);
        self.app_effect(effect);
    }

    /// O estado da atualização para o tópico `app`.
    pub(super) fn update_view(&mut self) -> UpdateView {
        let installed = self.config.version.clone();
        let inner = self.update_inner();
        let (phase, version) = match inner.controller.state() {
            State::Idle => (UpdatePhase::Idle, None),
            State::Checking => (UpdatePhase::Checking, None),
            State::Available(u) => (UpdatePhase::Available, Some(u.version.clone())),
            State::Downloading(u) => (UpdatePhase::Downloading, Some(u.version.clone())),
            State::Ready(v) => (UpdatePhase::Ready, Some(v.clone())),
        };
        UpdateView {
            phase,
            version,
            menu: inner.controller.menu_title(),
            menu_enabled: inner.controller.menu_enabled(),
            auto: inner.controller.auto(),
            installed,
            staged: inner.controller.installer().is_staged(),
        }
    }

    /// O clique no item "Procurar atualizações…" do menu.
    pub(super) fn update_menu_clicked(&mut self) {
        let effects = self.update_inner().controller.menu_clicked();
        self.update_apply(effects);
    }

    /// A resposta ao aviso: primeiro a caixa de atualizar sozinho, depois
    /// "Atualizar e reiniciar", como o Swift.
    pub(super) fn update_answer(&mut self, answer: UpdateAnswer) -> Result<(), String> {
        let inner = self.update_inner();
        let mut effects = Vec::new();
        if answer.auto != inner.controller.auto() {
            effects.extend(inner.controller.set_auto(answer.auto));
        }
        if answer.accept {
            let Some(update) = inner
                .prompted
                .clone()
                .filter(|u| u.version == answer.version)
            else {
                self.update_apply(effects);
                return Err(format!(
                    "o aviso da versão {} não está aberto",
                    answer.version
                ));
            };
            effects.extend(inner.controller.update_and_restart(update));
        }
        self.update_apply(effects);
        Ok(())
    }

    /// O item de menu "Atualizar automaticamente".
    pub(super) fn update_set_auto(&mut self, on: bool) {
        let effects = self.update_inner().controller.set_auto(on);
        self.update_apply(effects);
    }

    /// Ao abrir, uma consulta depois de [`FIRST_CHECK_AFTER`] e outra a cada
    /// [`CHECK_EVERY`] — só no estável, que é quando o controller diz que
    /// vale a pena.
    pub(super) fn update_tick(&mut self, now: SystemTime) {
        let inner = self.update_inner();
        if inner.checks_off {
            return;
        }
        if !inner.scheduled {
            inner.scheduled = true;
            if inner.controller.start() {
                inner.launch_at = Some(now + FIRST_CHECK_AFTER);
            }
        }
        let mut effects = Vec::new();
        if inner.launch_at.is_some_and(|at| now >= at) {
            inner.launch_at = None;
            inner.periodic_at = Some(now + CHECK_EVERY);
            effects.extend(inner.controller.check(Reason::Launch, None));
        } else if inner.periodic_at.is_some_and(|at| now >= at) {
            inner.periodic_at = Some(now + CHECK_EVERY);
            effects.extend(inner.controller.check(Reason::Periodic, None));
        }
        self.update_apply(effects);
    }

    /// O app está saindo: com a opção ligada e a versão pronta, a troca vai
    /// agora. O core a chama no encerramento (`Msg::Shutdown`), que é dele.
    #[allow(dead_code)]
    pub(super) fn update_shutdown(&mut self) {
        let effects = self.update_inner().controller.application_will_terminate();
        self.update_apply(effects);
    }

    /// Faz o que o controller pediu. A rede sai do ator; o resto é da UI.
    fn update_apply(&mut self, effects: Vec<Effect>) {
        for effect in effects {
            match effect {
                Effect::FetchRelease { .. } | Effect::Download(_) => self.update_network(effect),
                Effect::Prompt(update) => self.update_prompt(update),
                Effect::Message { title, text } => {
                    self.app_effect(AppEffect::UpdateMessage { title, text });
                }
                Effect::Terminate => self.app_effect(AppEffect::Terminate),
            }
        }
        // O estado mudou (consultando, baixando, pronto): quem assina `app` vê.
        self.app_publish();
    }

    fn update_network(&mut self, effect: Effect) {
        let inner = self.update_inner();
        let installer = inner.controller.installer().clone();
        let Some(client) = inner.client.clone() else {
            // Sem cliente a consulta falha como falha de rede.
            return self.update_network_unavailable(effect);
        };
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let Some(done) = client.execute(effect, installer).await else {
                return;
            };
            let job = move |actor: &mut Actor| {
                let more = done.apply(&mut actor.update_inner().controller);
                actor.update_apply(more);
            };
            let _ = inbox.send(Msg::Run(Box::new(job))).await;
        });
    }

    /// Sem cliente HTTPS: devolve ao controller o que a rede devolveria.
    fn update_network_unavailable(&mut self, effect: Effect) {
        use crate::features::update::controller::FetchOutcome;
        use crate::features::update::installer::Failure;
        let controller = &mut self.update_inner().controller;
        let more = match effect {
            Effect::FetchRelease { reason, .. } => {
                controller.release_fetched(reason, FetchOutcome::Failed("sem cliente HTTPS".into()))
            }
            Effect::Download(update) => controller.prepared(
                update,
                Err(Failure::NotInstallable("o download falhou".into())),
            ),
            _ => Vec::new(),
        };
        self.update_apply(more);
    }
}

#[cfg(test)]
mod tests {
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::time::{Duration, SystemTime};

    use serde_json::{Value, json};

    use super::super::processes_commands::support::{Rig, request};
    use crate::commons::paths::Flavor;
    use crate::protocol::routes::FeatureRoute;

    async fn update(rig: &mut Rig, target: &str) -> Value {
        let reply = rig
            .call(FeatureRoute::Update, request("GET", target, None))
            .await;
        assert_eq!(reply.status, 200);
        reply.json
    }

    /// Um servidor local que responde qualquer pedido com `body` (nunca a
    /// internet).
    fn serve(body: String) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        std::thread::spawn(move || {
            for stream in listener.incoming().flatten().take(8) {
                let mut stream = stream;
                let mut buf = [0u8; 2048];
                let _ = stream.read(&mut buf);
                let head = format!(
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                    body.len()
                );
                let _ = stream.write_all(head.as_bytes());
                let _ = stream.write_all(body.as_bytes());
            }
        });
        base
    }

    /// Com os arquivos desta plataforma, que o app procura.
    fn release(tag: &str) -> String {
        let names = crate::features::update::AssetNames::default();
        json!({
            "tag_name": tag, "html_url": "https://example.com/r", "body": "novidades",
            "assets": [
                {"name": names.zip, "browser_download_url": "https://example.com/a.zip"},
                {"name": names.signature, "browser_download_url": "https://example.com/a.sig"},
            ],
        })
        .to_string()
    }

    #[tokio::test]
    async fn mostra_o_estado_e_grava_a_opcao_de_atualizar_sozinho() {
        let mut rig = Rig::new();
        let snapshot = update(&mut rig, "/update").await;
        assert_eq!(
            snapshot,
            json!({
                "auto": false, "installed": "9.9.9", "menu": "Procurar atualizações…",
                "staged": false, "state": "idle",
            })
        );
        let snapshot = update(&mut rig, "/update?auto=1").await;
        assert_eq!(snapshot["auto"], true);
        assert_eq!(
            std::fs::read_to_string(rig.data.join("update.json")).unwrap(),
            r#"{"auto":true}"#
        );
    }

    #[tokio::test]
    async fn consulta_a_release_pela_rede_e_vira_disponivel() {
        // Só o dev troca o endereço da consulta e aceita http.
        let mut rig = Rig::with_flavor(Flavor::Dev);
        let base = serve(release("v10.0.0"));
        let checking = update(&mut rig, &format!("/update?check=1&feed={base}/release")).await;
        assert_eq!(checking["state"], "checking");
        rig.settle().await;
        let after = update(&mut rig, "/update").await;
        assert_eq!(after["state"], "available");
        assert_eq!(after["version"], "10.0.0");
        assert_eq!(after["menu"], "Atualizar para a versão 10.0.0…");
    }

    #[tokio::test]
    async fn release_que_nao_e_mais_nova_ou_rede_que_cai_volta_ao_repouso() {
        let mut rig = Rig::with_flavor(Flavor::Dev);
        let base = serve(release("v9.9.9"));
        update(&mut rig, &format!("/update?check=1&feed={base}/release")).await;
        rig.settle().await;
        assert_eq!(update(&mut rig, "/update").await["state"], "idle");

        // Porta que ninguém atende: a consulta falha e o estado volta. No
        // Windows a conexão recusada leva uns 2 s (o SYN é repetido), mais que
        // o silêncio que o `settle` espera.
        update(&mut rig, "/update?check=1&feed=http://127.0.0.1:1/release").await;
        let mut state = serde_json::Value::Null;
        for _ in 0..40 {
            rig.settle().await;
            state = update(&mut rig, "/update").await["state"].clone();
            if state != "checking" {
                break;
            }
        }
        assert_eq!(state, "idle");
    }

    #[test]
    fn so_o_valor_1_desliga_as_consultas_automaticas() {
        use super::no_update_check;
        let with = |value: Option<&'static str>| {
            no_update_check(move |key| {
                (key == "EGEON_NO_UPDATE_CHECK")
                    .then(|| value.map(str::to_owned))
                    .flatten()
            })
        };
        assert!(with(Some("1")));
        for off in [None, Some(""), Some("0"), Some("true")] {
            assert!(!with(off), "{off:?}");
        }
    }

    // O estável consultaria o GitHub 4 s depois de abrir; com o interruptor
    // ligado o tique não agenda nem faz consulta nenhuma (o teste não vai à
    // internet: sem o interruptor ele iria).
    #[tokio::test]
    async fn com_o_interruptor_o_estavel_nao_consulta_na_partida_nem_depois() {
        let mut rig = Rig::new();
        assert!(
            rig.actor.update_inner().checks_off,
            "o teste nasce sem rede"
        );
        let t0 = SystemTime::now();
        rig.actor.update_tick(t0);
        rig.actor.update_tick(t0 + Duration::from_secs(10));
        rig.actor.update_tick(t0 + Duration::from_secs(7 * 3600));
        rig.settle().await;
        assert_eq!(update(&mut rig, "/update").await["state"], "idle");
        let inner = rig.actor.update_inner();
        assert!(inner.launch_at.is_none() && inner.periodic_at.is_none());
    }

    #[tokio::test]
    async fn no_dev_o_tique_nao_agenda_consulta_nenhuma() {
        // No dev o número da versão não diz nada: nada é consultado. (O
        // estável consultaria o GitHub, e teste não vai à internet.)
        let mut dev = Rig::with_flavor(Flavor::Dev);
        let t0 = SystemTime::now();
        dev.actor.update_tick(t0);
        dev.actor.update_tick(t0 + Duration::from_secs(60));
        dev.settle().await;
        assert_eq!(update(&mut dev, "/update").await["state"], "idle");
    }

    #[test]
    fn o_app_instalado_e_o_appimage_o_bundle_ou_o_executavel() {
        use std::ffi::OsStr;
        use std::path::PathBuf;

        use super::installed_app;
        let mounted = PathBuf::from("/tmp/.mount_EgeonAb12/usr/bin/egeon-app");
        let appimage = OsStr::new("/home/u/Apps/EgeonDeck-linux-x86_64.AppImage");
        assert_eq!(
            installed_app(Some(appimage), mounted.clone()),
            PathBuf::from("/home/u/Apps/EgeonDeck-linux-x86_64.AppImage")
        );
        // `.deb`, `cargo run`: o próprio executável, que não se troca.
        assert_eq!(installed_app(None, mounted.clone()), mounted);
        assert_eq!(
            installed_app(Some(OsStr::new("")), mounted.clone()),
            mounted
        );
        let in_bundle = PathBuf::from("/Applications/Egeon Deck.app/Contents/MacOS/egeon-app");
        assert_eq!(
            installed_app(None, in_bundle),
            PathBuf::from("/Applications/Egeon Deck.app")
        );
    }
}
