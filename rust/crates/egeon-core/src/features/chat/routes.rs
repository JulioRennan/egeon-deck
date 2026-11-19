//! As rotas do chat: `/chat`, `/compose` e `/chat/clear`. Casamento no Swift, na
//! ordem do `ControlSocket.swift`:
//!
//! - `:538` `("POST", _, _) where route.contains("/chat/clear")`
//! - `:688` `("POST", _, _) where route.contains("/compose")`
//! - `:702` `("GET", _, _) where route.contains("/chat")` — depois das duas de cima,
//!   senão `/chat/clear` cairia aqui.
//!
//! Os handlers mexem em [`ChatRoutes`] — uma [`ChatView`] por bancada, o foco e a
//! caixa de texto — e devolvem o que o core executa fora do estado
//! ([`ChatEffect`]). `chat_clear` arquiva o `chat.jsonl` no disco: o core o chama
//! de `spawn_blocking`.
//!
//! O que é da tela e não tem dono no core — popup de `@` e `/`, fila ao lado,
//! largura do painel, rolagem — o Flutter guarda; o retrato devolve esses campos
//! no formato do Swift com o valor de "nada aberto" (ver [`snapshot`]).

use std::collections::BTreeMap;
use std::time::SystemTime;

use serde_json::{Value, json};

use super::store::ChatHistory;
use super::thread::{ChatParticipant, activity_name};
use super::view::{ChatUpdate, ChatView};
use crate::features::activity::model::Activity;
use crate::protocol::handler::{RouteReply, RouteRequest};

/// Uma bancada com chat: o id (a pasta de dados), o nome (o que as rotas
/// recebem em `target`) e a visualização em que ela está.
struct Bench {
    id: String,
    name: String,
    /// `canvas` ou `chat` (o `rawValue` do `ViewMode` do Swift).
    mode: String,
    view: ChatView,
    participants: Vec<ChatParticipant>,
    /// O participante em foco; sem escolha do usuário, o primeiro agente vivo.
    focused: Option<String>,
    user_chose_focus: bool,
    composer: String,
}

pub struct ChatRoutes {
    history: ChatHistory,
    benches: BTreeMap<String, Bench>,
}

/// O que a rota pede ao core, fora do estado.
#[derive(Debug, Clone, PartialEq)]
pub enum ChatEffect {
    /// Uma linha do canal `/ui` para quem assina o chat desta bancada.
    Ui(ChatUpdate),
    /// Refazer a montagem da thread (o estado de abertura ou a janela mudou):
    /// o core chama [`ChatView::rebuild`] com o que ler e empurra o resultado.
    Rebuild { workbench: String },
    /// Entregar `text` ao agente `target` (`bancada/nó` já resolvido por quem
    /// chama) — o Enter do composer. Depois de entregar, o core chama
    /// [`ChatRoutes::sent`] para o eco entrar na thread.
    Send {
        workbench: String,
        target: String,
        text: String,
    },
}

impl ChatRoutes {
    pub fn new(history: ChatHistory) -> ChatRoutes {
        ChatRoutes {
            history,
            benches: BTreeMap::new(),
        }
    }

    /// Cadastra (ou atualiza o nome e a visualização de) uma bancada.
    pub fn register(&mut self, id: &str, name: &str, mode: &str) {
        let bench = self.benches.entry(id.to_owned()).or_insert_with(|| Bench {
            id: id.to_owned(),
            name: name.to_owned(),
            mode: mode.to_owned(),
            view: ChatView::new(id),
            participants: Vec::new(),
            focused: None,
            user_chose_focus: false,
            composer: String::new(),
        });
        bench.name = name.to_owned();
        bench.mode = mode.to_owned();
    }

    pub fn forget(&mut self, id: &str) {
        self.benches.remove(id);
    }

    /// Os participantes de agora; o foco se reajusta como no `refresh` do Swift
    /// (`ChatContainer.swift:291`): sem escolha do usuário — ou com o escolhido
    /// morto —, o primeiro AGENTE vivo na ordem dos nós, e não o primeiro que
    /// apareceu vivo.
    /// Devolve o evento `participants` do canal quando a barra mudou.
    pub fn set_participants(
        &mut self,
        id: &str,
        participants: Vec<ChatParticipant>,
    ) -> Vec<ChatEffect> {
        let Some(bench) = self.benches.get_mut(id) else {
            return Vec::new();
        };
        let alive: Vec<&ChatParticipant> = participants
            .iter()
            .filter(|p| p.activity != Activity::Dead)
            .collect();
        let keeps =
            bench.user_chose_focus && alive.iter().any(|p| Some(&p.id) == bench.focused.as_ref());
        if !keeps {
            bench.focused = alive
                .iter()
                .find(|p| p.is_agent)
                .or(alive.first())
                .map(|p| p.id.clone());
        }
        bench.participants = participants;
        let list = bench
            .participants
            .iter()
            .map(ChatParticipant::info)
            .collect();
        bench
            .view
            .set_participants(list)
            .into_iter()
            .map(ChatEffect::Ui)
            .collect()
    }

    /// As filas da bancada (op `queues`).
    pub fn set_queues(&mut self, id: &str, list: Vec<super::thread::QueueInfo>) -> Vec<ChatEffect> {
        let Some(bench) = self.benches.get_mut(id) else {
            return Vec::new();
        };
        bench
            .view
            .set_queues(list)
            .into_iter()
            .map(ChatEffect::Ui)
            .collect()
    }

    /// A bandeja de permissão da bancada (op `permissions`); vazia a esvazia.
    pub fn set_permissions(&mut self, id: &str, list: Vec<Value>) -> Vec<ChatEffect> {
        let Some(bench) = self.benches.get_mut(id) else {
            return Vec::new();
        };
        bench
            .view
            .set_permissions(list)
            .into_iter()
            .map(ChatEffect::Ui)
            .collect()
    }

    // ---- comandos do canal `/ui` (protocol/chat.rs) --------------------------

    /// `chat_snapshot{workbench}` → `{rev, blocks, participants, queues, permissions}`.
    pub fn snapshot_of(&self, id: &str) -> Option<Value> {
        self.benches.get(id).map(|b| b.view.snapshot())
    }

    /// A assinatura do tópico `chat/<id>` — e o `rev` perdido: o `reset` com tudo.
    pub fn reset_update(&self, id: &str) -> Option<ChatUpdate> {
        self.benches.get(id).map(|b| b.view.reset_update())
    }

    /// `chat_step{workbench, block}`: abre ou recolhe um passo, ou sobe o nível da
    /// capa. O core refaz a montagem em seguida (efeito `Rebuild`).
    pub fn step(&mut self, id: &str, block: &str) -> Vec<ChatEffect> {
        let Some(bench) = self.benches.get_mut(id) else {
            return Vec::new();
        };
        if !bench.view.toggle_step(block) {
            return Vec::new();
        }
        vec![ChatEffect::Rebuild {
            workbench: id.to_owned(),
        }]
    }

    /// `chat_more{workbench}`: o usuário rolou até o começo do que há.
    pub fn more(&mut self, id: &str) -> Vec<ChatEffect> {
        let Some(bench) = self.benches.get_mut(id) else {
            return Vec::new();
        };
        if !bench.view.load_more(true, false) {
            return Vec::new();
        }
        vec![ChatEffect::Rebuild {
            workbench: id.to_owned(),
        }]
    }

    /// `chat_clear{workbench}`: arquiva a conversa corrente e começa outra.
    /// Devolve para onde foi (ou `None` se já estava vazia) e os efeitos. Faz
    /// disco: chame de `spawn_blocking`. `None` em `Option` externo é bancada
    /// desconhecida.
    pub fn clear(
        &mut self,
        id: &str,
        now: SystemTime,
    ) -> Option<(Option<std::path::PathBuf>, Vec<ChatEffect>)> {
        let ChatRoutes { history, benches } = self;
        let bench = benches.get_mut(id)?;
        let archived = history.archive(&bench.id, now);
        let update = bench.view.cleared_history();
        bench.composer.clear();
        Some((archived, update.into_iter().map(ChatEffect::Ui).collect()))
    }

    /// `chat_send{workbench, to, text, quote}`: um `Send` por destinatário vivo.
    /// Quem entrega é o core; depois chama [`ChatRoutes::sent`] por destinatário.
    /// A citação (`quote`, o `messageKey` da bolha citada) é da bolha do usuário e
    /// não vai ao agente.
    pub fn send(&mut self, id: &str, to: &[String], text: &str) -> Vec<ChatEffect> {
        let Some(bench) = self.benches.get_mut(id) else {
            return Vec::new();
        };
        let message = text.trim();
        if message.is_empty() {
            return Vec::new();
        }
        bench.composer.clear();
        to.iter()
            .filter(|node| {
                bench
                    .participants
                    .iter()
                    .any(|p| &p.id == *node && p.activity != Activity::Dead)
            })
            .map(|node| ChatEffect::Send {
                workbench: id.to_owned(),
                target: node.clone(),
                text: message.to_owned(),
            })
            .collect()
    }

    /// Os ids das bancadas cadastradas.
    pub fn ids(&self) -> impl Iterator<Item = &str> {
        self.benches.keys().map(String::as_str)
    }

    /// `(id, nome)` de cada bancada cadastrada.
    pub fn bench_ids(&self) -> impl Iterator<Item = (&str, &str)> {
        self.benches
            .values()
            .map(|b| (b.id.as_str(), b.name.as_str()))
    }

    /// Os participantes da bancada, como o último `set_participants` os deixou.
    pub fn participants(&self, id: &str) -> &[ChatParticipant] {
        self.benches
            .get(id)
            .map_or(&[], |b| b.participants.as_slice())
    }

    /// O agente a que o "+ Nova fila" liga a fila: o que está em foco e, se o foco
    /// não é um agente, o primeiro (`newQueueClicked` do Swift).
    pub fn new_queue_agent(&self, id: &str) -> Option<String> {
        let agents = || self.participants(id).iter().filter(|p| p.is_agent);
        let focused = self.focused(id);
        agents()
            .find(|p| Some(&p.id) == focused.as_ref())
            .or_else(|| agents().next())
            .map(|p| p.id.clone())
    }

    /// O participante em foco.
    pub fn focused(&self, id: &str) -> Option<String> {
        self.benches.get(id).and_then(|b| b.focused.clone())
    }

    /// A conversa foi arquivada (o job de disco terminou): a thread esvazia, e o
    /// que ela guardava em memória vai junto.
    pub fn cleared(&mut self, id: &str) -> Vec<ChatEffect> {
        let Some(bench) = self.benches.get_mut(id) else {
            return Vec::new();
        };
        bench.composer.clear();
        bench
            .view
            .cleared_history()
            .into_iter()
            .map(ChatEffect::Ui)
            .collect()
    }

    pub fn view(&self, id: &str) -> Option<&ChatView> {
        self.benches.get(id).map(|b| &b.view)
    }

    pub fn view_mut(&mut self, id: &str) -> Option<&mut ChatView> {
        self.benches.get_mut(id).map(|b| &mut b.view)
    }

    pub fn history(&mut self) -> &mut ChatHistory {
        &mut self.history
    }

    /// O core entregou a mensagem: o eco entra na linha do tempo até o transcript
    /// confirmar. `known_turn_ids` são os turnos que o agente já tinha.
    pub fn sent(
        &mut self,
        id: &str,
        text: &str,
        target: &str,
        at: SystemTime,
        known_turn_ids: std::collections::BTreeSet<String>,
    ) {
        if let Some(bench) = self.benches.get_mut(id) {
            bench.view.sent(text, target, at, known_turn_ids);
        }
    }

    fn by_name(&mut self, name: &str) -> Option<&mut Bench> {
        self.benches.values_mut().find(|b| b.name == name)
    }
}

/// `/chat/clear?target=<bancada>` — arquiva a conversa corrente do chat
/// (`chat.jsonl` → `chat-archive/`) e começa outra. Nada é apagado (ADR-037).
pub fn chat_clear(
    state: &mut ChatRoutes,
    req: &RouteRequest,
    now: SystemTime,
) -> (RouteReply, Vec<ChatEffect>) {
    let name = req.param("target").unwrap_or("").to_owned();
    let ChatRoutes { history, benches } = state;
    let Some(bench) = benches.values_mut().find(|b| b.name == name) else {
        return (
            RouteReply::err(404, format!("bancada desconhecida '{name}'")),
            Vec::new(),
        );
    };
    let archived = history.archive(&bench.id, now);
    // A thread guarda eco e turno ao vivo em memória: arquivar o arquivo sem
    // avisá-la deixava mensagem órfã na tela (ADR-059).
    let update = bench.view.cleared_history();
    bench.composer.clear();
    let effects: Vec<ChatEffect> = update.into_iter().map(ChatEffect::Ui).collect();
    let reply = match archived {
        None => RouteReply::ok(json!({
            "ok": true, "workbench": name, "archived": Value::Null,
            "detail": "conversa já estava vazia"})),
        Some(path) => {
            crate::log!(
                "chat[{name}]: conversa limpa — arquivada em {}",
                path.file_name()
                    .map(|n| n.to_string_lossy())
                    .unwrap_or_default()
            );
            RouteReply::ok(json!({
                "ok": true, "workbench": name, "archived": path.to_string_lossy()}))
        }
    };
    (reply, effects)
}

/// `/compose?target=ws[&send=1]` — o corpo, em texto puro, vai para a caixa do
/// chat; `send=1` aperta o Enter. Texto puro e não JSON porque o que interessa aqui
/// é justamente prompt de VÁRIAS linhas. Sem a bancada em modo chat, 404.
pub fn chat_compose(
    state: &mut ChatRoutes,
    req: &RouteRequest,
    _now: SystemTime,
) -> (RouteReply, Vec<ChatEffect>) {
    let target = req.param("target").unwrap_or("").to_owned();
    let send = req.param("send") == Some("1");
    let text = req.text();
    let Some(bench) = state.by_name(&target).filter(|b| b.mode == "chat") else {
        return (
            RouteReply::err(404, format!("bancada sem chat montado '{target}'")),
            Vec::new(),
        );
    };
    bench.composer = text;
    let mut effects = Vec::new();
    if send {
        // O Enter só vale com destinatário vivo e texto: o composer do Swift não
        // envia caixa vazia nem para terminal morto.
        let destination = bench
            .focused
            .as_ref()
            .and_then(|id| bench.participants.iter().find(|p| &p.id == id))
            .filter(|p| p.activity != Activity::Dead)
            .map(|p| p.id.clone());
        let message = bench.composer.trim().to_owned();
        if let (Some(to), false) = (destination, message.is_empty()) {
            effects.push(ChatEffect::Send {
                workbench: bench.id.clone(),
                target: to,
                text: message,
            });
            bench.composer.clear();
        }
    }
    let reply = RouteReply::ok(snapshot(bench));
    (reply, effects)
}

/// `/chat?target=ws[&scroll=top|bottom][&focus=id][&expand=bloco]` — o modo chat
/// da bancada, como dados; `scroll` rola a thread, `focus` escolhe o participante
/// antes de responder e `expand` abre ou recolhe um passo pelo id que o retrato
/// lista em `blocks`. Os parâmetros da tela (`search`, `newqueue`, `panel`) são
/// do Flutter e o core os ignora.
pub fn chat_get(
    state: &mut ChatRoutes,
    req: &RouteRequest,
    _now: SystemTime,
) -> (RouteReply, Vec<ChatEffect>) {
    let target = req.param("target").unwrap_or("").to_owned();
    let Some(bench) = state.by_name(&target) else {
        return (
            RouteReply::err(404, format!("bancada desconhecida '{target}'")),
            Vec::new(),
        );
    };
    let mut effects = Vec::new();
    if let Some(id) = req.param("focus")
        && bench.participants.iter().any(|p| p.id == id)
    {
        bench.focused = Some(id.to_owned());
        bench.user_chose_focus = true;
    }
    if let Some(id) = req.param("expand")
        && bench.view.toggle_step(id)
    {
        effects.push(ChatEffect::Rebuild {
            workbench: bench.id.clone(),
        });
    }
    // `scroll=top` é o usuário no começo do que há: a janela cresce.
    if req.param("scroll") == Some("top") && bench.view.load_more(true, false) {
        effects.push(ChatEffect::Rebuild {
            workbench: bench.id.clone(),
        });
    }
    let reply = RouteReply::ok(snapshot(bench));
    (reply, effects)
}

/// O retrato do chat de uma bancada, com as chaves do `ChatContainer.snapshot`
/// (`ChatContainer.swift:836`) mais `workbench` e `mode` (`main.swift:440`).
fn snapshot(bench: &Bench) -> Value {
    let mut out = match bench.view.route_snapshot() {
        Value::Object(map) => map,
        _ => serde_json::Map::new(),
    };
    let participants: Vec<Value> = bench
        .participants
        .iter()
        .map(|p| {
            json!({"id": p.id, "address": p.address, "agent": p.is_agent,
                   "activity": activity_name(&p.activity), "role": p.role.clone().unwrap_or_default()})
        })
        .collect();
    out.insert(
        "focus".into(),
        json!(bench.focused.clone().unwrap_or_default()),
    );
    out.insert("viewing".into(), json!("thread"));
    out.insert("queuePanel".into(), json!(""));
    out.insert("queuePanelWidth".into(), json!(0));
    out.insert("queues".into(), json!([]));
    out.insert("participants".into(), Value::Array(participants));
    out.insert("composer".into(), json!({"text": bench.composer}));
    out.insert("popup".into(), json!({"mode": "none"}));
    out.insert("workbench".into(), json!(bench.name));
    out.insert("mode".into(), json!(bench.mode));
    Value::Object(out)
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;
    use std::time::{Duration, UNIX_EPOCH};

    use super::*;
    use crate::features::chat::model::{ChatPart, ChatRecord, ChatStep, ChatTurn};
    use crate::features::chat::time::utc;
    use crate::features::chat::view::ThreadInput;
    use crate::features::usage::PriceTable;

    fn at(secs: f64) -> SystemTime {
        UNIX_EPOCH + Duration::from_secs_f64(secs)
    }

    fn request(method: &str, target: &str, body: &str) -> RouteRequest {
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
            origin: None,
        }
    }

    fn agent(id: &str, activity: Activity) -> ChatParticipant {
        ChatParticipant {
            id: id.into(),
            address: format!("deck/{id}"),
            is_agent: true,
            role: Some("front-end".into()),
            activity,
            screen: None,
        }
    }

    fn record() -> ChatRecord {
        let mut turn = ChatTurn::new("u1", "faz", at(1_000.0), None);
        let mut run = ChatStep::new("$", "Roda");
        run.detail = Some("swift test".into());
        turn.steps = vec![run.clone()];
        turn.parts = vec![ChatPart::Step(run), ChatPart::Text("Pronto.".into())];
        turn.reply_text = "Pronto.".into();
        turn.reply_at = Some(at(1_005.0));
        ChatRecord::new("front", turn)
    }

    fn routes(dir: &std::path::Path) -> ChatRoutes {
        let mut routes = ChatRoutes::new(ChatHistory::new(dir.to_path_buf(), utc));
        routes.register("w1", "deck", "chat");
        routes.set_participants(
            "w1",
            vec![
                ChatParticipant {
                    is_agent: false,
                    ..agent("zsh", Activity::Ready)
                },
                agent("front", Activity::Waiting),
                agent("back", Activity::Dead),
            ],
        );
        routes
    }

    fn rebuild(routes: &mut ChatRoutes, records: &[ChatRecord]) {
        let participants = routes.benches["w1"].participants.clone();
        let live = BTreeMap::new();
        let prices = PriceTable::from_built_in();
        routes.view_mut("w1").expect("view").rebuild(&ThreadInput {
            participants: &participants,
            records,
            live: &live,
            prices: &prices,
        });
    }

    #[test]
    fn foco_e_o_primeiro_agente_vivo() {
        let dir = tempfile::tempdir().expect("pasta");
        let mut routes = routes(dir.path());
        let (reply, _) = chat_get(
            &mut routes,
            &request("GET", "/chat?target=deck", ""),
            at(0.0),
        );
        assert_eq!(reply.status, 200);
        assert_eq!(
            reply.json["focus"], "front",
            "o shell vem antes na lista, o agente vence"
        );
        // Escolha do usuário: `focus=` vale, e sobrevive a um novo `set_participants`.
        let (reply, _) = chat_get(
            &mut routes,
            &request("GET", "/chat?target=deck&focus=zsh", ""),
            at(0.0),
        );
        assert_eq!(reply.json["focus"], "zsh");
    }

    #[test]
    fn retrato_tem_as_chaves_do_swift() {
        let dir = tempfile::tempdir().expect("pasta");
        let mut routes = routes(dir.path());
        rebuild(&mut routes, &[record()]);
        let (reply, effects) = chat_get(
            &mut routes,
            &request("GET", "/chat?target=deck", ""),
            at(0.0),
        );
        assert!(effects.is_empty());
        let json = &reply.json;
        for key in [
            "focus",
            "viewing",
            "queuePanel",
            "queuePanelWidth",
            "queues",
            "participants",
            "composer",
            "popup",
            "pending",
            "blocks",
            "messages",
            "workbench",
            "mode",
        ] {
            assert!(json.get(key).is_some(), "falta `{key}`");
        }
        assert_eq!(json["workbench"], "deck");
        assert_eq!(json["mode"], "chat");
        assert_eq!(json["viewing"], "thread");
        assert_eq!(json["popup"], json!({"mode": "none"}));
        assert_eq!(
            json["participants"][1],
            json!({"id": "front", "address": "deck/front", "agent": true,
                   "activity": "waiting", "role": "front-end"})
        );
        assert_eq!(json["participants"][2]["activity"], "dead");
        assert_eq!(json["pending"], 0);
        let ids: Vec<&str> = json["blocks"]
            .as_array()
            .expect("blocos")
            .iter()
            .map(|b| b["id"].as_str().expect("id"))
            .collect();
        assert_eq!(ids, ["p|u1", "h|u1", "b|u1|0", "b|u1|1"]);
        assert_eq!(
            json["blocks"][2],
            json!({"id": "b|u1|0", "kind": "step", "expanded": false})
        );
    }

    #[test]
    fn bancada_desconhecida_e_404() {
        let dir = tempfile::tempdir().expect("pasta");
        let mut routes = routes(dir.path());
        let (reply, _) = chat_get(
            &mut routes,
            &request("GET", "/chat?target=nada", ""),
            at(0.0),
        );
        assert_eq!(reply.status, 404);
        assert_eq!(
            reply.json,
            json!({"ok": false, "error": "bancada desconhecida 'nada'"})
        );
        let (reply, _) = chat_clear(
            &mut routes,
            &request("POST", "/chat/clear?target=nada", ""),
            at(0.0),
        );
        assert_eq!(reply.status, 404);
        assert_eq!(reply.json["error"], "bancada desconhecida 'nada'");
    }

    #[test]
    fn expand_abre_o_passo_e_pede_a_remontagem() {
        let dir = tempfile::tempdir().expect("pasta");
        let mut routes = routes(dir.path());
        rebuild(&mut routes, &[record()]);
        let (_, effects) = chat_get(
            &mut routes,
            &request("GET", "/chat?target=deck&expand=b%7Cu1%7C0", ""),
            at(0.0),
        );
        // `RouteRequest` já chega decodificado; aqui o id vai cru no mapa.
        assert!(effects.is_empty(), "id com `%7C` não é um bloco");
        let mut req = request("GET", "/chat?target=deck", "");
        req.query.insert("expand".into(), "b|u1|0".into());
        let (_, effects) = chat_get(&mut routes, &req, at(0.0));
        assert_eq!(
            effects,
            [ChatEffect::Rebuild {
                workbench: "w1".into()
            }]
        );
        assert_eq!(
            routes.view("w1").expect("view").expanded_steps(),
            &BTreeSet::from(["b|u1|0".to_owned()])
        );
        rebuild(&mut routes, &[record()]);
        let (reply, _) = chat_get(
            &mut routes,
            &request("GET", "/chat?target=deck", ""),
            at(0.0),
        );
        assert_eq!(
            reply.json["blocks"][2],
            json!({"id": "b|u1|0", "kind": "step", "expanded": true})
        );
    }

    #[test]
    fn compose_poe_o_texto_na_caixa_e_so_envia_com_send() {
        let dir = tempfile::tempdir().expect("pasta");
        let mut routes = routes(dir.path());
        let (reply, effects) = chat_compose(
            &mut routes,
            &request("POST", "/compose?target=deck", "olha\nisso"),
            at(0.0),
        );
        assert_eq!(reply.status, 200);
        assert!(effects.is_empty());
        assert_eq!(reply.json["composer"]["text"], "olha\nisso");

        let (reply, effects) = chat_compose(
            &mut routes,
            &request("POST", "/compose?target=deck&send=1", "olha essa melhoria"),
            at(0.0),
        );
        assert_eq!(
            effects,
            [ChatEffect::Send {
                workbench: "w1".into(),
                target: "front".into(),
                text: "olha essa melhoria".into()
            }]
        );
        assert_eq!(
            reply.json["composer"]["text"], "",
            "enviou: a caixa esvazia"
        );

        // O core entregou: o eco entra na thread.
        routes.sent(
            "w1",
            "olha essa melhoria",
            "front",
            at(5.0),
            BTreeSet::new(),
        );
        rebuild(&mut routes, &[]);
        let (reply, _) = chat_get(
            &mut routes,
            &request("GET", "/chat?target=deck", ""),
            at(0.0),
        );
        assert_eq!(reply.json["pending"], 1);
    }

    #[test]
    fn compose_sem_destinatario_vivo_ou_texto_nao_envia() {
        let dir = tempfile::tempdir().expect("pasta");
        let mut routes = routes(dir.path());
        let (_, effects) = chat_compose(
            &mut routes,
            &request("POST", "/compose?target=deck&send=1", "  \n"),
            at(0.0),
        );
        assert!(effects.is_empty(), "caixa vazia não envia");
        // Foco num terminal morto: o Enter não tem para quem ir.
        let mut req = request("GET", "/chat?target=deck", "");
        req.query.insert("focus".into(), "back".into());
        chat_get(&mut routes, &req, at(0.0));
        let (reply, effects) = chat_compose(
            &mut routes,
            &request("POST", "/compose?target=deck&send=1", "oi"),
            at(0.0),
        );
        assert!(effects.is_empty());
        assert_eq!(
            reply.json["composer"]["text"], "oi",
            "o texto fica na caixa"
        );
    }

    #[test]
    fn compose_fora_do_modo_chat_e_404() {
        let dir = tempfile::tempdir().expect("pasta");
        let mut routes = routes(dir.path());
        routes.register("w1", "deck", "canvas");
        let (reply, _) = chat_compose(
            &mut routes,
            &request("POST", "/compose?target=deck", "oi"),
            at(0.0),
        );
        assert_eq!(reply.status, 404);
        assert_eq!(
            reply.json,
            json!({"ok": false, "error": "bancada sem chat montado 'deck'"})
        );
    }

    #[test]
    fn scroll_top_cresce_a_janela_uma_vez() {
        let dir = tempfile::tempdir().expect("pasta");
        let mut routes = routes(dir.path());
        let records: Vec<ChatRecord> = (0..100)
            .map(|i| {
                let mut turn =
                    ChatTurn::new(&format!("u{i}"), "p", at(1_000.0 + i as f64 * 60.0), None);
                turn.reply_text = "r".into();
                turn.reply_at = Some(at(1_005.0 + i as f64 * 60.0));
                ChatRecord::new("front", turn)
            })
            .collect();
        rebuild(&mut routes, &records);
        let (_, effects) = chat_get(
            &mut routes,
            &request("GET", "/chat?target=deck&scroll=top", ""),
            at(0.0),
        );
        assert_eq!(
            effects,
            [ChatEffect::Rebuild {
                workbench: "w1".into()
            }]
        );
        assert_eq!(routes.view("w1").expect("view").loaded_messages(), 120);
        let (_, effects) = chat_get(
            &mut routes,
            &request("GET", "/chat?target=deck&scroll=top", ""),
            at(0.0),
        );
        assert!(effects.is_empty(), "ainda carregando");
        let (_, effects) = chat_get(
            &mut routes,
            &request("GET", "/chat?target=deck&scroll=bottom", ""),
            at(0.0),
        );
        assert!(effects.is_empty(), "descer é da tela");
    }

    #[test]
    fn clear_arquiva_leva_o_eco_e_avisa_a_ui() {
        let dir = tempfile::tempdir().expect("pasta");
        let mut routes = routes(dir.path());
        routes.history().append(&record(), "w1");
        routes.sent("w1", "eco", "front", at(2.0), BTreeSet::new());
        rebuild(&mut routes, &[record()]);

        let (reply, effects) = chat_clear(
            &mut routes,
            &request("POST", "/chat/clear?target=deck", ""),
            at(9_000.0),
        );
        assert_eq!(reply.status, 200);
        assert_eq!(reply.json["ok"], true);
        assert_eq!(reply.json["workbench"], "deck");
        let archived = reply.json["archived"].as_str().expect("caminho");
        assert!(archived.contains("/w1/chat-archive/chat-"), "{archived}");
        assert!(std::path::Path::new(archived).exists());
        assert!(!dir.path().join("w1/chat.jsonl").exists());
        assert!(matches!(effects.as_slice(), [ChatEffect::Ui(update)] if update.rev == 3));
        let view = routes.view("w1").expect("view");
        assert_eq!(view.pending_count(), 0);
        assert!(view.blocks().is_empty());

        // Limpar de novo: a conversa já estava vazia.
        let (reply, effects) = chat_clear(
            &mut routes,
            &request("POST", "/chat/clear?target=deck", ""),
            at(9_100.0),
        );
        assert_eq!(
            reply.json,
            json!({"ok": true, "workbench": "deck", "archived": null, "detail": "conversa já estava vazia"})
        );
        assert!(effects.is_empty());
    }
}
