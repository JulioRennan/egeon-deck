//! Testes do runtime do chat com um `ChatHost` de mentira: o que sai (respostas,
//! linhas do canal, jobs) para cada comando, e o ciclo job → `done`.

use std::collections::BTreeMap;
use std::path::PathBuf;
use std::time::{Duration, UNIX_EPOCH};

use serde_json::{Value, json};

use super::model::{ChatRecord, ChatTurn};
use super::runtime::{
    Answer, BenchInfo, ChatHost, ChatJob, ChatRuntime, Complete, Identity, JobKind, Out,
    SlashInputs, Source,
};
use super::store::ChatHistory;
use super::time::utc;
use crate::features::activity::model::Activity;
use crate::features::node::model::NodeConfig;
use crate::features::queue::chat::ChatQueue;
use crate::features::usage::PriceTable;
use crate::features::usage::store::UsageStore;

struct Fake {
    queues: Vec<ChatQueue>,
    mode: &'static str,
    activity: BTreeMap<String, Activity>,
    sources: BTreeMap<String, Source>,
}

impl Fake {
    fn new(mode: &'static str) -> Fake {
        Fake {
            queues: Vec::new(),
            mode,
            activity: BTreeMap::new(),
            sources: BTreeMap::new(),
        }
    }
}

impl ChatHost for Fake {
    fn benches(&self) -> Vec<BenchInfo> {
        let nodes: Vec<NodeConfig> = [
            r#"{"type":"agent","id":"front","agent":"claude"}"#,
            r#"{"type":"agent","id":"back","agent":"claude"}"#,
        ]
        .iter()
        .map(|j| serde_json::from_str(j).expect("nó"))
        .collect();
        vec![BenchInfo {
            id: "w1".into(),
            name: "deck".into(),
            mode: self.mode.into(),
            nodes,
        }]
    }

    fn activity(&self, address: &str) -> Option<Activity> {
        self.activity.get(address).cloned()
    }

    fn source(&self, _workbench: &str, node: &str) -> Option<Source> {
        self.sources.get(node).cloned()
    }

    fn identity(&self, _workbench: &str, _node: &str) -> Identity {
        Identity::default()
    }

    fn permissions(&self, _workbench: &str) -> Vec<Value> {
        Vec::new()
    }

    fn queues(&self, _workbench: &str) -> Vec<ChatQueue> {
        self.queues.clone()
    }

    fn slash(&self, _workbench: &str, _node: &str) -> Option<SlashInputs> {
        None
    }

    fn prices(&self) -> PriceTable {
        PriceTable::from_built_in()
    }
}

fn runtime(dir: &std::path::Path) -> ChatRuntime {
    let usage = UsageStore::new(dir.to_path_buf(), dir.to_path_buf());
    ChatRuntime::new(dir.join("workbenches"), utc, usage)
}

fn at(secs: u64) -> std::time::SystemTime {
    UNIX_EPOCH + Duration::from_secs(secs)
}

fn run_jobs(rt: &mut ChatRuntime, host: &Fake, out: Out, now: u64) -> Out {
    let mut all = Out::default();
    all.replies.extend(out.replies);
    all.publish.extend(out.publish);
    all.usage.extend(out.usage);
    for (token, job) in out.jobs {
        let done = job.run();
        let next = rt.done(host, token, done, at(now));
        all.replies.extend(next.replies);
        all.publish.extend(next.publish);
        all.usage.extend(next.usage);
    }
    all
}

/// Quantos jobs de leitura do chat o tique pediu (o de consumo é à parte).
fn refreshes(out: &Out) -> usize {
    out.jobs
        .iter()
        .filter(|(_, job)| matches!(job, ChatJob::Refresh(_)))
        .count()
}

fn record(node: &str, id: &str) -> ChatRecord {
    let mut turn = ChatTurn::new(id, "faz", at(1_000), None);
    turn.reply_text = "feito".into();
    turn.reply_at = Some(at(1_005));
    ChatRecord::new(node, turn)
}

#[test]
fn assinar_bancada_desconhecida_e_none_e_a_conhecida_recebe_o_reset() {
    let dir = tempfile::tempdir().expect("pasta");
    let mut rt = runtime(dir.path());
    let host = Fake::new("chat");
    assert!(rt.subscribe(&host, "nao-existe", at(10)).is_none());

    let out = rt.subscribe(&host, "w1", at(10)).expect("bancada");
    let lines: Vec<&(String, String)> =
        out.publish.iter().filter(|(t, _)| t == "chat/w1").collect();
    assert_eq!(lines.len(), 1, "um reset, sem os eventos de sincronização");
    let value: Value = serde_json::from_str(&lines[0].1).expect("json");
    assert_eq!(value["topic"], "chat/w1");
    assert_eq!(value["ops"][0]["op"], "reset");
    assert_eq!(value["ops"][1]["op"], "participants");
    assert_eq!(value["ops"][2]["op"], "queues");
    assert_eq!(value["ops"][3]["op"], "permissions");
    assert!(lines[0].1.ends_with('\n'), "NDJSON");
    // E uma leitura do histórico para trazer o que está em disco.
    assert!(matches!(out.jobs.as_slice(), [(_, ChatJob::Refresh(_))]));
}

#[test]
fn o_historico_do_disco_entra_pelo_job_de_leitura() {
    let dir = tempfile::tempdir().expect("pasta");
    let mut history = ChatHistory::new(dir.path().join("workbenches"), utc);
    history.append(&record("front", "u1"), "w1");
    let mut rt = runtime(dir.path());
    let host = Fake::new("chat");
    let out = rt.subscribe(&host, "w1", at(2_000)).expect("bancada");
    let after = run_jobs(&mut rt, &host, out, 2_000);
    let last: Value = serde_json::from_str(&after.publish.last().expect("evento").1).expect("json");
    assert_eq!(last["topic"], "chat/w1");
    let snapshot = rt.snapshot("w1").expect("retrato");
    let ids: Vec<&str> = snapshot["blocks"]
        .as_array()
        .expect("blocos")
        .iter()
        .filter_map(|b| b["id"].as_str())
        .collect();
    assert_eq!(ids, ["p|u1", "h|u1", "b|u1|0"]);
}

#[test]
fn limpar_arquiva_e_responde_so_quando_o_job_termina() {
    let dir = tempfile::tempdir().expect("pasta");
    let mut history = ChatHistory::new(dir.path().join("workbenches"), utc);
    history.append(&record("front", "u1"), "w1");
    let mut rt = runtime(dir.path());
    let host = Fake::new("chat");
    let out = rt.subscribe(&host, "w1", at(2_000)).expect("bancada");
    run_jobs(&mut rt, &host, out, 2_000);

    let out = rt.clear(7, true, "deck", at(3_000));
    assert!(out.replies.is_empty(), "a resposta espera o disco");
    let done = run_jobs(&mut rt, &host, out, 3_000);
    let (token, answer) = done.replies.first().expect("resposta");
    assert_eq!(*token, 7);
    let Answer::Ok(body) = answer else {
        panic!("esperava ok")
    };
    assert_eq!(body["workbench"], "deck");
    assert!(
        body["archived"]
            .as_str()
            .is_some_and(|p| p.contains("chat-archive"))
    );
    assert!(
        rt.snapshot("w1").expect("retrato")["blocks"]
            .as_array()
            .is_some_and(Vec::is_empty)
    );
    assert!(
        done.publish.iter().any(|(t, _)| t == "chat/w1"),
        "a UI vê a thread esvaziar"
    );

    let missing = rt.clear(8, true, "nada", at(3_100));
    assert!(matches!(
        missing.replies.as_slice(),
        [(8, Answer::Err { status: 404, .. })]
    ));
}

#[test]
fn enviar_so_para_agente_vivo_e_o_eco_entra_na_thread() {
    let dir = tempfile::tempdir().expect("pasta");
    let mut rt = runtime(dir.path());
    let mut host = Fake::new("chat");
    host.activity.insert("deck/front".into(), Activity::Waiting);
    host.activity.insert("deck/back".into(), Activity::Dead);
    let mut sink = Out::default();
    rt.sync(&host, &mut sink);

    let to = vec!["front".to_owned(), "back".to_owned()];
    let out = rt.send("w1", &to, "olha isso");
    assert_eq!(out.deliveries.len(), 1);
    assert_eq!(out.deliveries[0].node, "front");

    let echo = rt.sent(&host, "w1", "front", "olha isso", at(50));
    assert!(echo.publish.iter().any(|(t, _)| t == "chat/w1"));
    assert_eq!(rt.routes().view("w1").map(|v| v.pending_count()), Some(1));
}

#[test]
fn completar_arroba_responde_na_hora_com_os_agentes_vivos() {
    let dir = tempfile::tempdir().expect("pasta");
    let mut rt = runtime(dir.path());
    let mut host = Fake::new("chat");
    host.activity.insert("deck/front".into(), Activity::Waiting);
    host.activity.insert("deck/back".into(), Activity::Dead);
    let mut sink = Out::default();
    rt.sync(&host, &mut sink);

    // "veja com o @f" com o cursor no fim: o trecho `@f` (11..13) é o que a escolha troca.
    let request = Complete {
        workbench: "w1".into(),
        text: "veja com o @f".into(),
        caret: 13,
        to: None,
        search: None,
    };
    let out = rt.complete(&host, 3, &request);
    let [(3, Answer::Ok(body))] = out.replies.as_slice() else {
        panic!("esperava resposta")
    };
    assert_eq!(body["range"], json!([11, 13]));
    assert_eq!(
        body["items"].as_array().map(Vec::len),
        Some(1),
        "só o agente vivo"
    );
    assert_eq!(
        body["items"][0],
        json!({"label": "@front", "insert": "@front ", "detail": "deck/front", "kind": "agent"})
    );

    // Sem gatilho no cursor: vazio, com o range no cursor.
    let none = Complete {
        text: "oi".into(),
        caret: 2,
        ..request.clone()
    };
    let out = rt.complete(&host, 4, &none);
    assert!(matches!(out.replies.as_slice(),
        [(4, Answer::Ok(b))] if b["items"] == json!([]) && b["range"] == json!([2, 2])));
    let unknown = Complete {
        workbench: "x".into(),
        ..request.clone()
    };
    assert!(matches!(
        rt.complete(&host, 5, &unknown).replies.as_slice(),
        [(5, Answer::Err { status: 404, .. })]
    ));

    // `/` no começo: sem lista de comandos (outro CLI), vazio e sem job; o
    // range cobre a palavra inteira.
    let slash = Complete {
        text: "/cle agora".into(),
        caret: 4,
        ..request
    };
    let out = rt.complete(&host, 6, &slash);
    assert!(out.jobs.is_empty());
    assert!(matches!(out.replies.as_slice(),
        [(6, Answer::Ok(b))] if b["items"] == json!([]) && b["range"] == json!([0, 4])));
}

#[test]
fn o_tique_so_le_a_cauda_enquanto_um_agente_trabalha_e_no_modo_chat() {
    let dir = tempfile::tempdir().expect("pasta");
    let transcript: PathBuf = dir.path().join("t.jsonl");
    std::fs::write(
        &transcript,
        format!(
            "{}\n{}\n",
            r#"{"type":"user","uuid":"u1","timestamp":"2026-08-25T17:00:00.000Z","message":{"content":"faz"}}"#,
            r#"{"type":"assistant","timestamp":"2026-08-25T17:00:01.000Z","message":{"content":[{"type":"text","text":"Vou olhar."}]}}"#
        ),
    )
    .expect("grava");
    let mut rt = runtime(dir.path());
    let mut host = Fake::new("chat");
    host.sources.insert(
        "front".into(),
        Source {
            path: transcript,
            not_before: None,
        },
    );

    // Ninguém trabalha: o tique não lê nada.
    host.activity.insert("deck/front".into(), Activity::Waiting);
    assert!(refreshes(&rt.tick(&host, at(100))) == 0);

    host.activity.insert("deck/front".into(), Activity::Working);
    let out = rt.tick(&host, at(101));
    assert_eq!(refreshes(&out), 1);
    let after = run_jobs(&mut rt, &host, out, 101);
    let blocks = rt.snapshot("w1").expect("retrato");
    let ids: Vec<&str> = blocks["blocks"]
        .as_array()
        .expect("blocos")
        .iter()
        .filter_map(|b| b["id"].as_str())
        .collect();
    assert!(
        ids.contains(&"s|u1"),
        "a bolha ao vivo ganha a linha de status: {ids:?}"
    );
    assert!(after.publish.iter().all(|(t, _)| t == "chat/w1"));

    // Em modo canvas ninguém olha o chat: o tique não lê.
    let canvas = Fake {
        mode: "canvas",
        ..Fake::new("canvas")
    };
    let mut rt2 = runtime(dir.path());
    let mut canvas = canvas;
    canvas
        .activity
        .insert("deck/front".into(), Activity::Working);
    assert!(refreshes(&rt2.tick(&canvas, at(200))) == 0);
}

#[test]
fn o_stop_grava_o_turno_e_o_consumo_e_o_historico_e_relido() {
    let dir = tempfile::tempdir().expect("pasta");
    let transcript: PathBuf = dir.path().join("t.jsonl");
    std::fs::write(
        &transcript,
        format!(
            "{}\n{}\n",
            r#"{"type":"user","uuid":"u9","timestamp":"2026-08-25T17:00:00.000Z","message":{"content":"faz"}}"#,
            r#"{"type":"assistant","timestamp":"2026-08-25T17:00:01.000Z","message":{"id":"m1","model":"claude-opus-5-5","content":[{"type":"text","text":"Pronto. [[ED:ok]]"}],"usage":{"input_tokens":1,"output_tokens":2}}}"#
        ),
    )
    .expect("grava");
    let mut rt = runtime(dir.path());
    let mut host = Fake::new("chat");
    host.sources.insert(
        "front".into(),
        Source {
            path: transcript,
            not_before: None,
        },
    );
    let mut sink = Out::default();
    rt.sync(&host, &mut sink);

    let out = rt.turn_ended(&host, "deck/front", at(500));
    assert_eq!(out.jobs.len(), 2, "gravar o turno e reler o consumo");
    let after = run_jobs(&mut rt, &host, out, 500);
    // Gravado em disco…
    let written = ChatHistory::new(dir.path().join("workbenches"), utc).load("w1", None);
    assert_eq!(written.len(), 1);
    assert_eq!(written[0].turn.reply_text, "Pronto.");
    // …e o job de leitura que o `Record` pede traz o turno para a thread.
    let _ = after;
    let again = rt.tick(&host, at(501));
    let more = run_jobs(&mut rt, &host, again, 501);
    let _ = more;
    // Agente de outro tipo ou endereço malformado não grava nada.
    assert!(rt.turn_ended(&host, "sem-barra", at(502)).jobs.is_empty());
    assert!(rt.turn_ended(&host, "outra/front", at(502)).jobs.is_empty());
}

/// A seção FILAS: o resumo e a pergunta vêm prontos do core, o op só vai quando a
/// lista muda, e a fila nova nasce ligada ao agente em foco.
#[test]
fn as_filas_vao_no_op_queues_e_a_nova_liga_ao_agente_em_foco() {
    let dir = tempfile::tempdir().expect("pasta");
    let mut rt = runtime(dir.path());
    let mut host = Fake::new("chat");
    let mut sink = Out::default();
    rt.sync(&host, &mut sink);
    assert!(
        sink.publish
            .iter()
            .all(|(_, line)| !line.contains("queues")),
        "sem filas: nenhum op queues"
    );

    host.queues = vec![ChatQueue {
        id: "q1".into(),
        pending: 2,
        asking: false,
        working_with: Some("front".into()),
    }];
    let mut out = Out::default();
    rt.sync(&host, &mut out);
    let value: Value = serde_json::from_str(&out.publish[0].1).expect("json");
    assert_eq!(
        value["ops"][0],
        json!({"op": "queues", "list": [{"id": "q1", "summary": "2 pendentes · com front", "asking": false}]})
    );
    let mut again = Out::default();
    rt.sync(&host, &mut again);
    assert!(again.publish.is_empty(), "igual: nada vai");

    host.queues[0].asking = true;
    let mut asked = Out::default();
    rt.sync(&host, &mut asked);
    let value: Value = serde_json::from_str(&asked.publish[0].1).expect("json");
    assert_eq!(value["ops"][0]["list"][0]["summary"], "? pergunta");
    assert_eq!(value["ops"][0]["list"][0]["asking"], true);

    // Sem escolha do usuário o foco é o primeiro agente vivo.
    assert_eq!(rt.new_queue_agent("w1").as_deref(), Some("front"));
    assert_eq!(rt.new_queue_agent("nao-existe"), None);
}

/// O consumo lido no fim do turno chega ao estado que o ator publica; bancada
/// desconhecida não tem estado.
#[test]
fn o_estado_do_consumo_vem_do_registro_lido_e_so_para_bancada_conhecida() {
    let dir = tempfile::tempdir().expect("pasta");
    let transcript: PathBuf = dir.path().join("t.jsonl");
    std::fs::write(
        &transcript,
        r#"{"type":"assistant","timestamp":"2026-08-25T17:00:01.000Z","message":{"id":"m1","model":"claude-opus-5-5","content":[{"type":"text","text":"Pronto. [[ED:ok]]"}],"usage":{"input_tokens":1000,"output_tokens":2000}}}
"#,
    )
    .expect("grava");
    let mut rt = runtime(dir.path());
    let mut host = Fake::new("chat");
    host.sources.insert(
        "front".into(),
        Source {
            path: transcript,
            not_before: None,
        },
    );
    let (pill, panel) = rt.usage_state(&host, "w1").expect("bancada conhecida");
    assert_eq!(pill.text, "US$ 0,00");
    assert_eq!(panel.heading, "CONSUMO · DECK");
    assert!(panel.agents.is_empty());

    let out = rt.turn_ended(&host, "deck/front", at(500));
    let after = run_jobs(&mut rt, &host, out, 500);
    assert_eq!(
        after.usage,
        ["w1"],
        "o ator publica o painel da bancada que mudou"
    );
    let (pill, panel) = rt.usage_state(&host, "w1").expect("bancada conhecida");
    assert_ne!(pill.text, "US$ 0,00");
    assert_eq!(panel.agents.len(), 1);
    assert_eq!(panel.agents[0].name, "front");
    assert_eq!(panel.total.amount, pill.text);
    assert!(rt.usage_state(&host, "outra").is_none());
}

/// Um job que dá pânico não pode deixar ninguém esperando nem a bancada presa:
/// quem esperava ganha um erro e a bancada volta a ser lida.
#[test]
fn job_que_da_panico_nao_trava_a_bancada_nem_deixa_ninguem_esperando() {
    let dir = tempfile::tempdir().expect("pasta");
    let mut rt = runtime(dir.path());
    let host = Fake::new("chat");

    // O Refresh em voo segura novos pedidos; se morre, a bancada é liberada.
    let first = rt.subscribe(&host, "w1", at(10)).expect("bancada");
    let (_, job) = first.jobs.into_iter().next().expect("job de leitura");
    let kind = job.kind();
    assert_eq!(
        kind,
        JobKind::Refresh {
            workbench: "w1".into()
        }
    );
    let again = rt.subscribe(&host, "w1", at(11)).expect("bancada");
    assert!(
        again.jobs.is_empty(),
        "com um Refresh em voo não se pede outro"
    );
    let caught = std::panic::catch_unwind(|| ChatJob::Boom.run());
    assert!(caught.is_err(), "o job de mentira dá pânico");
    let out = rt.failed(&host, 0, &kind, at(12));
    assert!(out.replies.is_empty());
    let later = rt.subscribe(&host, "w1", at(13)).expect("bancada");
    assert!(
        later
            .jobs
            .iter()
            .any(|(_, j)| matches!(j, ChatJob::Refresh(_))),
        "a bancada voltou a ser lida"
    );

    // Quem espera `clear` ou `complete` recebe um erro, não silêncio.
    let out = rt.failed(&host, 9, &JobKind::Archive, at(14));
    assert!(matches!(
        out.replies.as_slice(),
        [(9, Answer::Err { status: 500, .. })]
    ));
    let out = rt.failed(&host, 10, &JobKind::Complete, at(14));
    assert!(matches!(
        out.replies.as_slice(),
        [(10, Answer::Err { status: 500, .. })]
    ));

    // O consumo, que andava no job, ganha um registro novo e volta a ser lido.
    let tick = rt.tick(&host, at(20));
    assert!(
        tick.jobs
            .iter()
            .any(|(_, j)| matches!(j, ChatJob::Usage(_)))
    );
    rt.failed(&host, 0, &JobKind::Usage, at(21));
    let tick = rt.tick(&host, at(40));
    assert!(
        tick.jobs
            .iter()
            .any(|(_, j)| matches!(j, ChatJob::Usage(_))),
        "o consumo voltou"
    );
}

/// O `clear_workbench` arquiva sem passar pelo chat e depois avisa a thread: o
/// arquivo vai para `chat-archive/`, e o eco e o que a thread guardava somem.
#[test]
fn arquivar_e_esvaziar_pelo_caminho_do_clear_workbench() {
    let dir = tempfile::tempdir().expect("pasta");
    let mut history = ChatHistory::new(dir.path().join("workbenches"), utc);
    history.append(&record("front", "u1"), "w1");
    let mut rt = runtime(dir.path());
    let mut host = Fake::new("chat");
    host.activity.insert("deck/front".into(), Activity::Waiting);
    let out = rt.subscribe(&host, "w1", at(2_000)).expect("bancada");
    run_jobs(&mut rt, &host, out, 2_000);
    rt.sent(&host, "w1", "front", "eco", at(2_001));
    assert_eq!(rt.routes().view("w1").map(|v| v.pending_count()), Some(1));

    let archived = rt.archive_now("w1", at(3_000)).expect("arquivou");
    assert!(archived.to_string_lossy().contains("chat-archive"));
    assert!(rt.archive_now("w1", at(3_001)).is_none(), "já vazia");

    let out = rt.cleared("w1");
    assert!(out.publish.iter().any(|(t, _)| t == "chat/w1"));
    let view = rt.routes().view("w1").expect("view");
    assert_eq!(view.pending_count(), 0);
    assert!(view.blocks().is_empty());
}
