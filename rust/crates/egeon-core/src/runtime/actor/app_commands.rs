//! Dono: `cli`. O tópico `app` (decisão 34) dentro do ator: o estado da
//! atualização e da limpeza de órfãos para quem assina, os efeitos que o core
//! pede à UI e os comandos do menu e do aviso.
//!
//! O estado mora nas features (`update_commands`, `processes_commands`); aqui
//! só se junta, se publica e se despacha o gesto da UI para a feature certa.

use super::Actor;
use crate::ports::opener::OpenTarget;
use crate::protocol::app::{AppEffect, AppState, OpenUrl};
use crate::protocol::message::{CommandKind, Event, EventBody, Reply, Topic};

impl Actor {
    /// O estado inteiro do tópico.
    pub(super) fn app_state(&mut self) -> AppState {
        AppState {
            update: self.update_view(),
            reaper: self.reaper_view(),
        }
    }

    /// O que vai a quem assina `app`.
    pub(super) fn app_snapshot(&mut self) -> Event {
        Event {
            topic: Topic::App,
            body: EventBody::App(self.app_state()),
        }
    }

    /// O estado novo a quem assina; sem assinante não monta nada.
    pub(super) fn app_publish(&mut self) {
        if !self
            .clients
            .values()
            .any(|c| c.topics.contains(&Topic::App))
        {
            return;
        }
        let event = self.app_snapshot();
        self.publish(&event);
    }

    /// Um efeito de uma vez só para quem assina `app`.
    pub(super) fn app_effect(&mut self, effect: AppEffect) {
        self.publish(&Event {
            topic: Topic::App,
            body: EventBody::AppEffect(effect),
        });
    }

    /// Os comandos do menu de atualização e da limpeza de órfãos.
    pub(super) fn app_command(&mut self, re: u64, kind: CommandKind) -> Reply {
        let outcome = match kind {
            CommandKind::UpdateMenu => {
                self.update_menu_clicked();
                Ok(())
            }
            CommandKind::UpdateAnswer(answer) => self.update_answer(answer),
            CommandKind::UpdateAuto(auto) => {
                self.update_set_auto(auto.on);
                Ok(())
            }
            CommandKind::ReaperEnabled(reaper) => {
                self.reaper_set_enabled(reaper.on);
                Ok(())
            }
            other => Err(format!("{} não é do tópico app", other.name())),
        };
        self.app_publish();
        match outcome {
            Ok(()) => Reply::ok(re),
            Err(error) => Reply::err(re, error),
        }
    }

    /// O link no navegador: quem decide se abre é o sistema, e o texto
    /// inválido (o `URL(string:)` do Swift dá nulo) volta como recusa.
    pub(super) fn open_url(&mut self, re: u64, open: OpenUrl) -> Reply {
        if self.drivers.opener.open(&OpenTarget::Url(open.url.clone())) {
            Reply::ok(re)
        } else {
            crate::log!("chat: o sistema não abriu {}", open.url);
            Reply::err(re, "o sistema não abriu o link")
        }
    }
}

#[cfg(test)]
mod tests {
    use std::io::{Read, Write};
    use std::net::TcpListener;

    use serde_json::{Value, json};
    use tokio::sync::{mpsc, oneshot};

    use super::super::processes_commands::support::{Rig, request};
    use super::super::{ClientId, Msg, WireLine};
    use crate::commons::paths::Flavor;
    use crate::protocol::message::parse_command;
    use crate::protocol::routes::FeatureRoute;

    struct Ui {
        id: ClientId,
        lines: mpsc::Receiver<WireLine>,
        /// A ponta que a conexão esperaria para fechar; segurá-la mantém o cliente vivo.
        _closed: oneshot::Receiver<()>,
    }

    async fn ui(rig: &mut Rig) -> Ui {
        let (queue, lines) = mpsc::channel(64);
        let (alive, closed) = oneshot::channel();
        let (reply, got) = oneshot::channel();
        rig.actor.handle(Msg::UiOpen {
            queue,
            alive,
            reply,
        });
        Ui {
            id: got.await.unwrap(),
            lines,
            _closed: closed,
        }
    }

    fn send(rig: &mut Rig, ui: &Ui, command: Value) {
        let command = parse_command(&command.to_string()).unwrap();
        rig.actor.handle(Msg::UiCommand {
            client: ui.id,
            command,
        });
    }

    fn drain(ui: &mut Ui) -> Vec<Value> {
        let mut out = Vec::new();
        while let Ok(line) = ui.lines.try_recv() {
            out.push(serde_json::from_slice(&line).unwrap());
        }
        out
    }

    /// A resposta do comando `re` no meio do que chegou.
    fn reply_of(got: &[Value], re: u64) -> Value {
        got.iter()
            .find(|l| l["re"] == re)
            .cloned()
            .expect("sem resposta")
    }

    /// Os estados do tópico `app` que chegaram, em ordem.
    fn states(got: &[Value]) -> Vec<Value> {
        got.iter()
            .filter(|l| l["topic"] == "app" && l.get("update").is_some())
            .cloned()
            .collect()
    }

    fn idle() -> Value {
        json!({
            "topic": "app",
            "update": {
                "state": "idle", "menu": "Procurar atualizações…", "menu_enabled": true,
                "auto": false, "installed": "9.9.9", "staged": false,
            },
            "reaper": {"enabled": true},
        })
    }

    #[tokio::test]
    async fn assinar_entrega_o_estado_inteiro_depois_da_resposta() {
        let mut rig = Rig::new();
        let mut ui = ui(&mut rig).await;
        send(
            &mut rig,
            &ui,
            json!({"id": 1, "cmd": "subscribe", "topic": "app"}),
        );
        assert_eq!(drain(&mut ui), [json!({"re": 1, "ok": true}), idle()]);
    }

    #[tokio::test]
    async fn os_itens_de_menu_mudam_o_estado_e_o_disco_e_republicam() {
        let mut rig = Rig::new();
        let mut ui = ui(&mut rig).await;
        send(
            &mut rig,
            &ui,
            json!({"id": 1, "cmd": "subscribe", "topic": "app"}),
        );
        drain(&mut ui);

        send(
            &mut rig,
            &ui,
            json!({"id": 2, "cmd": "reaper_enabled", "on": false}),
        );
        let got = drain(&mut ui);
        assert_eq!(reply_of(&got, 2), json!({"re": 2, "ok": true}));
        let mut expected = idle();
        expected["reaper"]["enabled"] = json!(false);
        assert_eq!(states(&got), [expected]);
        let policy: Value =
            serde_json::from_slice(&std::fs::read(rig.data.join("processes.json")).unwrap())
                .unwrap();
        assert_eq!(policy["enabled"], false);

        send(
            &mut rig,
            &ui,
            json!({"id": 3, "cmd": "update_auto", "on": true}),
        );
        let got = drain(&mut ui);
        assert_eq!(reply_of(&got, 3), json!({"re": 3, "ok": true}));
        assert_eq!(states(&got)[0]["update"]["auto"], true);
        assert_eq!(
            std::fs::read_to_string(rig.data.join("update.json")).unwrap(),
            r#"{"auto":true}"#
        );
    }

    #[tokio::test]
    async fn sem_assinante_nada_e_publicado_e_o_comando_responde_igual() {
        let mut rig = Rig::new();
        let mut ui = ui(&mut rig).await;
        send(
            &mut rig,
            &ui,
            json!({"id": 1, "cmd": "update_auto", "on": true}),
        );
        assert_eq!(drain(&mut ui), [json!({"re": 1, "ok": true})]);
    }

    #[tokio::test]
    async fn resposta_a_um_aviso_que_nao_esta_aberto_e_erro() {
        let mut rig = Rig::new();
        let mut ui = ui(&mut rig).await;
        send(
            &mut rig,
            &ui,
            json!({"id": 1, "cmd": "update_answer", "version": "1.0.0", "accept": true, "auto": false}),
        );
        assert_eq!(
            drain(&mut ui),
            [json!({"re": 1, "ok": false, "error": "o aviso da versão 1.0.0 não está aberto"})]
        );
    }

    #[tokio::test]
    async fn show_processes_do_processes_vira_efeito_no_topico_app() {
        let mut rig = Rig::new();
        let mut ui = ui(&mut rig).await;
        send(
            &mut rig,
            &ui,
            json!({"id": 1, "cmd": "subscribe", "topic": "app"}),
        );
        drain(&mut ui);
        rig.call(
            FeatureRoute::Processes,
            request("GET", "/processes?show=1", None),
        )
        .await;
        assert_eq!(
            drain(&mut ui),
            [json!({"topic": "app", "effect": "show_processes"})]
        );
    }

    /// Um servidor local que responde qualquer pedido com `body` (nunca a
    /// internet).
    fn serve(body: String) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        std::thread::spawn(move || {
            for mut stream in listener.incoming().flatten().take(8) {
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

    fn release(tag: &str) -> String {
        json!({
            "tag_name": tag, "html_url": "https://example.com/r", "body": "novidades",
            "assets": [
                {"name": "EgeonDeckNext.zip", "browser_download_url": "https://example.com/a.zip"},
                {"name": "EgeonDeckNext.zip.sig", "browser_download_url": "https://example.com/a.sig"},
            ],
        })
        .to_string()
    }

    #[tokio::test]
    async fn o_menu_consulta_e_o_aviso_chega_pronto_para_a_ui() {
        let mut rig = Rig::with_flavor(Flavor::Dev);
        rig.actor.update.feed_override = Some(format!("{}/release", serve(release("v10.0.0"))));
        let mut ui = ui(&mut rig).await;
        send(
            &mut rig,
            &ui,
            json!({"id": 1, "cmd": "subscribe", "topic": "app"}),
        );
        drain(&mut ui);

        send(&mut rig, &ui, json!({"id": 2, "cmd": "update_menu"}));
        rig.settle().await;
        let got = drain(&mut ui);
        let prompt = got
            .iter()
            .find(|l| l["effect"] == "update_prompt")
            .expect("o aviso não veio");
        assert_eq!(prompt["topic"], "app");
        assert_eq!(prompt["version"], "10.0.0");
        assert_eq!(prompt["title"], "Versão 10.0.0 do Egeon Deck disponível");
        assert_eq!(prompt["auto"], false);
        assert_eq!(prompt["accept_label"], "Atualizar e reiniciar");
        assert_eq!(prompt["later_label"], "Depois");
        let text = prompt["text"].as_str().unwrap();
        assert!(text.starts_with("novidades\n\n"), "{text}");
        assert!(!text.contains("agente"), "nenhum agente aberto: {text}");
        // O estado acompanhou: checando e depois disponível.
        let states: Vec<&str> = got
            .iter()
            .filter_map(|l| l["update"]["state"].as_str())
            .collect();
        assert_eq!(states.last(), Some(&"available"), "{states:?}");

        // Responder "depois" com a caixa marcada liga o automático — e, com
        // versão disponível, ele tenta baixar na hora: o instalador de mentira
        // do teste diz que o app não pode ser trocado, e a mensagem sai.
        send(
            &mut rig,
            &ui,
            json!({"id": 3, "cmd": "update_answer", "version": "10.0.0", "accept": false, "auto": true}),
        );
        rig.settle().await;
        let got = drain(&mut ui);
        assert_eq!(reply_of(&got, 3), json!({"re": 3, "ok": true}));
        assert!(got.iter().any(|l| l["update"]["auto"] == true));
        let message = got
            .iter()
            .find(|l| l["effect"] == "update_message")
            .expect("sem mensagem");
        assert_eq!(message["title"], "Não deu para atualizar");
        assert!(
            message["text"]
                .as_str()
                .unwrap()
                .starts_with("O app não está num lugar onde possa ser trocado (")
        );
    }

    #[tokio::test]
    async fn na_ultima_versao_o_menu_manda_uma_mensagem() {
        let mut rig = Rig::with_flavor(Flavor::Dev);
        rig.actor.update.feed_override = Some(format!("{}/release", serve(release("v9.9.9"))));
        let mut ui = ui(&mut rig).await;
        send(
            &mut rig,
            &ui,
            json!({"id": 1, "cmd": "subscribe", "topic": "app"}),
        );
        drain(&mut ui);
        send(&mut rig, &ui, json!({"id": 2, "cmd": "update_menu"}));
        rig.settle().await;
        let got = drain(&mut ui);
        assert!(
            got.contains(&json!({
                "topic": "app", "effect": "update_message",
                "title": "Você está na última versão", "text": "Egeon Deck (dev) 9.9.9.",
            })),
            "{got:?}"
        );
    }

    /// O link da resposta do chat vai ao abridor do sistema, e a resposta é
    /// só o ok: o `app` não republica por isso.
    #[tokio::test]
    async fn open_url_entrega_o_link_ao_abridor() {
        let mut rig = Rig::new();
        let mut ui = ui(&mut rig).await;
        send(
            &mut rig,
            &ui,
            json!({"id": 1, "cmd": "open_url", "url": "https://example.com/docs"}),
        );
        assert_eq!(drain(&mut ui), [json!({"re": 1, "ok": true})]);
        assert_eq!(
            *rig.opener.opened.lock().unwrap(),
            [crate::ports::opener::OpenTarget::Url(
                "https://example.com/docs".into()
            )]
        );
    }
}
