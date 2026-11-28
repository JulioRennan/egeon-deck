//! Porte de `PromptQueueTests.swift` (menos a largura do painel, que é
//! geometria da UI), mais o disco: arquivo antigo e arquivo do Swift abrem.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use super::model::{MessageKind, Status};
use super::runner::LOST_AFTER;
use super::*;
use crate::features::activity::model::Activity;

fn t0() -> SystemTime {
    UNIX_EPOCH + Duration::from_secs(1_787_678_363)
}

fn item(id: &str, text: &str) -> QueueItem {
    QueueItem::with_id(id, text, Vec::new(), Status::Pending)
}

fn queue_of(ids: &[&str]) -> PromptQueue {
    PromptQueue {
        items: ids.iter().map(|id| item(id, id)).collect(),
        ..PromptQueue::default()
    }
}

fn ids(queue: &PromptQueue) -> Vec<&str> {
    queue.items.iter().map(|i| i.id.as_str()).collect()
}

fn statuses(queue: &PromptQueue) -> Vec<Status> {
    queue.items.iter().map(|i| i.status).collect()
}

#[test]
fn destino_cai_no_primeiro_ligado() {
    let mut queue = PromptQueue::default();
    let linked = |names: &[&str]| names.iter().map(|n| n.to_string()).collect::<Vec<_>>();
    assert_eq!(queue.destination(&linked(&[])), None);
    assert_eq!(queue.destination(&linked(&["dev", "front"])), Some("dev"));
    queue.target = Some("front".into());
    assert_eq!(queue.destination(&linked(&["dev", "front"])), Some("front"));
    // Aresta apagada: o escolhido some, vale o primeiro que sobrou.
    assert_eq!(queue.destination(&linked(&["dev"])), Some("dev"));
}

#[test]
fn mover_fica_dentro_da_lista() {
    let mut queue = queue_of(&["a", "b", "c"]);
    queue.move_by("a", -1);
    assert_eq!(ids(&queue), ["a", "b", "c"]);
    queue.move_by("a", 1);
    assert_eq!(ids(&queue), ["b", "a", "c"]);
    queue.move_by("c", -5);
    assert_eq!(ids(&queue), ["c", "b", "a"]);
}

#[test]
fn arrasto_conta_so_as_linhas_que_ficaram() {
    let mut queue = queue_of(&["a", "b", "c", "d"]);
    // "a" solto depois de "c": entre as que ficaram (b, c, d), posição 2.
    queue.move_to("a", 2);
    assert_eq!(ids(&queue), ["b", "c", "a", "d"]);
    queue.move_to("d", 0);
    assert_eq!(ids(&queue), ["d", "b", "c", "a"]);
    queue.move_to("b", 99);
    assert_eq!(ids(&queue), ["d", "c", "a", "b"]);
}

fn step(queue: &PromptQueue, activity: Option<Activity>, saw_work: bool, now: SystemTime) -> Step {
    QueueRunner::step(queue, activity.as_ref(), saw_work, now)
}

fn finish_send(finish: Option<&str>, send: Option<&str>) -> Step {
    Step {
        finish: finish.map(str::to_owned),
        send: send.map(str::to_owned),
    }
}

#[test]
fn o_runner_espera_o_trabalho_fecha_e_so_no_automatico_manda_o_proximo() {
    let mut queue = PromptQueue {
        items: vec![
            QueueItem::with_id("1", "um", Vec::new(), Status::Sent),
            item("2", "dois"),
        ],
        ..PromptQueue::default()
    };
    queue.items[0].sent_at = Some(t0());
    let now = t0();
    // Parado logo depois do envio, sem ter trabalhado: ainda não é o fim.
    assert_eq!(
        step(&queue, Some(Activity::Waiting), false, now),
        Step::default()
    );
    assert_eq!(
        step(&queue, Some(Activity::Working), true, now),
        Step::default()
    );
    // Pergunta não é fim de turno: mandar por cima atropelaria a resposta.
    assert_eq!(
        step(&queue, Some(Activity::Asking), true, now),
        Step::default()
    );
    assert_eq!(
        step(&queue, Some(Activity::Waiting), true, now),
        finish_send(Some("1"), None)
    );
    queue.auto = true;
    assert_eq!(
        step(&queue, Some(Activity::Waiting), true, now),
        finish_send(Some("1"), Some("2"))
    );
    assert_eq!(
        step(&queue, Some(Activity::Dead), true, now),
        Step::default()
    );
    assert_eq!(step(&queue, None, true, now), Step::default());
}

#[test]
fn o_runner_desiste_de_entrega_perdida() {
    let mut queue = PromptQueue {
        items: vec![QueueItem::with_id("1", "um", Vec::new(), Status::Sent)],
        ..PromptQueue::default()
    };
    queue.items[0].sent_at = Some(t0());
    let later = t0() + LOST_AFTER + Duration::from_secs(1);
    assert_eq!(
        step(&queue, Some(Activity::Ready), false, later),
        finish_send(Some("1"), None)
    );
}

#[test]
fn o_runner_comeca_o_automatico_quando_ocioso_e_nada_em_andamento() {
    let queue = PromptQueue {
        items: vec![item("1", "um")],
        auto: true,
        ..PromptQueue::default()
    };
    assert_eq!(
        step(&queue, Some(Activity::Ready), false, t0()),
        finish_send(None, Some("1"))
    );
}

// ---- Controller

struct Sent {
    node: String,
    text: String,
    images: Vec<String>,
}

struct World {
    linked: Vec<Linked>,
    activity: Option<Activity>,
    sent: Vec<Sent>,
    failure: Option<String>,
}

impl World {
    fn new() -> Self {
        World {
            linked: vec![Linked::agent("dev")],
            activity: Some(Activity::Ready),
            sent: Vec::new(),
            failure: None,
        }
    }

    /// O pedido sem o rodapé de comandos da tarefa.
    fn bodies(&self) -> Vec<String> {
        self.sent
            .iter()
            .map(|s| {
                s.text
                    .split("\n\n[ED]")
                    .next()
                    .unwrap_or(&s.text)
                    .to_owned()
            })
            .collect()
    }
}

impl QueueHost for World {
    fn linked(&self) -> Vec<Linked> {
        self.linked.clone()
    }

    fn activity(&self, _node: &str) -> Option<Activity> {
        self.activity.clone()
    }

    fn dispatch(&mut self, node: &str, text: &str, images: &[String]) -> Result<(), String> {
        if let Some(failure) = &self.failure {
            return Err(failure.clone());
        }
        self.sent.push(Sent {
            node: node.to_owned(),
            text: text.to_owned(),
            images: images.to_vec(),
        });
        Ok(())
    }
}

struct Bench {
    _dir: tempfile::TempDir,
    folder: std::path::PathBuf,
    controller: QueueController,
}

fn bench() -> Bench {
    let dir = tempfile::tempdir().unwrap();
    let folder = dir.path().join("fila");
    let controller = QueueController::new(QueueStore::new(folder.clone()), "fila");
    Bench {
        _dir: dir,
        folder,
        controller,
    }
}

#[test]
fn o_automatico_anda_a_fila_um_turno_por_vez() {
    let mut world = World::new();
    let mut b = bench();
    let q = &mut b.controller;
    q.add("primeiro", vec![], None);
    q.add("segundo\n\ncom detalhe", vec![], None);
    // A tarefa em branco é a que você está escrevendo: não é a próxima.
    let blank = q.add("  ", vec![], None);

    q.set_auto(true, &mut world, t0());
    assert_eq!(world.bodies(), ["primeiro"]);
    assert_eq!(
        statuses(q.queue()),
        [Status::Sent, Status::Pending, Status::Pending]
    );

    // O agente pega o primeiro, trabalha, e só ao parar vai o segundo.
    world.activity = Some(Activity::Working);
    q.tick(&mut world, t0());
    assert_eq!(world.sent.len(), 1);
    world.activity = Some(Activity::Waiting);
    q.tick(&mut world, t0());
    assert_eq!(world.bodies(), ["primeiro", "segundo\n\ncom detalhe"]);
    assert_eq!(
        statuses(q.queue()),
        [Status::Done, Status::Sent, Status::Pending]
    );
    q.drop_if_empty(&blank.id);

    // A fila sobrevive ao app: o disco tem o mesmo que a memória.
    let reloaded = QueueStore::new(b.folder.clone()).load();
    assert_eq!(
        reloaded.items.iter().map(|i| &i.id).collect::<Vec<_>>(),
        b.controller
            .queue()
            .items
            .iter()
            .map(|i| &i.id)
            .collect::<Vec<_>>()
    );
    assert_eq!(statuses(&reloaded), [Status::Done, Status::Sent]);
    assert_eq!(
        reloaded
            .items
            .iter()
            .map(|i| i.sent_to.as_deref())
            .collect::<Vec<_>>(),
        [Some("dev"), Some("dev")]
    );
    assert!(reloaded.auto);
}

#[test]
fn envio_manual_sem_ligacao_ou_com_falha_mantem_o_item_pendente() {
    let mut world = World::new();
    world.linked.clear();
    let mut b = bench();
    let q = &mut b.controller;
    let it = q.add("pedido", vec![], None);
    assert_eq!(
        q.send(&it.id, &mut world, t0()),
        Err(QueueError::NoDestination)
    );
    assert_eq!(q.queue().items[0].status, Status::Pending);

    world.linked = vec![Linked::agent("dev")];
    world.failure = Some("terminal desconhecido".into());
    let error = q.send(&it.id, &mut world, t0()).unwrap_err();
    assert_eq!(error.to_string(), "terminal desconhecido");
    assert_eq!(q.queue().items[0].status, Status::Pending);

    world.failure = None;
    assert_eq!(q.send(&it.id, &mut world, t0()), Ok(()));
    assert_eq!(q.queue().items[0].sent_to.as_deref(), Some("dev"));
}

#[test]
fn mandar_por_cima_de_um_item_em_andamento_o_encerra() {
    let mut world = World::new();
    let mut b = bench();
    let q = &mut b.controller;
    let first = q.add("um", vec![], None);
    let second = q.add("dois", vec![], None);
    q.send(&first.id, &mut world, t0()).unwrap();
    q.send(&second.id, &mut world, t0()).unwrap();
    assert_eq!(statuses(q.queue()), [Status::Done, Status::Sent]);
}

#[test]
fn imagens_vao_como_caminho_absoluto_e_saem_com_o_item() {
    let mut world = World::new();
    let mut b = bench();
    let name = b
        .controller
        .store()
        .save_image(&[0x89, 0x50, 0x4E, 0x47])
        .unwrap();
    let q = &mut b.controller;
    let it = q.add("", vec![name.clone()], None);
    q.send(&it.id, &mut world, t0()).unwrap();
    let path = q.store().url_of(&name);
    assert_eq!(world.sent[0].images, [path.to_string_lossy()]);
    assert!(path.exists());

    // Com o agente, a tarefa não sai da lista; feita, sai com o print.
    q.remove(&it.id);
    assert_eq!(q.queue().items.len(), 1);
    q.agent("dev", "done", &it.short_id(), "", t0()).unwrap();
    q.remove(&it.id);
    assert!(!path.exists());
}

#[test]
fn mudar_os_ligados_avisa_a_view() {
    let mut world = World::new();
    let mut b = bench();
    let q = &mut b.controller;
    q.tick(&mut world, t0());
    assert!(!q.take_changed());
    world.linked.push(Linked::agent("front"));
    q.tick(&mut world, t0());
    assert!(q.take_changed());
    assert!(!q.take_changed());
}

#[test]
fn enter_depois_de_uma_tarefa_aberta_insere_abaixo_e_as_em_branco_somem() {
    let mut b = bench();
    let q = &mut b.controller;
    let a = q.add("a", vec![], None);
    q.add("c", vec![], None);
    let blank = q.add("", vec![], Some(&a.id));
    let texts = |q: &QueueController| {
        q.queue()
            .items
            .iter()
            .map(|i| i.text.clone())
            .collect::<Vec<_>>()
    };
    assert_eq!(texts(q), ["a", "", "c"]);
    assert_eq!(q.queue().pending_count(), 2);
    q.drop_if_empty(&a.id);
    assert_eq!(q.queue().items.len(), 3);
    q.drop_if_empty(&blank.id);
    assert_eq!(texts(q), ["a", "c"]);
}

#[test]
fn checkbox_marca_feito_a_mao_e_volta() {
    let mut world = World::new();
    let mut b = bench();
    let q = &mut b.controller;
    let it = q.add("resolvi sozinho", vec![], None);
    q.toggle_done(&it.id, t0());
    assert_eq!(q.queue().items[0].status, Status::Done);
    assert!(world.sent.is_empty());
    q.toggle_done(&it.id, t0());
    assert_eq!(q.queue().items[0].status, Status::Pending);
    let _ = &mut world;
}

#[test]
fn anexar_e_desanexar_imagens() {
    let mut b = bench();
    let name = b.controller.store().save_image(&[1, 2, 3]).unwrap();
    let q = &mut b.controller;
    let it = q.add("com print", vec![], None);
    q.attach(vec![name.clone()], &it.id);
    assert_eq!(q.queue().items[0].images, std::slice::from_ref(&name));
    q.detach(&name, &it.id);
    assert!(q.queue().items[0].images.is_empty());
    assert!(!q.store().url_of(&name).exists());
}

// ---- Thread

#[test]
fn rodape_so_vai_para_agente_e_leva_o_id_curto() {
    let mut world = World::new();
    let mut b = bench();
    let q = &mut b.controller;
    let it = q.add("conserta o toast", vec![], None);
    q.send(&it.id, &mut world, t0()).unwrap();
    let footer = q.footer(&it);
    assert!(world.sent[0].text.ends_with(&footer));
    assert!(
        world.sent[0]
            .text
            .contains(&format!("egeon task done {}", it.short_id()))
    );

    world.linked = vec![Linked {
        id: "sh".into(),
        label: "sh".into(),
        agent: false,
    }];
    let other = q.add("ls", vec![], None);
    q.send(&other.id, &mut world, t0()).unwrap();
    assert_eq!(world.sent[1].text, "ls");
}

#[test]
fn o_agente_marca_pergunta_e_comenta_pelo_id_curto() {
    let mut b = bench();
    let q = &mut b.controller;
    let it = q.add("toast atrás do header", vec![], None);
    assert!(q.agent("dev", "done", "zzzz", "", t0()).is_err());
    assert!(q.agent("dev", "ask", &it.short_id(), "  ", t0()).is_err());

    q.agent(
        "dev",
        "note",
        &it.short_id().to_uppercase(),
        "achei no header.css",
        t0(),
    )
    .unwrap();
    q.agent(
        "dev",
        "ask",
        &it.short_id(),
        "o header é fixo em todas?",
        t0(),
    )
    .unwrap();
    assert!(q.queue().items[0].awaiting);
    q.agent("dev", "done", &it.id, "", t0()).unwrap();
    let done = &q.queue().items[0];
    assert_eq!(done.status, Status::Done);
    assert!(!done.awaiting);
    assert_eq!(
        done.thread.iter().map(|m| m.kind).collect::<Vec<_>>(),
        [MessageKind::Note, MessageKind::Question, MessageKind::Done]
    );
    assert!(
        done.thread
            .iter()
            .all(|m| m.author.as_deref() == Some("dev"))
    );
    assert_eq!(q.tasks()[0]["id"], it.short_id());
}

#[test]
fn mensagens_de_erro_do_agente_sao_as_do_swift() {
    let mut b = bench();
    let q = &mut b.controller;
    let it = q.add("x", vec![], None);
    let said = |r: Result<(), QueueError>| r.unwrap_err().to_string();
    assert_eq!(
        said(q.agent("dev", "done", "zzzz", "", t0())),
        "tarefa zzzz não existe na fila fila (veja `egeon tasks`)"
    );
    assert_eq!(
        said(q.agent("dev", "ask", &it.short_id(), "", t0())),
        "pergunta vazia — o que você quer saber?"
    );
    assert_eq!(
        said(q.agent("dev", "note", &it.short_id(), " ", t0())),
        "comentário vazio"
    );
    assert_eq!(
        said(q.agent("dev", "grita", &it.short_id(), "x", t0())),
        "ação desconhecida grita — use done, ask ou note"
    );
    // Id curto demais não acha nada, e o ambíguo também não.
    assert_eq!(q.queue().index_matching("abc"), None);
}

#[test]
fn pergunta_aberta_segura_a_fila_ate_voce_responder() {
    let mut world = World::new();
    let mut b = bench();
    let q = &mut b.controller;
    let first = q.add("primeira", vec![], None);
    q.add("segunda", vec![], None);
    q.set_auto(true, &mut world, t0());
    world.activity = Some(Activity::Working);
    q.tick(&mut world, t0());
    q.agent("dev", "ask", &first.short_id(), "qual navegador?", t0())
        .unwrap();
    // O agente parou para perguntar: não é fim de tarefa, a fila espera.
    world.activity = Some(Activity::Waiting);
    q.tick(&mut world, t0());
    q.tick(&mut world, t0());
    assert_eq!(world.sent.len(), 1);
    assert_eq!(statuses(q.queue()), [Status::Sent, Status::Pending]);

    q.reply(&first.id, "Safari", &mut world, t0()).unwrap();
    assert_eq!(world.sent.len(), 2);
    assert_eq!(world.sent[1].node, "dev");
    assert!(world.sent[1].text.contains("primeira"));
    assert!(world.sent[1].text.ends_with("Safari"));
    assert!(!q.queue().items[0].awaiting);

    // A resposta é trabalho novo: só depois dele a fila anda.
    world.activity = Some(Activity::Working);
    q.tick(&mut world, t0());
    world.activity = Some(Activity::Waiting);
    q.tick(&mut world, t0());
    assert_eq!(statuses(q.queue()), [Status::Done, Status::Sent]);
}

#[test]
fn comentario_antes_de_enviar_vai_com_a_tarefa() {
    let mut world = World::new();
    let mut b = bench();
    let q = &mut b.controller;
    let it = q.add("logo pixelado", vec![], None);
    q.reply(&it.id, "só no retina", &mut world, t0()).unwrap();
    assert!(world.sent.is_empty());
    q.send(&it.id, &mut world, t0()).unwrap();
    assert_eq!(world.bodies(), ["logo pixelado\n\nsó no retina"]);
}

#[test]
fn arquivo_antigo_sem_thread_ainda_abre() {
    let json = r#"{"items":[{"id":"abc123","title":"t","notes":"corpo","images":[],"status":"pending"},{"id":"d","title":"só título","notes":"","images":[],"status":"done"}],"auto":false}"#;
    let queue: PromptQueue = serde_json::from_str(json).unwrap();
    // Título e notas da v1.7 viram um texto só, e o prompt não muda.
    assert_eq!(
        queue
            .items
            .iter()
            .map(|i| i.text.as_str())
            .collect::<Vec<_>>(),
        ["t\n\ncorpo", "só título"]
    );
    let saved = serde_json::to_string(&queue).unwrap();
    assert!(!saved.contains("\"title\""));
    assert!(queue.items[0].thread.is_empty());
    assert!(!queue.items[0].awaiting);
}

#[test]
fn a_manchete_e_a_primeira_linha_encurtada() {
    assert_eq!(
        item("x", "\n  primeira linha\nsegunda").headline(),
        "primeira linha"
    );
    let long = item("x", &"x".repeat(80)).headline();
    assert_eq!(long.chars().count(), 61);
    assert!(long.ends_with('…'));
}

#[test]
fn a_resposta_diz_de_que_tarefa_fala_pela_primeira_linha() {
    let mut world = World::new();
    let mut b = bench();
    let q = &mut b.controller;
    let it = q.add(
        "Toast atrás do header\nSó no Safari, nas páginas logadas.",
        vec![],
        None,
    );
    q.send(&it.id, &mut world, t0()).unwrap();
    q.reply(&it.id, "é o z-index", &mut world, t0()).unwrap();
    assert!(world.sent[1].text.contains("“Toast atrás do header”"));
    assert!(!world.sent[1].text.contains("Só no Safari"));
}

// ---- Coluna do chat

#[test]
fn o_resumo_do_chat_diz_o_que_a_fila_precisa() {
    let summary = |q: &PromptQueue| ChatQueue::new("fila", q).summary();
    let mut queue = PromptQueue::default();
    assert_eq!(summary(&queue), "nada pendente");
    queue.items = vec![item("a", "a")];
    assert_eq!(summary(&queue), "1 pendente");
    queue.items.push(item("b", "b"));
    // A tarefa em branco é a que você está escrevendo: não conta.
    queue.items.push(item("c", "  "));
    assert_eq!(summary(&queue), "2 pendentes");
    queue.items[0].status = Status::Sent;
    queue.items[0].sent_to = Some("dev".into());
    assert_eq!(summary(&queue), "1 pendente · com dev");
    queue.items[1].status = Status::Done;
    assert_eq!(summary(&queue), "com dev");
    queue.items[0].awaiting = true;
    let asking = ChatQueue::new("fila", &queue);
    assert!(asking.asking);
    assert_eq!(asking.summary(), "? pergunta");
}

#[test]
fn tarefa_enviada_so_anda_pela_thread() {
    let mut world = World::new();
    let mut b = bench();
    let kept = b.controller.store().save_image(&[1]).unwrap();
    let late = b.controller.store().save_image(&[2]).unwrap();
    let q = &mut b.controller;
    let it = q.add("original", vec![], None);
    q.attach(vec![kept.clone()], &it.id);
    assert!(!q.queue().items[0].is_locked());
    q.update(&it.id, "antes de enviar");
    q.send(&it.id, &mut world, t0()).unwrap();
    assert!(q.queue().items[0].is_locked());

    q.update(&it.id, "mudou depois");
    assert_eq!(q.queue().items[0].text, "antes de enviar");
    q.attach(vec![late.clone()], &it.id);
    assert_eq!(q.queue().items[0].images, std::slice::from_ref(&kept));
    assert!(!q.store().url_of(&late).exists(), "print sem dono não fica");
    q.detach(&kept, &it.id);
    assert_eq!(q.queue().items[0].images, std::slice::from_ref(&kept));
    assert_eq!(
        q.send(&it.id, &mut world, t0()),
        Err(QueueError::AlreadySent)
    );
    assert_eq!(world.sent.len(), 1);

    // Feita: não volta a pendente nem se reenvia. A resposta na thread é que reabre.
    q.agent("dev", "done", &it.short_id(), "", t0()).unwrap();
    q.reopen(&it.id);
    q.toggle_done(&it.id, t0());
    assert_eq!(q.queue().items[0].status, Status::Done);
    q.reply(&it.id, "faltou o Safari", &mut world, t0())
        .unwrap();
    assert_eq!(q.queue().items[0].status, Status::Sent);
    assert_eq!(q.queue().items[0].text, "antes de enviar");
    assert_eq!(world.sent.len(), 2);
}

#[test]
fn tarefa_feita_a_mao_ainda_pode_ser_editada() {
    let mut b = bench();
    let q = &mut b.controller;
    let it = q.add("resolvi sozinho", vec![], None);
    q.toggle_done(&it.id, t0());
    q.update(&it.id, "resolvi sozinho, com nota");
    assert_eq!(q.queue().items[0].text, "resolvi sozinho, com nota");
    q.toggle_done(&it.id, t0());
    assert_eq!(q.queue().items[0].status, Status::Pending);
}

// ---- O que o Swift não testava: o contrato com o disco e com a rota

#[test]
fn a_fila_gravada_pelo_swift_abre_e_o_que_se_grava_tem_a_mesma_forma() {
    // `JSONEncoder` com `.prettyPrinted`, `.sortedKeys` e `.iso8601`.
    let swift = r#"{
  "auto" : true,
  "items" : [
    {
      "awaiting" : true,
      "id" : "3F9A2C1D-0000-4000-8000-000000000001",
      "images" : [
        "img-ab12cd34.png"
      ],
      "sentAt" : "2026-08-25T17:19:23Z",
      "sentTo" : "dev",
      "status" : "sent",
      "text" : "conserta o toast",
      "thread" : [
        {
          "at" : "2026-08-25T17:20:00Z",
          "author" : "dev",
          "kind" : "question",
          "text" : "qual?"
        },
        {
          "at" : "2026-08-25T17:21:00Z",
          "kind" : "reply",
          "text" : "este"
        }
      ]
    }
  ],
  "target" : "dev"
}"#;
    let queue: PromptQueue = serde_json::from_str(swift).unwrap();
    assert!(queue.auto);
    assert_eq!(queue.target.as_deref(), Some("dev"));
    let first = &queue.items[0];
    assert_eq!(first.short_id(), "3f9a2c");
    assert_eq!(
        first.sent_at,
        Some(UNIX_EPOCH + Duration::from_secs(1_787_678_363))
    );
    assert_eq!(first.thread[1].author, None);
    assert_eq!(first.thread[1].kind, MessageKind::Reply);

    // Gravar de volta: datas em segundos inteiros, sem chave nula, ordem alfabética.
    let dir = tempfile::tempdir().unwrap();
    let store = QueueStore::new(dir.path().to_owned());
    store.save(&queue);
    let text = std::fs::read_to_string(dir.path().join("queue.json")).unwrap();
    assert!(
        text.contains("\"sentAt\": \"2026-08-25T17:19:23Z\""),
        "{text}"
    );
    assert!(!text.contains("doneAt"));
    assert!(!text.contains("null"));
    assert!(text.find("\"auto\"").unwrap() < text.find("\"items\"").unwrap());
    assert_eq!(store.load(), queue);
}

#[test]
fn arquivo_ausente_ou_estragado_e_fila_vazia() {
    let dir = tempfile::tempdir().unwrap();
    let store = QueueStore::new(dir.path().to_owned());
    assert_eq!(store.load(), PromptQueue::default());
    std::fs::write(dir.path().join("queue.json"), "{ isto não é json").unwrap();
    assert_eq!(store.load(), PromptQueue::default());
}

#[test]
fn a_pasta_da_fila_e_da_bancada_e_do_no() {
    let store = QueueStore::for_node(std::path::Path::new("/w"), "aaaa1111", "fila");
    assert_eq!(
        store.folder(),
        std::path::Path::new("/w/aaaa1111/queues/fila")
    );
}

#[test]
fn importar_imagem_copia_para_a_pasta_com_a_extensao_em_minuscula() {
    let dir = tempfile::tempdir().unwrap();
    let source = dir.path().join("Print.JPG");
    std::fs::write(&source, [9, 9]).unwrap();
    let store = QueueStore::new(dir.path().join("fila"));
    let name = store.import_image(&source).unwrap();
    assert!(name.starts_with("img-") && name.ends_with(".jpg"), "{name}");
    assert_eq!(name.len(), "img-".len() + 8 + ".jpg".len());
    assert_eq!(std::fs::read(store.url_of(&name)).unwrap(), [9, 9]);
    assert_eq!(store.import_image(&dir.path().join("nao-existe.png")), None);
}

#[test]
fn as_tarefas_do_agente_saem_curtas() {
    let mut b = bench();
    let q = &mut b.controller;
    let it = q.add("faz isto", vec![], None);
    q.add("   ", vec![], None);
    q.agent("dev", "ask", &it.short_id(), "e agora?", t0())
        .unwrap();
    let tasks = q.tasks();
    assert_eq!(tasks.len(), 1, "a em branco não aparece");
    assert_eq!(
        tasks[0],
        serde_json::json!({
            "id": it.short_id(), "text": "faz isto", "status": "pending", "fila": "fila",
            "awaiting": true,
            "thread": [{"from": "dev", "kind": "question", "text": "e agora?"}],
        })
    );
}

#[test]
fn a_rota_queue_aplica_os_parametros_e_devolve_o_retrato() {
    let mut world = World::new();
    let mut b = bench();
    let q = &mut b.controller;
    let query = |pairs: &[(&str, &str)]| {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect::<std::collections::HashMap<_, _>>()
    };
    let added = q.control(&query(&[("add", "primeira")]), &mut world, t0());
    let id = added["added"].as_str().unwrap().to_owned();
    assert_eq!(added["items"][0]["status"], "pending");
    assert_eq!(added["destination"], "dev");
    assert_eq!(added["targets"], serde_json::json!(["dev"]));

    let sent = q.control(&query(&[("send", "next")]), &mut world, t0());
    assert_eq!(sent["error"], "");
    assert_eq!(sent["items"][0]["status"], "sent");
    assert_eq!(sent["items"][0]["sentTo"], "dev");

    let again = q.control(&query(&[("send", "next")]), &mut world, t0());
    assert_eq!(again["error"], "nada pendente");

    let toggled = q.control(
        &query(&[("done", &id), ("auto", "1"), ("to", "dev")]),
        &mut world,
        t0(),
    );
    assert_eq!(toggled["auto"], true);
    assert_eq!(toggled["items"][0]["status"], "done");

    let cleared = q.control(&query(&[("clear", "done")]), &mut world, t0());
    assert_eq!(cleared["items"], serde_json::json!([]));
}

// O `Codable` sintetizado do Swift exige `items` e `auto`: sem eles a fila
// inteira abre vazia. Porte fiel, conferido contra o Swift com load→save.
#[test]
fn fila_sem_items_ou_sem_auto_abre_vazia_como_no_swift() {
    let dir = tempfile::tempdir().unwrap();
    let store = QueueStore::new(dir.path().to_owned());
    for json in [
        r#"{"auto":false}"#,
        r#"{"items":[{"id":"abc123","text":"x","images":[],"status":"pending"}]}"#,
    ] {
        std::fs::write(dir.path().join("queue.json"), json).unwrap();
        assert_eq!(store.load(), PromptQueue::default(), "{json}");
    }
}

// O `.iso8601` do Foundation só aceita `T` e `Z` em maiúsculas; arquivo com
// data em minúsculas esvazia a fila.
#[test]
fn data_com_t_ou_z_minusculos_esvazia_a_fila_como_no_swift() {
    let dir = tempfile::tempdir().unwrap();
    let store = QueueStore::new(dir.path().to_owned());
    let with = |date: &str| {
        format!(
            r#"{{"auto":false,"items":[{{"id":"a1b2c3","text":"x","images":[],"status":"sent","sentAt":"{date}"}}]}}"#
        )
    };
    std::fs::write(dir.path().join("queue.json"), with("2026-08-25T17:19:23Z")).unwrap();
    assert_eq!(store.load().items.len(), 1);
    for lower in ["2026-08-25t17:19:23Z", "2026-08-25T17:19:23z"] {
        std::fs::write(dir.path().join("queue.json"), with(lower)).unwrap();
        assert_eq!(store.load(), PromptQueue::default(), "{lower}");
    }
}

#[test]
fn a_manchete_corta_por_grafema_e_nao_parte_um_caractere_composto() {
    // 59 letras + "é" decomposto (e + acento): são 60 grafemas e 61 `char`s.
    let text = format!("{}e\u{301}", "x".repeat(59));
    assert_eq!(
        item("x", &text).headline(),
        text,
        "60 grafemas cabem inteiros"
    );
    let longer = format!("{text}y");
    let cut = item("x", &longer).headline();
    assert!(
        cut.ends_with("e\u{301}…"),
        "o acento não é separado da letra: {cut:?}"
    );
}

#[test]
fn imagem_salva_nao_deixa_temporario_para_tras() {
    let dir = tempfile::tempdir().unwrap();
    let store = QueueStore::new(dir.path().join("fila"));
    let name = store.save_image(&[1, 2, 3]).unwrap();
    let left: Vec<String> = std::fs::read_dir(store.folder())
        .unwrap()
        .flatten()
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .collect();
    assert_eq!(left, [name]);
}

// Como o `JSONDecoder` do Swift abre: BOM e a primeira chave repetida vence.
// (O float integral não aparece aqui: a fila não tem campo numérico.)
#[test]
fn queue_json_abre_como_o_jsondecoder_com_bom_e_chave_repetida() {
    let dir = tempfile::tempdir().unwrap();
    let store = QueueStore::new(dir.path().to_owned());
    let item = r#"{"id":"abc123","text":"x","images":[],"status":"pending"}"#;
    let mut bom = vec![0xEF, 0xBB, 0xBF];
    bom.extend_from_slice(format!(r#"{{"auto":false,"items":[{item}]}}"#).as_bytes());
    std::fs::write(dir.path().join("queue.json"), bom).unwrap();
    assert_eq!(store.load().items.len(), 1, "BOM");

    // A primeira chave vence: `auto` vale true, `text` fica "primeiro".
    let dup = r#"{"auto":true,"auto":false,"items":[{"id":"abc123","text":"primeiro","text":"segundo","images":[],"status":"pending"}]}"#;
    std::fs::write(dir.path().join("queue.json"), dup).unwrap();
    let loaded = store.load();
    assert!(loaded.auto);
    assert_eq!(loaded.items[0].text, "primeiro");
}
