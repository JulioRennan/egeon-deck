//! A regra da atualização: o que fazer em cada situação, sem rede nem tela.
//!
//! Máquina de estados que recebe o que aconteceu (clique, resposta da consulta,
//! download pronto) e devolve o que o core deve fazer — [`Effect`]. Nada aqui
//! espera: a consulta e o download são pedidos de fora, e o relógio das
//! consultas (4 s depois de abrir e a cada 6 h) é de quem liga.

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use serde_json::{Value, json};

use super::installer::{Failure, UpdateInstaller};
use super::policy::{Action, Reason, UpdatePolicy};
use super::release::{AssetNames, AvailableUpdate};
use super::settings::Settings;

/// A release mais recente do projeto.
pub const FEED: &str = "https://api.github.com/repos/JulioRennan/egeon-deck/releases/latest";

/// De quanto em quanto o core consulta ([`Reason::Periodic`]).
pub const CHECK_EVERY: Duration = Duration::from_secs(6 * 60 * 60);

/// Quanto depois de abrir o app o core faz a primeira consulta
/// ([`Reason::Launch`]).
pub const FIRST_CHECK_AFTER: Duration = Duration::from_secs(4);

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum State {
    Idle,
    Checking,
    Available(AvailableUpdate),
    Downloading(AvailableUpdate),
    Ready(String),
}

/// O que o core deve fazer a seguir.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Effect {
    /// `GET feed` com `User-Agent: EgeonDeck/<versão instalada>`; a resposta
    /// volta por [`UpdateController::release_fetched`].
    FetchRelease { reason: Reason, feed: String },
    /// Baixar a assinatura e o zip, rodar [`UpdateInstaller::prepare`] fora do
    /// ator, e responder por [`UpdateController::prepared`]. Download que
    /// falha é `Failure::NotInstallable("o download falhou")`.
    Download(AvailableUpdate),
    /// Mostrar o aviso de versão nova.
    Prompt(AvailableUpdate),
    /// Uma mensagem: título e texto.
    Message { title: String, text: String },
    /// Encerrar o app: a troca já está esperando ele sair.
    Terminate,
}

/// O que veio da consulta à release.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FetchOutcome {
    /// Resposta 200, com o corpo.
    Body(Vec<u8>),
    /// Falha de rede ou status diferente de 200, com o motivo para o log.
    Failed(String),
}

#[derive(Debug, Clone)]
pub struct UpdateConfig {
    pub installed_version: String,
    /// "Egeon Deck" ou "Egeon Deck (dev)", para a mensagem de "última versão".
    pub display_name: String,
    /// Só no estável: o dev é reconstruído a toda hora, e o número dele não
    /// diz nada.
    pub is_dev: bool,
    /// O pid do app, que a troca espera sair.
    pub app_pid: u32,
    /// `update.json`.
    pub settings_file: PathBuf,
    /// Onde o processo da troca escreve o que fez (`update.log`).
    pub swap_log: PathBuf,
    /// A consulta padrão; a rota `/update` só a troca no dev.
    pub feed: String,
    /// Os arquivos que a release traz.
    pub assets: AssetNames,
}

pub struct UpdateController {
    state: State,
    /// O estado de antes da consulta em andamento, para onde voltar se ela
    /// falhar.
    before_check: Option<State>,
    settings: Settings,
    config: UpdateConfig,
    installer: Arc<UpdateInstaller>,
    restart_when_ready: bool,
    swap_launched: bool,
}

impl UpdateController {
    pub fn new(installer: Arc<UpdateInstaller>, config: UpdateConfig) -> Self {
        let settings = Settings::load(&config.settings_file);
        UpdateController {
            state: State::Idle,
            before_check: None,
            settings,
            config,
            installer,
            restart_when_ready: false,
            swap_launched: false,
        }
    }

    pub fn state(&self) -> &State {
        &self.state
    }

    pub fn auto(&self) -> bool {
        self.settings.auto
    }

    pub fn installer(&self) -> &Arc<UpdateInstaller> {
        &self.installer
    }

    /// Ao abrir o app. `true` quando o core deve agendar as consultas
    /// ([`FIRST_CHECK_AFTER`] e [`CHECK_EVERY`]).
    pub fn start(&self) -> bool {
        if self.config.is_dev {
            return false;
        }
        // Bundle que esperava uma troca que não aconteceu (o app caiu): pode
        // estar velho, e baixar de novo é barato.
        self.installer.discard_staged();
        true
    }

    pub fn set_auto(&mut self, on: bool) -> Vec<Effect> {
        self.settings.auto = on;
        self.settings.save(&self.config.settings_file);
        crate::log!(
            "atualização: automático {}",
            if on { "ligado" } else { "desligado" }
        );
        match (&self.state, on) {
            (State::Available(update), true) => {
                let update = update.clone();
                self.download(update)
            }
            _ => Vec::new(),
        }
    }

    pub fn check(&mut self, reason: Reason, feed: Option<&str>) -> Vec<Effect> {
        if matches!(self.state, State::Checking | State::Downloading(_)) {
            return Vec::new();
        }
        let previous = std::mem::replace(&mut self.state, State::Checking);
        self.before_check = Some(previous);
        vec![Effect::FetchRelease {
            reason,
            feed: feed.unwrap_or(&self.config.feed).to_owned(),
        }]
    }

    /// A resposta da consulta pedida por [`Effect::FetchRelease`].
    pub fn release_fetched(&mut self, reason: Reason, outcome: FetchOutcome) -> Vec<Effect> {
        let previous = self.before_check.take().unwrap_or(State::Idle);
        let parsed = match &outcome {
            FetchOutcome::Body(body) => AvailableUpdate::parse(body, &self.config.assets),
            FetchOutcome::Failed(_) => None,
        };
        let Some(update) = parsed else {
            self.state = previous;
            let why = match &outcome {
                FetchOutcome::Failed(why) => why.as_str(),
                FetchOutcome::Body(_) => "resposta inesperada",
            };
            crate::log!("atualização: consulta falhou — {why}");
            return if reason == Reason::Manual {
                vec![message(
                    "Não deu para procurar atualizações",
                    "Confira a internet e tente de novo.",
                )]
            } else {
                Vec::new()
            };
        };
        self.handle(update, reason, previous)
    }

    fn handle(&mut self, update: AvailableUpdate, reason: Reason, previous: State) -> Vec<Effect> {
        let newer = update.is_newer(&self.config.installed_version);
        crate::log!(
            "atualização: publicada {}, instalada {}",
            update.version,
            self.config.installed_version
        );
        // Já baixada: a versão pronta continua valendo.
        if let State::Ready(version) = &previous
            && *version == update.version
        {
            self.state = previous;
            return if reason == Reason::Manual {
                vec![Effect::Prompt(update)]
            } else {
                Vec::new()
            };
        }
        self.state = if newer {
            State::Available(update.clone())
        } else {
            State::Idle
        };
        match UpdatePolicy::action(newer, reason, self.settings.auto) {
            Action::Nothing | Action::ShowInMenu => Vec::new(),
            Action::SayUpToDate => vec![message(
                "Você está na última versão",
                &format!(
                    "{} {}.",
                    self.config.display_name, self.config.installed_version
                ),
            )],
            Action::Prompt => vec![Effect::Prompt(update)],
            Action::DownloadQuietly => self.download(update),
        }
    }

    /// O clique em "Atualizar e reiniciar".
    pub fn update_and_restart(&mut self, update: AvailableUpdate) -> Vec<Effect> {
        if matches!(&self.state, State::Ready(version) if *version == update.version) {
            return self.restart();
        }
        self.restart_when_ready = true;
        self.download(update)
    }

    /// O clique no menu quando já está baixada.
    pub fn restart(&mut self) -> Vec<Effect> {
        match self.launch_swap(true) {
            Ok(()) => vec![Effect::Terminate],
            Err(effect) => vec![effect],
        }
    }

    fn download(&mut self, update: AvailableUpdate) -> Vec<Effect> {
        if !self.installer.can_install() {
            self.restart_when_ready = false;
            self.state = State::Available(update);
            return vec![self.fail(&format!(
                "O app não está num lugar onde possa ser trocado ({}). {}",
                self.installer.destination().display(),
                cannot_install_hint(std::env::consts::OS)
            ))];
        }
        if update.signature.is_none() {
            self.restart_when_ready = false;
            let text = format!(
                "A versão {} foi publicada sem assinatura, e o app não instala o que não pode conferir.",
                update.version
            );
            self.state = State::Available(update);
            return vec![self.fail(&text)];
        }
        crate::log!("atualização: baixando {}", update.version);
        self.state = State::Downloading(update.clone());
        vec![Effect::Download(update)]
    }

    /// O resultado de [`Effect::Download`] depois do `prepare`.
    pub fn prepared(
        &mut self,
        update: AvailableUpdate,
        outcome: Result<String, Failure>,
    ) -> Vec<Effect> {
        match outcome {
            Ok(version) => {
                crate::log!(
                    "atualização: {version} pronta em {}",
                    self.installer.staged().display()
                );
                self.state = State::Ready(version);
                if std::mem::take(&mut self.restart_when_ready) {
                    return self.restart();
                }
                Vec::new()
            }
            Err(error) => {
                self.restart_when_ready = false;
                self.state = State::Available(update);
                vec![self.fail(&format!("A atualização não foi instalada: {error}"))]
            }
        }
    }

    fn fail(&self, text: &str) -> Effect {
        crate::log!("atualização: {text}");
        message("Não deu para atualizar", text)
    }

    /// Solta a troca, uma vez só. `Err` traz a mensagem pronta.
    fn launch_swap(&mut self, reopen: bool) -> Result<(), Effect> {
        if self.swap_launched {
            return Ok(());
        }
        match self
            .installer
            .launch_swap(self.config.app_pid, reopen, &self.config.swap_log)
        {
            Ok(()) => {
                self.swap_launched = true;
                crate::log!("atualização: troca agendada para a saída do app");
                Ok(())
            }
            Err(error) => Err(self.fail(&format!("Não consegui preparar a troca: {error}"))),
        }
    }

    /// O app está saindo: com a opção ligada e a versão pronta, a troca vai
    /// agora.
    pub fn application_will_terminate(&mut self) -> Vec<Effect> {
        if !(self.settings.auto
            && matches!(self.state, State::Ready(_))
            && self.installer.is_staged())
        {
            return Vec::new();
        }
        self.launch_swap(false).err().into_iter().collect()
    }

    // ---- Menu

    pub fn menu_title(&self) -> String {
        match &self.state {
            State::Idle => "Procurar atualizações…".to_owned(),
            State::Checking => "Procurando atualizações…".to_owned(),
            State::Available(update) => {
                format!("Atualizar para a versão {}…", update.version)
            }
            State::Downloading(update) => format!("Baixando a versão {}…", update.version),
            State::Ready(version) => {
                format!("Reiniciar para atualizar para a versão {version}")
            }
        }
    }

    pub fn menu_enabled(&self) -> bool {
        !matches!(self.state, State::Checking | State::Downloading(_))
    }

    pub fn menu_clicked(&mut self) -> Vec<Effect> {
        match &self.state {
            State::Available(update) => vec![Effect::Prompt(update.clone())],
            State::Ready(_) => vec![Effect::Prompt(self.ready_update())],
            _ => self.check(Reason::Manual, None),
        }
    }

    /// A versão pronta, para o aviso: as novidades já não importam nesse ponto.
    fn ready_update(&self) -> AvailableUpdate {
        let version = match &self.state {
            State::Ready(ready) => ready.clone(),
            _ => self.config.installed_version.clone(),
        };
        AvailableUpdate {
            version,
            notes: String::new(),
            page: FEED.to_owned(),
            zip: FEED.to_owned(),
            signature: None,
        }
    }

    /// `/update?install=1`: o mesmo que o clique, sem o aviso.
    pub fn install_available(&mut self) -> Vec<Effect> {
        match &self.state {
            State::Available(update) => {
                let update = update.clone();
                self.update_and_restart(update)
            }
            State::Ready(_) => self.restart(),
            _ => Vec::new(),
        }
    }

    /// O estado como dados, para a rota `/update`.
    pub fn snapshot(&self) -> Value {
        let mut out = json!({
            "auto": self.settings.auto,
            "installed": self.config.installed_version,
            "menu": self.menu_title(),
            "staged": self.installer.is_staged(),
        });
        let (state, version) = match &self.state {
            State::Idle => ("idle", None),
            State::Checking => ("checking", None),
            State::Available(update) => ("available", Some(update.version.clone())),
            State::Downloading(update) => ("downloading", Some(update.version.clone())),
            State::Ready(version) => ("ready", Some(version.clone())),
        };
        out["state"] = json!(state);
        if let Some(version) = version {
            out["version"] = json!(version);
        }
        out
    }

    /// A rota `GET /update[?check=1][&feed=url][&prompt=1][&install=1][&auto=0|1]`:
    /// aplica os parâmetros na ordem do Swift. O `feed` só vale no dev — é por
    /// onde a rota testa com uma release falsa, e a assinatura continua
    /// valendo.
    pub fn control(
        &mut self,
        query: &std::collections::HashMap<String, String>,
    ) -> (Vec<Effect>, Value) {
        let mut effects = Vec::new();
        if let Some(auto) = query.get("auto") {
            effects.extend(self.set_auto(auto == "1"));
        }
        let feed = if self.config.is_dev {
            query.get("feed").map(String::as_str)
        } else {
            None
        };
        if query.get("check").is_some_and(|v| v == "1") {
            effects.extend(self.check(Reason::Periodic, feed));
        }
        if query.get("prompt").is_some_and(|v| v == "1") {
            effects.extend(self.menu_clicked());
        }
        if query.get("install").is_some_and(|v| v == "1") {
            effects.extend(self.install_available());
        }
        (effects, self.snapshot())
    }
}

fn message(title: &str, text: &str) -> Effect {
    Effect::Message {
        title: title.to_owned(),
        text: text.to_owned(),
    }
}

/// O que fazer quando o app não se troca. No Linux é o `.deb` (ou o binário
/// solto): só o AppImage se troca sozinho, e o resto baixa da página.
pub fn cannot_install_hint(os: &str) -> &'static str {
    match os {
        "linux" => "Só o AppImage se atualiza sozinho: baixe a versão nova na página da release.",
        _ => "Mova-o para /Applications e tente de novo.",
    }
}
