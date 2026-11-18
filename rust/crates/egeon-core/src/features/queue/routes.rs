//! As rotas da fila: `GET /tasks`, `POST /task?…` (o que o agente usa por
//! `egeon tasks` e `egeon task`) e `GET /queue?…` (a fila por fora).
//!
//! Casamento no Swift, em `ControlSocket.swift`:
//! - `:466` `case ("GET", _, _) where route.hasPrefix("/tasks")`
//! - `:476` `case ("POST", _, _) where route.hasPrefix("/task?")`
//! - `:731` `case ("GET", _, _) where route.contains("/queue")`
//!
//! `/tasks` vem antes de `/task?`, e nenhuma das duas casa com a outra:
//! `/tasks` não começa com `/task?`.

use std::time::SystemTime;

use serde_json::{Value, json};

use super::service::{QueueController, QueueHost};
use crate::protocol::handler::{RouteReply, RouteRequest};

/// As filas que mandam para um agente — é delas que ele marca, pergunta e
/// comenta tarefas (`queues(reaching:)` do `main.swift`).
pub trait TaskQueues {
    /// As filas da bancada de `address` (`bancada/nó`) cujo destino inclui o
    /// nó. Vazio se a bancada ou o nó não existem.
    fn reaching(&mut self, address: &str) -> Vec<&mut QueueController>;
}

/// Onde achar a fila de um nó pelo endereço `bancada/nó`.
pub trait QueueDirectory {
    /// Roda `run` com a fila e o mundo dela, e devolve o que `run` devolveu;
    /// `None` se não há fila nesse endereço. É por callback porque o mundo da
    /// fila (despacho, atividade) é emprestado do estado do core só durante a
    /// chamada.
    fn with_queue(
        &mut self,
        address: &str,
        run: &mut dyn FnMut(&mut QueueController, &mut dyn QueueHost) -> Value,
    ) -> Option<Value>;
}

/// O que a rota `/queue` pede à UI: o estado de tela do card, que não é da
/// fila.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum QueueEffect {
    /// `open=<item>`: abre a tarefa no card.
    OpenItem { address: String, item: String },
    /// `draft=<texto>`: o rascunho da tarefa que está sendo escrita.
    SetDraft { address: String, text: String },
}

const NOT_TERMINAL: &str = "esta conexão não veio de um terminal";

/// `GET /tasks` — as tarefas das filas ligadas a quem chama (`egeon tasks`).
pub fn tasks(state: &mut dyn TaskQueues, req: &RouteRequest, _now: SystemTime) -> RouteReply {
    let Some(origin) = &req.origin else {
        return RouteReply::err(403, NOT_TERMINAL);
    };
    let tasks: Vec<Value> = state
        .reaching(origin)
        .into_iter()
        .flat_map(|queue| queue.tasks())
        .collect();
    RouteReply::ok(json!({"ok": true, "tasks": tasks}))
}

/// `POST /task?action=done|ask|note&id=<tarefa>` — o corpo é o texto. Quem
/// mexe sai do processo, como no `/trace`: a tarefa diz quem marcou.
pub fn task(state: &mut dyn TaskQueues, req: &RouteRequest, now: SystemTime) -> RouteReply {
    let Some(origin) = &req.origin else {
        return RouteReply::err(403, NOT_TERMINAL);
    };
    let action = req.param("action").unwrap_or_default();
    let typed = req.param("id").unwrap_or_default();
    let author = origin
        .rsplit('/')
        .find(|p| !p.is_empty())
        .unwrap_or_default();
    let mut reaching = state.reaching(origin);
    if reaching.is_empty() {
        return RouteReply::err(400, "nenhuma fila está ligada a você");
    }
    // A mesma tarefa não existe em duas filas: o id é um UUID.
    let Some(queue) = reaching
        .iter_mut()
        .find(|q| q.queue().index_matching(typed).is_some())
    else {
        return RouteReply::err(
            400,
            format!("tarefa {typed} não existe nas filas ligadas a você (veja `egeon tasks`)"),
        );
    };
    match queue.agent(author, action, typed, &req.text(), now) {
        Ok(()) => RouteReply::ok(json!({"ok": true})),
        Err(error) => RouteReply::err(400, error.to_string()),
    }
}

/// `GET /queue?target=ws/id[&add=texto[&image=caminho]][&send=next|<item>]
/// [&done=<item>][&open=<item>][&draft=texto][&remove=<item>]
/// [&reply=<item>&text=][&auto=0|1][&to=<nó>][&clear=done]` — a fila de
/// prompts por fora, e como ela ficou. A resposta não leva `ok`: é o que a
/// rota fez (`added`, `error`) junto do retrato da fila.
pub fn queue(
    state: &mut dyn QueueDirectory,
    req: &RouteRequest,
    now: SystemTime,
) -> (RouteReply, Vec<QueueEffect>) {
    let target = req.param("target").unwrap_or_default();
    let found = state.with_queue(target, &mut |controller, host| {
        controller.control(&req.query, host, now)
    });
    let Some(payload) = found else {
        return (
            RouteReply::err(404, format!("fila desconhecida '{target}'")),
            Vec::new(),
        );
    };
    let mut effects = Vec::new();
    if let Some(item) = req.param("open") {
        effects.push(QueueEffect::OpenItem {
            address: target.to_owned(),
            item: item.to_owned(),
        });
    }
    if let Some(text) = req.param("draft") {
        effects.push(QueueEffect::SetDraft {
            address: target.to_owned(),
            text: text.to_owned(),
        });
    }
    (RouteReply::ok(payload), effects)
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, UNIX_EPOCH};

    use super::*;
    use crate::features::activity::model::Activity;
    use crate::features::queue::service::Linked;
    use crate::features::queue::store::QueueStore;

    fn now() -> SystemTime {
        UNIX_EPOCH + Duration::from_secs(1_787_678_363)
    }

    fn request(method: &str, target: &str, origin: Option<&str>, body: &str) -> RouteRequest {
        let (path, query) = target.split_once('?').unwrap_or((target, ""));
        RouteRequest {
            method: method.into(),
            target: target.into(),
            path: path.into(),
            query: query
                .split('&')
                .filter_map(|p| p.split_once('='))
                .map(|(k, v)| (k.to_owned(), v.to_owned()))
                .collect(),
            body: body.as_bytes().to_vec(),
            origin: origin.map(str::to_owned),
        }
    }

    struct World {
        sent: Vec<(String, String)>,
    }

    impl QueueHost for World {
        fn linked(&self) -> Vec<Linked> {
            vec![Linked::agent("dev")]
        }
        fn activity(&self, _: &str) -> Option<Activity> {
            Some(Activity::Ready)
        }
        fn dispatch(&mut self, node: &str, text: &str, _: &[String]) -> Result<(), String> {
            self.sent.push((node.to_owned(), text.to_owned()));
            Ok(())
        }
    }

    /// Uma bancada "deck" com uma fila "fila" ligada ao agente "dev".
    struct Deck {
        _dir: tempfile::TempDir,
        queue: QueueController,
        world: World,
    }

    impl Deck {
        fn new() -> Self {
            let dir = tempfile::tempdir().unwrap();
            let queue = QueueController::new(QueueStore::new(dir.path().join("fila")), "fila");
            Deck {
                _dir: dir,
                queue,
                world: World { sent: Vec::new() },
            }
        }
    }

    impl TaskQueues for Deck {
        fn reaching(&mut self, address: &str) -> Vec<&mut QueueController> {
            if address == "deck/dev" {
                vec![&mut self.queue]
            } else {
                Vec::new()
            }
        }
    }

    impl QueueDirectory for Deck {
        fn with_queue(
            &mut self,
            address: &str,
            run: &mut dyn FnMut(&mut QueueController, &mut dyn QueueHost) -> Value,
        ) -> Option<Value> {
            (address == "deck/fila").then(|| run(&mut self.queue, &mut self.world))
        }
    }

    fn id_of(deck: &Deck) -> String {
        deck.queue.queue().items[0].short_id()
    }

    #[test]
    fn tasks_so_para_terminal_e_lista_as_filas_ligadas() {
        let mut deck = Deck::new();
        deck.queue.add("conserta o toast", vec![], None);
        let denied = tasks(&mut deck, &request("GET", "/tasks", None, ""), now());
        assert_eq!(denied.status, 403);
        assert_eq!(
            denied.json,
            json!({"ok": false, "error": "esta conexão não veio de um terminal"})
        );

        let id = id_of(&deck);
        let reply = tasks(
            &mut deck,
            &request("GET", "/tasks", Some("deck/dev"), ""),
            now(),
        );
        assert_eq!(reply.status, 200);
        assert_eq!(
            reply.json,
            json!({"ok": true, "tasks": [
                {"id": id, "text": "conserta o toast", "status": "pending", "fila": "fila"}
            ]})
        );
        // Quem nenhuma fila alcança vê a lista vazia, não um erro.
        let none = tasks(
            &mut deck,
            &request("GET", "/tasks", Some("deck/outro"), ""),
            now(),
        );
        assert_eq!(none.json, json!({"ok": true, "tasks": []}));
    }

    #[test]
    fn task_done_ask_e_note_pelo_id_curto() {
        let mut deck = Deck::new();
        deck.queue.add("toast", vec![], None);
        let id = id_of(&deck);
        let call = |deck: &mut Deck, action: &str, body: &str| {
            let target = format!("/task?action={action}&id={id}");
            task(
                deck,
                &request("POST", &target, Some("deck/dev"), body),
                now(),
            )
        };
        assert_eq!(call(&mut deck, "note", "achei").json, json!({"ok": true}));
        assert_eq!(call(&mut deck, "ask", "qual?").json, json!({"ok": true}));
        assert!(deck.queue.queue().items[0].awaiting);
        let done = call(&mut deck, "done", "");
        assert_eq!((done.status, done.json), (200, json!({"ok": true})));
        let item = &deck.queue.queue().items[0];
        assert_eq!(item.thread.len(), 3);
        // Quem marcou é o nó que chamou, nunca o texto.
        assert!(
            item.thread
                .iter()
                .all(|m| m.author.as_deref() == Some("dev"))
        );
    }

    #[test]
    fn task_recusa_com_as_mensagens_do_swift() {
        let mut deck = Deck::new();
        deck.queue.add("toast", vec![], None);
        let id = id_of(&deck);
        let call = |deck: &mut Deck, origin: Option<&str>, target: &str| {
            let reply = task(deck, &request("POST", target, origin, "x"), now());
            (
                reply.status,
                reply.json["error"].as_str().map(str::to_owned),
            )
        };
        assert_eq!(
            call(&mut deck, None, "/task?action=done&id=x"),
            (403, Some("esta conexão não veio de um terminal".into()))
        );
        assert_eq!(
            call(
                &mut deck,
                Some("deck/outro"),
                &format!("/task?action=done&id={id}")
            ),
            (400, Some("nenhuma fila está ligada a você".into()))
        );
        assert_eq!(
            call(&mut deck, Some("deck/dev"), "/task?action=done&id=zzzz"),
            (
                400,
                Some("tarefa zzzz não existe nas filas ligadas a você (veja `egeon tasks`)".into())
            )
        );
        // Sem `id` na query o id é vazio, e vazio nunca casa.
        assert_eq!(
            call(&mut deck, Some("deck/dev"), "/task?action=done").0,
            400
        );
        assert_eq!(
            call(
                &mut deck,
                Some("deck/dev"),
                &format!("/task?action=grita&id={id}")
            ),
            (
                400,
                Some("ação desconhecida grita — use done, ask ou note".into())
            )
        );
        assert_eq!(
            call(
                &mut deck,
                Some("deck/dev"),
                &format!("/task?action=ask&id={id}")
            )
            .0,
            200,
            "o corpo \"x\" vira a pergunta"
        );
    }

    #[test]
    fn queue_desconhecida_e_404_com_o_alvo() {
        let mut deck = Deck::new();
        let (reply, effects) = queue(
            &mut deck,
            &request("GET", "/queue?target=deck/nada", None, ""),
            now(),
        );
        assert_eq!(reply.status, 404);
        assert_eq!(
            reply.json,
            json!({"ok": false, "error": "fila desconhecida 'deck/nada'"})
        );
        assert!(effects.is_empty());
        let (missing, _) = queue(&mut deck, &request("GET", "/queue", None, ""), now());
        assert_eq!(missing.json["error"], "fila desconhecida ''");
    }

    #[test]
    fn queue_aplica_os_parametros_e_devolve_o_retrato_sem_ok() {
        let mut deck = Deck::new();
        let (reply, effects) = queue(
            &mut deck,
            &request("GET", "/queue?target=deck/fila&add=primeira", None, ""),
            now(),
        );
        assert_eq!(reply.status, 200);
        assert!(reply.json.get("ok").is_none());
        assert!(reply.json["added"].is_string());
        assert_eq!(reply.json["items"][0]["status"], "pending");
        assert_eq!(reply.json["destination"], "dev");
        assert!(effects.is_empty());

        let (sent, _) = queue(
            &mut deck,
            &request("GET", "/queue?target=deck/fila&send=next", None, ""),
            now(),
        );
        assert_eq!(sent.json["error"], "");
        assert_eq!(sent.json["items"][0]["status"], "sent");
        assert_eq!(deck.world.sent.len(), 1);
        assert_eq!(deck.world.sent[0].0, "dev");
    }

    #[test]
    fn open_e_draft_vao_para_a_ui_so_se_a_fila_existe() {
        let mut deck = Deck::new();
        let (_, effects) = queue(
            &mut deck,
            &request(
                "GET",
                "/queue?target=deck/fila&open=abc123&draft=oi",
                None,
                "",
            ),
            now(),
        );
        assert_eq!(
            effects,
            [
                QueueEffect::OpenItem {
                    address: "deck/fila".into(),
                    item: "abc123".into()
                },
                QueueEffect::SetDraft {
                    address: "deck/fila".into(),
                    text: "oi".into()
                },
            ]
        );
        let (_, none) = queue(
            &mut deck,
            &request("GET", "/queue?target=deck/nada&open=abc123", None, ""),
            now(),
        );
        assert!(none.is_empty());
    }
}
