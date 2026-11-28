//! Os botões da cortina "sem acesso" (decisão 39, `guardAccess`/`askAccess`
//! do Swift, main.swift:870-915).

use serde_json::json;

use super::{Actor, ClientId, Msg};
use crate::features::workbench::access::FolderAccess;
use crate::ports::opener::OpenTarget;
use crate::protocol::message::Reply;
use crate::protocol::org::WorkbenchRef;

impl Actor {
    /// "Abrir Ajustes": o painel de privacidade, como o `NSWorkspace.open` do
    /// Swift.
    pub(super) fn access_open_settings(&mut self, re: u64, r: &WorkbenchRef) -> Reply {
        if self.org.index_of(&r.workbench).is_none() {
            return Reply::err(re, format!("bancada desconhecida '{}'", r.workbench));
        }
        let Some(url) = self.drivers.folders.settings_url() else {
            return Reply::err(re, "este sistema não tem o painel de privacidade");
        };
        if self.drivers.opener.open(&OpenTarget::Url(url)) {
            Reply::ok(re)
        } else {
            Reply::err(re, "o sistema não abriu o painel de privacidade")
        }
    }

    /// "Pedir de novo": zera a recusa do macOS e confere, fora do ator (o
    /// sistema pode mostrar o pedido e esperar você). A resposta sai quando
    /// a conferência volta; a cortina e os terminais seguem a releitura.
    pub(super) fn access_ask_again(
        &mut self,
        client: ClientId,
        re: u64,
        r: &WorkbenchRef,
    ) -> Option<Reply> {
        let Some(index) = self.org.index_of(&r.workbench) else {
            return Some(Reply::err(
                re,
                format!("bancada desconhecida '{}'", r.workbench),
            ));
        };
        let home = self.org.home.clone();
        let path = self.org.state.workbenches[index].url_path(&home);
        let folders = self.drivers.folders.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let checked = path.clone();
            let result = tokio::task::spawn_blocking(move || {
                FolderAccess::request(&checked, &home, &*folders)
            })
            .await
            .unwrap_or(FolderAccess::Ok);
            let job = move |actor: &mut Actor| {
                let mut denied = actor.org.denied.clone();
                let (name, message) = match &result {
                    FolderAccess::Ok => {
                        denied.remove(&path);
                        ("ok", None)
                    }
                    FolderAccess::Missing => {
                        denied.remove(&path);
                        ("missing", None)
                    }
                    FolderAccess::Denied { folder } => {
                        denied.insert(path.clone(), folder.clone());
                        ("denied", result.message())
                    }
                };
                if actor.access_changed(denied) {
                    actor.publish_org();
                }
                let reply = match message {
                    Some(message) => Reply::with(re, &json!({"access": name, "message": message})),
                    None => Reply::with(re, &json!({"access": name})),
                };
                actor.send_reply(client, &reply);
            };
            let _ = inbox.send(Msg::Run(Box::new(job))).await;
        });
        None
    }
}
