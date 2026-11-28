//! A central de notificações do freedesktop (`org.freedesktop.Notifications`,
//! pelo D-Bus de sessão) e os sons do tema.

mod sound;

use std::collections::HashMap;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, PoisonError};

use egeon_core::log;
use egeon_core::ports::notifier::{Notice, NoticeClick};
use futures_util::StreamExt;
use tokio::sync::mpsc;
use zbus::zvariant::Value;
use zbus::{Connection, MatchRule, MessageStream};

pub(super) use sound::{Sounds, beep};

/// Cliques pendentes de leitura pelo core.
const CLICK_CAPACITY: usize = 16;
/// Avisos e retiradas a caminho da central. Cheio é a central travada: o
/// aviso a mais se perde, e o terminal que o gerou segue.
const COMMAND_CAPACITY: usize = 64;

const SERVICE: &str = "org.freedesktop.Notifications";
const PATH: &str = "/org/freedesktop/Notifications";
const APP_NAME: &str = "Egeon Deck";
/// O nome do `.desktop` do app: a central mostra o ícone e o nome dele.
const DESKTOP_ENTRY: &str = "dev.duckcoder.egeondeck.next";
/// O som de mensagem do tema freedesktop, que a central toca quando sabe tocar.
const SOUND_NAME: &str = "message-new-instant";
/// A ação que a central dispara no clique no corpo do aviso.
const DEFAULT_ACTION: &str = "default";

enum Command {
    Post(Notice),
    Withdraw(String),
}

#[derive(Default)]
pub(super) struct Center {
    authorized: Arc<AtomicBool>,
    commands: Mutex<Option<mpsc::Sender<Command>>>,
}

impl Center {
    /// Como no macOS fora de um `.app`, a central só existe no app empacotado:
    /// `cargo test` e `cargo run` não põem aviso na tela de quem desenvolve.
    pub(super) fn start(&self) -> mpsc::Receiver<NoticeClick> {
        let (clicks, receiver) = mpsc::channel(CLICK_CAPACITY);
        if !is_packaged() {
            return receiver;
        }
        let Ok(runtime) = tokio::runtime::Handle::try_current() else {
            log!("notificação: sem runtime tokio, a central não sobe");
            return receiver;
        };
        let (commands, queue) = mpsc::channel(COMMAND_CAPACITY);
        *self.commands.lock().unwrap_or_else(PoisonError::into_inner) = Some(commands);
        let authorized = Arc::clone(&self.authorized);
        runtime.spawn(async move {
            match Connection::session().await {
                Ok(connection) => serve(connection, queue, clicks, authorized).await,
                Err(error) => log!("notificação: sem D-Bus de sessão — {error}"),
            }
        });
        receiver
    }

    pub(super) fn authorized(&self) -> bool {
        self.authorized.load(Ordering::Relaxed)
    }

    pub(super) fn post(&self, notice: Notice) {
        self.send(Command::Post(notice));
    }

    pub(super) fn withdraw(&self, identifier: &str) {
        self.send(Command::Withdraw(identifier.to_owned()));
    }

    fn send(&self, command: Command) {
        let commands = self.commands.lock().unwrap_or_else(PoisonError::into_inner);
        if let Some(commands) = commands.as_ref() {
            let _ = commands.try_send(command);
        }
    }
}

/// Empacotado é o AppImage (que define `$APPIMAGE`) ou o `.deb` (que instala
/// sob `/usr` ou `/opt`).
fn is_packaged() -> bool {
    let exe = std::env::current_exe().unwrap_or_default();
    packaged(std::env::var_os("APPIMAGE").is_some(), &exe)
}

fn packaged(has_appimage: bool, exe: &Path) -> bool {
    has_appimage || exe.starts_with("/usr") || exe.starts_with("/opt")
}

/// Um aviso entregue: o id que a central deu e o terminal dele.
struct Delivered {
    id: u32,
    workbench: String,
    node: String,
}

/// O dono da conexão: entrega os avisos em ordem e traduz os sinais da
/// central em cliques.
async fn serve(
    connection: Connection,
    mut queue: mpsc::Receiver<Command>,
    clicks: mpsc::Sender<NoticeClick>,
    authorized: Arc<AtomicBool>,
) {
    let capabilities = capabilities(&connection).await;
    // Sem som próprio, a central avisa calada e o som de atenção do core toca.
    authorized.store(capabilities.iter().any(|c| c == "sound"), Ordering::Relaxed);
    log!("notificação: central com {}", capabilities.join(", "));
    let mut signals = match signals(&connection).await {
        Ok(stream) => Some(stream),
        Err(error) => {
            log!("notificação: sem os sinais da central, o clique não chega — {error}");
            None
        }
    };
    let mut delivered: HashMap<String, Delivered> = HashMap::new();
    loop {
        let next_signal = async {
            match signals.as_mut() {
                Some(stream) => stream.next().await,
                None => std::future::pending().await,
            }
        };
        tokio::select! {
            command = queue.recv() => match command {
                Some(Command::Post(notice)) => post(&connection, &mut delivered, notice).await,
                Some(Command::Withdraw(identifier)) => {
                    if let Some(old) = delivered.remove(&identifier) {
                        close(&connection, old.id).await;
                    }
                }
                None => return,
            },
            Some(Ok(message)) = next_signal => {
                on_signal(&message, &mut delivered, &clicks);
            }
        }
    }
}

async fn capabilities(connection: &Connection) -> Vec<String> {
    let reply = connection
        .call_method(Some(SERVICE), PATH, Some(SERVICE), "GetCapabilities", &())
        .await;
    match reply.and_then(|reply| reply.body().deserialize::<Vec<String>>()) {
        Ok(capabilities) => capabilities,
        Err(error) => {
            log!("notificação: a central não respondeu — {error}");
            Vec::new()
        }
    }
}

async fn signals(connection: &Connection) -> zbus::Result<MessageStream> {
    let rule = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface(SERVICE)?
        .path(PATH)?
        .build();
    MessageStream::for_match_rule(rule, connection, Some(CLICK_CAPACITY)).await
}

/// O aviso novo de um terminal substitui o anterior dele (`replaces_id`), em
/// vez de empilhar, como o identificador faz no macOS.
async fn post(connection: &Connection, delivered: &mut HashMap<String, Delivered>, notice: Notice) {
    let replaces = delivered.get(&notice.identifier).map_or(0, |d| d.id);
    let hints: HashMap<&str, Value<'_>> = HashMap::from([
        ("sound-name", Value::from(SOUND_NAME)),
        ("desktop-entry", Value::from(DESKTOP_ENTRY)),
    ]);
    let body = (
        APP_NAME,
        replaces,
        "",
        notice.title.as_str(),
        notice.body.as_str(),
        vec![DEFAULT_ACTION, "Abrir"],
        hints,
        -1i32,
    );
    let reply = connection
        .call_method(Some(SERVICE), PATH, Some(SERVICE), "Notify", &body)
        .await;
    let (workbench, node) = (notice.workbench, notice.node);
    match reply.and_then(|reply| reply.body().deserialize::<u32>()) {
        Ok(id) => {
            log!("notificação[{workbench}/{node}]: {}", notice.body);
            delivered.insert(
                notice.identifier,
                Delivered {
                    id,
                    workbench,
                    node,
                },
            );
        }
        Err(error) => log!("notificação[{workbench}/{node}]: falhou — {error}"),
    }
}

async fn close(connection: &Connection, id: u32) {
    let _ = connection
        .call_method(
            Some(SERVICE),
            PATH,
            Some(SERVICE),
            "CloseNotification",
            &(id,),
        )
        .await;
}

fn on_signal(
    message: &zbus::Message,
    delivered: &mut HashMap<String, Delivered>,
    clicks: &mpsc::Sender<NoticeClick>,
) {
    let header = message.header();
    let Some(member) = header.member() else {
        return;
    };
    match member.as_str() {
        "ActionInvoked" => {
            let Ok((id, action)) = message.body().deserialize::<(u32, String)>() else {
                return;
            };
            if action != DEFAULT_ACTION {
                return;
            }
            if let Some(d) = delivered.values().find(|d| d.id == id) {
                // Cheio é a UI sem ler cliques: o mais novo não vale esperar.
                let _ = clicks.try_send(NoticeClick {
                    workbench: d.workbench.clone(),
                    node: d.node.clone(),
                });
            }
        }
        // Fechado (clicado, dispensado, expirado): um aviso novo do terminal
        // não substitui o que já não está na tela.
        "NotificationClosed" => {
            if let Ok((id, _reason)) = message.body().deserialize::<(u32, u32)>() {
                delivered.retain(|_, d| d.id != id);
            }
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::*;

    #[test]
    fn so_o_app_empacotado_tem_central() {
        assert!(packaged(
            true,
            Path::new("/home/u/Apps/x/usr/bin/egeon-app")
        ));
        assert!(packaged(false, Path::new("/usr/lib/egeon-deck/egeon-app")));
        assert!(packaged(false, Path::new("/opt/egeon-deck/egeon-app")));
        assert!(!packaged(
            false,
            Path::new("/home/u/egeon/rust/target/debug/egeon-app")
        ));
        assert!(!packaged(false, Path::new("/usrx/egeon-app")));
    }

    /// Uma central falsa: guarda o que recebeu e devolve ids em sequência.
    async fn fake_center(
        connection: Connection,
        log: mpsc::Sender<(String, u32, String)>,
    ) -> zbus::Result<()> {
        connection.request_name(SERVICE).await?;
        let rule = MatchRule::builder()
            .msg_type(zbus::message::Type::MethodCall)
            .interface(SERVICE)?
            .build();
        let mut calls = MessageStream::for_match_rule(rule, &connection, None).await?;
        let mut next_id = 0u32;
        while let Some(Ok(call)) = calls.next().await {
            let header = call.header();
            let member = header.member().map(|m| m.to_string()).unwrap_or_default();
            match member.as_str() {
                "GetCapabilities" => {
                    connection
                        .reply(&header, &(vec!["body", "actions", "sound"],))
                        .await?;
                }
                "Notify" => {
                    type Notify<'a> = (
                        String,
                        u32,
                        String,
                        String,
                        String,
                        Vec<String>,
                        HashMap<String, zbus::zvariant::OwnedValue>,
                        i32,
                    );
                    let (_, replaces, _, title, ..): Notify<'_> = call.body().deserialize()?;
                    let id = if replaces == 0 {
                        next_id += 1;
                        next_id
                    } else {
                        replaces
                    };
                    let _ = log.send(("Notify".into(), id, title)).await;
                    connection.reply(&header, &(id,)).await?;
                }
                "CloseNotification" => {
                    let (id,): (u32,) = call.body().deserialize()?;
                    let _ = log.send(("Close".into(), id, String::new())).await;
                    connection.reply(&header, &()).await?;
                }
                _ => {}
            }
        }
        Ok(())
    }

    fn notice(identifier: &str, title: &str) -> Notice {
        Notice {
            identifier: identifier.into(),
            title: title.into(),
            body: "rodar um comando".into(),
            workbench: "deck".into(),
            node: identifier.into(),
        }
    }

    /// Só num barramento privado, para nenhum aviso ir à tela de quem roda:
    /// `dbus-run-session -- cargo test -p egeon-driver --lib notifier -- --ignored`.
    #[tokio::test]
    #[ignore = "precisa de um D-Bus privado (dbus-run-session)"]
    async fn substitui_retira_e_entrega_o_clique() -> zbus::Result<()> {
        let step = Duration::from_secs(5);
        let server = Connection::session().await?;
        let (log_tx, mut log) = mpsc::channel(16);
        let center_side = server.clone();
        tokio::spawn(async move { fake_center(center_side, log_tx).await });
        tokio::time::sleep(Duration::from_millis(100)).await;

        let (commands, queue) = mpsc::channel(8);
        let (clicks, mut clicked) = mpsc::channel(8);
        let authorized = Arc::new(AtomicBool::new(false));
        let client = Connection::session().await?;
        tokio::spawn(serve(client, queue, clicks, Arc::clone(&authorized)));

        let _ = commands.send(Command::Post(notice("t1", "primeiro"))).await;
        let _ = commands.send(Command::Post(notice("t1", "segundo"))).await;
        let _ = commands.send(Command::Post(notice("t2", "outro"))).await;
        let got = |entry: Option<(String, u32, String)>| entry.unwrap_or_default();
        let first = got(tokio::time::timeout(step, log.recv()).await.ok().flatten());
        let second = got(tokio::time::timeout(step, log.recv()).await.ok().flatten());
        let third = got(tokio::time::timeout(step, log.recv()).await.ok().flatten());
        assert_eq!(first, ("Notify".into(), 1, "primeiro".into()));
        // O mesmo terminal substitui o aviso dele; o outro ganha id próprio.
        assert_eq!(second, ("Notify".into(), 1, "segundo".into()));
        assert_eq!(third, ("Notify".into(), 2, "outro".into()));
        assert!(authorized.load(Ordering::Relaxed));

        server
            .emit_signal(
                None::<&str>,
                PATH,
                SERVICE,
                "ActionInvoked",
                &(2u32, DEFAULT_ACTION),
            )
            .await?;
        let click = tokio::time::timeout(step, clicked.recv())
            .await
            .ok()
            .flatten();
        assert_eq!(
            click,
            Some(NoticeClick {
                workbench: "deck".into(),
                node: "t2".into()
            })
        );

        let _ = commands.send(Command::Withdraw("t1".into())).await;
        let closed = got(tokio::time::timeout(step, log.recv()).await.ok().flatten());
        assert_eq!(closed, ("Close".into(), 1, String::new()));
        Ok(())
    }
}
