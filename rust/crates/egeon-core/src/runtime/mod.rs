//! O laço único dono do estado: recebe mensagens por canal e é o único que
//! altera o estado do app.
//!
//! - [`actor`] guarda os nós e os clientes do `/ui`; tudo o mais só manda
//!   mensagem para ele.
//! - [`conn`] atende uma conexão do socket: lê a requisição, pergunta ao ator
//!   e responde, ou abre o canal `/ui`.
//! - [`serve`] liga tudo: abre a escuta, aceita conexões, vigia o arquivo do
//!   socket e encerra os terminais na saída.

mod actor;
mod conn;
mod node_view;
mod org;

#[cfg(test)]
mod fakes;
pub mod install;
#[cfg(test)]
mod tests;

use std::ffi::OsString;
use std::future::Future;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use tokio::sync::{mpsc, watch};

use crate::commons::paths::{Flavor, Paths};
use crate::features::agent::store as agent_store;
use crate::features::node::launch::install_shell_hook;
use crate::features::workbench::model::WorkbenchConfig;
use crate::features::workspace::model::WorkspaceConfig;
use crate::features::worktree::git::Git;
use crate::features::worktree::service::main_repo;
use crate::ports::file_clone::FileCloner;
use crate::ports::installer::AppInstaller;
use crate::ports::links::FileLinks;
use crate::ports::local_conn::{LocalConnDriver, LocalConnError, LocalListener, Probe};
use crate::ports::notifier::Notifier;
use crate::ports::opener::Opener;
use crate::ports::procs::{AppDriver, ProcessDriver};
use crate::ports::pty::PtyDriver;
use crate::ports::screen::ScreenFactory;

use actor::Msg;

/// Mensagens na fila do ator antes de quem manda esperar. O leitor de pty
/// esperando é o que segura um `cat` gigante sem estourar memória.
const INBOX: usize = 1024;

/// De quanto em quanto tempo o vigia confere se o arquivo do socket ainda é o
/// nosso — `stat` num arquivo, como no Swift.
pub const WATCH_EVERY: Duration = Duration::from_secs(10);

/// As peças que dependem do sistema, entregues uma vez na partida.
#[derive(Clone)]
pub struct Drivers {
    pub pty: Arc<dyn PtyDriver>,
    pub screens: Arc<dyn ScreenFactory>,
    pub local: Arc<dyn LocalConnDriver>,
    pub procs: Arc<dyn ProcessDriver>,
    /// Notificação e som de atenção.
    pub notifier: Arc<dyn Notifier>,
    /// Apps abertos de pé por conta própria (US-303).
    pub apps: Arc<dyn AppDriver>,
    /// A troca do app instalado, na atualização.
    pub installer: Arc<dyn AppInstaller>,
    /// Abrir arquivo ou URL com o app padrão, e o alerta sonoro (⌘-clique).
    pub opener: Arc<dyn Opener>,
    /// Clonar arquivo ou pasta (o `clonefile` do APFS), na cópia do não
    /// versionado para a worktree.
    pub cloner: Arc<dyn FileCloner>,
    /// Link simbólico e permissão de execução: os links do multi-projeto e o
    /// script de cópia da worktree.
    pub links: Arc<dyn FileLinks>,
    /// Arquivo que roda: é como o catálogo acha o binário do CLI no `PATH`.
    /// O bit de execução muda por sistema, por isso vem do driver.
    pub is_executable: fn(&std::path::Path) -> bool,
    /// O TCC das pastas protegidas: zerar a recusa e o painel do Ajustes.
    pub folders: Arc<dyn crate::ports::folder_access::FolderPermissions>,
}

#[derive(Debug, Clone)]
pub struct Config {
    /// A pasta de dados (`~/.egeon-next` ou `EGEON_HOME`) e o que mora nela.
    pub paths: Paths,
    /// Onde o terminal abre quando o pedido não diz. É também o HOME do
    /// usuário, que resolve `~`.
    pub default_cwd: PathBuf,
    /// Qual cópia do app: dá o `EGEON_DECK` que marca os processos e o
    /// `EGEON_FLAVOR` que o `egeon` dos terminais usa para achar o socket.
    pub flavor: Flavor,
    /// O binário `egeon` que acompanha este app. Copiado para `<home>/bin` a
    /// cada partida, como o Swift escreve o `bin/egeon` no arranque: o CLI e
    /// os ganchos dos terminais são sempre os da versão que subiu.
    pub cli_binary: Option<PathBuf>,
    /// A UI lançou o core (`--exit-with-stdin`): pedido de tela que chega
    /// antes de ela assinar `app` espera por ela, em vez de responder "sem
    /// janela" na partida.
    pub ui_parent: bool,
    pub version: String,
    pub build: String,
}

#[derive(Debug, thiserror::Error)]
pub enum RuntimeError {
    #[error("não foi possível criar {}: {reason}", path.display())]
    Home { path: PathBuf, reason: String },
    #[error("já há um Egeon atendendo em {} ({}); este processo não sobe", path.display(), pid.map_or_else(|| "pid desconhecido".to_owned(), |p| format!("pid {p}")))]
    AlreadyRunning { path: PathBuf, pid: Option<u32> },
    #[error("não foi possível escutar em {}: {source}", path.display())]
    Listen {
        path: PathBuf,
        #[source]
        source: LocalConnError,
    },
}

/// Sobe o core e atende até `shutdown` resolver; então encerra os terminais e
/// larga o socket.
pub async fn serve(
    config: Config,
    drivers: Drivers,
    shutdown: impl Future<Output = ()>,
) -> Result<(), RuntimeError> {
    let home = config.paths.home();
    std::fs::create_dir_all(home).map_err(|e| RuntimeError::Home {
        path: home.to_owned(),
        reason: e.to_string(),
    })?;
    let path = config.paths.socket();

    // Instância única: uma segunda que subisse apagaria o socket da primeira,
    // que ficaria viva e inalcançável.
    if let Probe::Alive { pid } = drivers.local.probe(&path) {
        return Err(RuntimeError::AlreadyRunning { path, pid });
    }
    let listener = listen(&*drivers.local, &path)?;
    crate::log!("socket: escutando em {}", path.display());

    let org = load_org(&config, &drivers).await;
    let (save_tx, save_rx) = watch::channel(None);
    let saving = tokio::spawn(saver(config.paths.clone(), save_rx));
    let (tx, rx) = mpsc::channel(INBOX);
    let state = actor::Actor::new(config, drivers.clone(), tx.clone())
        .with_org(org)
        .with_saver(save_tx);
    let actor = tokio::spawn(state.run(rx));
    let clicking = tokio::spawn(forward_clicks(drivers.notifier.start(), tx.clone()));

    tokio::select! {
        () = accept_loop(listener, &drivers, &path, tx.clone()) => {}
        () = shutdown => {}
    }

    // O ator só termina depois de mandar o sinal a todos os terminais: é o que
    // "fechar o app mata os processos" promete.
    let (done_tx, done_rx) = tokio::sync::oneshot::channel();
    if tx.send(Msg::Shutdown { done: done_tx }).await.is_ok() {
        let _ = done_rx.await;
    }
    clicking.abort();
    drop(tx);
    let _ = actor.await;
    // O ator largou o canal ao terminar: o gravador grava o último retrato e
    // sai. Um arrasto feito segundos antes de fechar não se perde.
    let _ = saving.await;
    Ok(())
}

/// Os cliques nas notificações vão ao ator, um a um.
async fn forward_clicks(
    mut clicks: mpsc::Receiver<crate::ports::notifier::NoticeClick>,
    inbox: mpsc::Sender<Msg>,
) {
    while let Some(click) = clicks.recv().await {
        let job = move |actor: &mut actor::Actor| actor.notice_clicked(click);
        if inbox.send(Msg::Run(Box::new(job))).await.is_err() {
            return;
        }
    }
}

/// Uma gravação dos dois arquivos, numerada para não gravar o mesmo duas
/// vezes.
pub struct Snapshot {
    pub seq: u64,
    pub workspaces: Vec<WorkspaceConfig>,
    pub workbenches: Vec<WorkbenchConfig>,
}

/// O único que escreve `workspaces.json` e `workbenches.json`. Fica só com o
/// retrato mais novo: mudanças que chegam enquanto ele grava viram uma
/// gravação só, e uma gravação velha nunca passa por cima de uma nova.
async fn saver(paths: Paths, mut rx: watch::Receiver<Option<Arc<Snapshot>>>) {
    let mut saved = 0;
    loop {
        let open = rx.changed().await.is_ok();
        let snapshot = rx.borrow_and_update().clone();
        if let Some(snapshot) = snapshot
            && snapshot.seq != saved
        {
            saved = snapshot.seq;
            let paths = paths.clone();
            let errors = tokio::task::spawn_blocking(move || {
                org::save(&paths, &snapshot.workspaces, &snapshot.workbenches)
            })
            .await
            .unwrap_or_default();
            for error in errors {
                crate::log!("bancadas: {error}");
            }
        }
        if !open {
            return;
        }
    }
}

/// Carrega e concilia as bancadas antes de atender: o git do `reconcile` e
/// o disco não podem rodar dentro do ator.
async fn load_org(config: &Config, drivers: &Drivers) -> org::Org {
    let paths = config.paths.clone();
    let home = config.default_cwd.to_string_lossy().into_owned();
    let links = drivers.links.clone();
    // O git do usuário, com o PATH que os terminais recebem: o do launchd
    // não acha o git do Homebrew.
    let env: Vec<(OsString, OsString)> = crate::features::terminal::environment::for_child(
        &*drivers.pty,
        &paths.cli_dir(),
        &crate::features::processes::mark::inherited(),
    )
    .into_iter()
    .map(|(k, v)| (k.into(), v.into()))
    .collect();
    let cli_binary = config.cli_binary.clone();
    let flavor = config.flavor.identifier().to_owned();
    let user_shell = crate::features::terminal::shell::LaunchShell::new(drivers.pty.user_shell());
    let loaded = tokio::task::spawn_blocking(move || {
        let git = Git::new(env);
        let mut loaded = org::load(&paths, &home, |path| main_repo(&git, path));
        loaded.org.profiles = agent_store::load(paths.home());
        loaded.org.existing = org::probe_paths(loaded.org.watched_paths());
        loaded.org.denied = org::probe_access(loaded.org.bench_paths(), &loaded.org.home);
        loaded.org.web_profiles = actor::load_web_profiles(&paths.config(actor::WEB_PROFILES));
        // O gancho do shell é escrito a cada arranque, como no Swift: um app
        // novo traz o gancho novo.
        loaded
            .notes
            .extend(install_shell_hook(&paths.config("zsh")));
        // Os rcfiles do bash só onde o shell do usuário é o bash (decisão 53):
        // no macOS, que é sempre zsh, a pasta de dados fica como era.
        if user_shell.kind == crate::features::terminal::shell::ShellKind::Bash {
            loaded
                .notes
                .extend(crate::features::terminal::shell::install_bash_hook(
                    &paths.config(crate::features::terminal::shell::BASH_DIR),
                ));
        }
        // O binário `egeon`, os ganchos do Claude (o `--settings` de cada agente
        // aponta para eles: sem eles o CLI não relata início, fim de turno nem
        // pedido de permissão) e as skills: só o que mudou desde o último
        // arranque.
        let user_home = std::path::PathBuf::from(&home);
        // O teste nunca lê o ambiente de verdade: um `CLAUDE_CONFIG_DIR` do
        // desenvolvedor levaria as skills para a configuração dele.
        #[cfg(test)]
        let environment = |_: &str| None;
        #[cfg(not(test))]
        let environment = |key: &str| std::env::var(key).ok();
        loaded
            .notes
            .extend(install::install(&install::Installation {
                paths: &paths,
                bundled_egeon: cli_binary,
                profiles: &loaded.org.profiles,
                user_home: &user_home,
                environment: &environment,
                links: links.as_ref(),
                // Até o corte só a pasta do app recebe as skills (decisão 36).
                flavor: &flavor,
            }));
        if loaded.needs_save {
            let org = &loaded.org;
            for error in org::save(&paths, &org.state.workspaces, &org.state.workbenches) {
                crate::log!("bancadas: {error}");
            }
        }
        loaded
    })
    .await;
    match loaded {
        Ok(loaded) => {
            for note in &loaded.notes {
                crate::log!("bancadas: {note}");
            }
            crate::log!(
                "bancadas: {} carregadas em {} workspace(s)",
                loaded.org.state.workbenches.len(),
                loaded.org.state.workspaces.len()
            );
            loaded.org
        }
        Err(err) => {
            crate::log!("bancadas: a carga não terminou ({err}); começo sem nenhuma");
            org::Org::default()
        }
    }
}

fn listen(
    local: &dyn LocalConnDriver,
    path: &std::path::Path,
) -> Result<Box<dyn LocalListener>, RuntimeError> {
    local.listen(path).map_err(|source| match source {
        LocalConnError::AlreadyListening { pid } => RuntimeError::AlreadyRunning {
            path: path.to_owned(),
            pid,
        },
        source => RuntimeError::Listen {
            path: path.to_owned(),
            source,
        },
    })
}

/// Aceita conexões e vigia o arquivo do socket. Não volta: perder a escuta não
/// é motivo para derrubar os terminais, e o vigia tenta religar a cada volta.
async fn accept_loop(
    listener: Box<dyn LocalListener>,
    drivers: &Drivers,
    path: &std::path::Path,
    actor: mpsc::Sender<Msg>,
) {
    let local = &*drivers.local;
    let procs = drivers.procs.clone();
    let mut listener = Some(listener);
    let mut watch = tokio::time::interval(WATCH_EVERY);
    watch.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    watch.tick().await;
    loop {
        let accept = async {
            match &listener {
                Some(l) => l.accept().await,
                None => std::future::pending().await,
            }
        };
        tokio::select! {
            accepted = accept => match accepted {
                Ok(conn) => {
                    tokio::spawn(conn::serve(conn, actor.clone(), procs.clone()));
                }
                // Erro de uma conexão (o par desistiu no meio) não para a
                // escuta; o vigia cuida do caso de o arquivo ter sumido.
                Err(err) => crate::log!("socket: accept falhou: {err}"),
            },
            _ = watch.tick() => {
                if listener.as_ref().is_some_and(|l| l.is_current()) {
                    continue;
                }
                // Sem isso os ganchos do CLI param de chegar em silêncio: o app
                // segue de pé e ninguém mais o alcança.
                crate::log!("socket: o arquivo {} sumiu ou virou de outro processo — religando", path.display());
                // Larga antes de religar: o drop só apaga o arquivo se ainda for
                // o nosso, então não leva o de outra instância junto.
                listener = None;
                match listen(local, path) {
                    Ok(fresh) => listener = Some(fresh),
                    Err(err) => crate::log!("socket: não deu para religar: {err}"),
                }
            }
        }
    }
}
