//! Uma conexão do socket: lê a requisição, pergunta ao ator e responde — ou,
//! no `GET /ui`, vira o canal de mensagens até o cliente fechar.

use serde_json::json;
use tokio::io::{AsyncReadExt, AsyncWriteExt, ReadHalf, WriteHalf};
use tokio::sync::{mpsc, oneshot};

use super::actor::{CLIENT_QUEUE, ClientId, HttpReply, Msg, WireLine};
use std::sync::Arc;

use crate::features::terminal::peer::ancestry;
use crate::ports::local_conn::{LocalConn, LocalStream};
use crate::ports::procs::ProcessDriver;
use crate::protocol::ProtocolError;
use crate::protocol::http::{Parsed, json_response, parse_request, upgrade_response};
use crate::protocol::message::{Reply, parse_command};
use crate::protocol::routes::{Route, route};

/// Teto de uma linha do `/ui`. Um comando é pequeno; só uma colagem enorme em
/// `input` chega perto disto.
pub const MAX_UI_LINE: usize = 4 << 20;

const CHUNK: usize = 16 * 1024;

pub async fn serve(conn: LocalConn, actor: mpsc::Sender<Msg>, procs: Arc<dyn ProcessDriver>) {
    let peer = conn.peer_pid;
    let mut stream = conn.stream;
    let mut buf = Vec::with_capacity(CHUNK);
    let mut chunk = vec![0u8; CHUNK];
    let mut eof = false;
    let (request, consumed) = loop {
        match parse_request(&buf, eof) {
            Ok(Parsed::Complete { request, consumed }) => break (request, consumed),
            Ok(Parsed::Partial) => {}
            // Corpo acima do teto: divergência do Swift, com resposta.
            Err(err @ ProtocolError::BodyTooLarge(_)) => {
                respond(&mut stream, 413, &err.to_string()).await;
                return;
            }
            // Cabeçalho que não termina, grande demais ou fora de UTF-8: o
            // Swift fechava sem responder, e o `probe` (conecta e fecha) cai
            // aqui também.
            Err(_) => return,
        }
        match stream.read(&mut chunk).await {
            Ok(0) => eof = true,
            Ok(n) => buf.extend_from_slice(&chunk[..n]),
            Err(_) => return,
        }
    };

    let route = match route(&request) {
        Ok(route) => route,
        Err(rejected) => {
            respond(&mut stream, rejected.status, &rejected.error).await;
            return;
        }
    };

    if route == Route::Ui {
        if stream.write_all(&upgrade_response()).await.is_err() {
            return;
        }
        let leftover = buf.split_off(consumed);
        ui(stream, leftover, actor).await;
        return;
    }

    // Quem chamou sai do kernel, não do pedido: o pid do par e os pais dele,
    // lidos aqui porque a tabela de processos bloqueia. O ator acha o dono.
    let caller = match peer {
        Some(pid) => tokio::task::spawn_blocking(move || ancestry(pid, |p| procs.parent_of(p)))
            .await
            .unwrap_or_default(),
        None => Vec::new(),
    };
    let (tx, rx) = oneshot::channel();
    let reply = match actor
        .send(Msg::Http {
            route,
            caller,
            reply: tx,
        })
        .await
    {
        Ok(()) => rx.await.unwrap_or_else(|_| unavailable()),
        Err(_) => unavailable(),
    };
    let _ = stream
        .write_all(&json_response(reply.status, &reply.json))
        .await;
    let _ = stream.shutdown().await;
}

fn unavailable() -> HttpReply {
    HttpReply {
        status: 503,
        json: json!({"ok": false, "error": "o core está encerrando"}),
    }
}

async fn respond(stream: &mut Box<dyn LocalStream>, status: u16, error: &str) {
    let body = json!({"ok": false, "error": error});
    let _ = stream.write_all(&json_response(status, &body)).await;
    let _ = stream.shutdown().await;
}

/// O canal `/ui`: um leitor de linhas que manda comandos ao ator e um
/// escritor que esvazia a fila do cliente.
///
/// Só o ator segura a ponta de envio da fila — e a ponta de `alive`. Quando
/// ele desliga o cliente (fila cheia, encerramento), as duas caem, e a conexão
/// fecha na hora: a UI recebe EOF e reconecta, em vez de ficar falando com
/// uma conexão que ninguém mais escuta.
async fn ui(stream: Box<dyn LocalStream>, leftover: Vec<u8>, actor: mpsc::Sender<Msg>) {
    let (queue, outbox) = mpsc::channel::<WireLine>(CLIENT_QUEUE);
    let (alive, hung_up) = oneshot::channel::<()>();
    let (tx, rx) = oneshot::channel();
    let open = Msg::UiOpen {
        queue,
        alive,
        reply: tx,
    };
    if actor.send(open).await.is_err() {
        return;
    }
    let Ok(client) = rx.await else { return };

    let (reader, writer) = tokio::io::split(stream);
    let mut writing = tokio::spawn(write_lines(writer, outbox));
    tokio::select! {
        () = read_lines(reader, leftover, client, &actor) => {
            // O cliente fechou a escrita: o ator larga a fila, e o escritor
            // entrega o que falta e fecha.
            let _ = actor.send(Msg::UiClose { client }).await;
            let _ = writing.await;
        }
        _ = &mut writing => {
            // A escrita falhou: o cliente sumiu.
            let _ = actor.send(Msg::UiClose { client }).await;
        }
        _ = hung_up => {
            // O ator desligou o cliente. O escritor pode estar preso num
            // `write` que o cliente não lê; larga tudo, e a conexão fecha. O
            // que ainda estava na fila se perde de propósito: o cliente
            // reconecta e cada assinatura lhe manda o estado inteiro.
            writing.abort();
        }
    }
}

async fn write_lines(
    mut writer: WriteHalf<Box<dyn LocalStream>>,
    mut outbox: mpsc::Receiver<WireLine>,
) {
    while let Some(line) = outbox.recv().await {
        if writer.write_all(&line).await.is_err() {
            return;
        }
    }
    let _ = writer.shutdown().await;
}

async fn read_lines(
    mut reader: ReadHalf<Box<dyn LocalStream>>,
    mut buf: Vec<u8>,
    client: ClientId,
    actor: &mpsc::Sender<Msg>,
) {
    let mut chunk = vec![0u8; CHUNK];
    let mut scanned = 0;
    loop {
        while let Some(pos) = buf[scanned..].iter().position(|b| *b == b'\n') {
            let end = scanned + pos;
            let line: Vec<u8> = buf.drain(..=end).collect();
            scanned = 0;
            if !handle_line(&line[..line.len() - 1], client, actor).await {
                return;
            }
        }
        scanned = buf.len();
        if buf.len() > MAX_UI_LINE {
            reject(actor, client, 0, "linha maior que 4 MiB; o canal fecha").await;
            return;
        }
        match reader.read(&mut chunk).await {
            Ok(0) | Err(_) => return,
            Ok(n) => buf.extend_from_slice(&chunk[..n]),
        }
    }
}

/// Devolve `false` quando o canal tem de fechar.
async fn handle_line(line: &[u8], client: ClientId, actor: &mpsc::Sender<Msg>) -> bool {
    let text = String::from_utf8_lossy(line);
    let text = text.trim();
    if text.is_empty() {
        return true;
    }
    match parse_command(text) {
        Ok(command) => actor.send(Msg::UiCommand { client, command }).await.is_ok(),
        // Comando ruim com id ganha resposta endereçada; sem id, `re` 0.
        Err(ProtocolError::BadCommand { id, reason }) => reject(actor, client, id, &reason).await,
        Err(err) => reject(actor, client, 0, &err.to_string()).await,
    }
}

/// O erro vai pelo ator, como toda resposta: é ele o dono da fila.
async fn reject(actor: &mpsc::Sender<Msg>, client: ClientId, re: u64, error: &str) -> bool {
    let reply = Reply::err(re, error);
    actor.send(Msg::UiReply { client, reply }).await.is_ok()
}
