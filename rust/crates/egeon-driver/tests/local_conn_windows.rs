//! Escuta local de verdade no Windows, sempre numa pasta temporária — nunca
//! `~/.egeon`. O par do `local_conn.rs` do unix; o cliente é o socket
//! bloqueante da `uds_windows`, porque o tokio não tem `AF_UNIX` no Windows.
//!
//! O `Path::exists` segue o ponto de nova análise do socket e diz `false` com
//! o arquivo lá: aqui se pergunta pelo `symlink_metadata`.

#![cfg(windows)]
#![allow(clippy::unwrap_used, clippy::expect_used)]

use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use egeon_core::ports::local_conn::{LocalConnDriver, LocalConnError, Probe};
use egeon_driver::SystemLocalConn;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use uds_windows::{UnixListener as StdListener, UnixStream};

fn socket_in(dir: &tempfile::TempDir) -> PathBuf {
    dir.path().join("sock")
}

fn my_pid() -> Option<u32> {
    Some(std::process::id())
}

fn on_disk(path: &Path) -> bool {
    std::fs::symlink_metadata(path).is_ok()
}

#[tokio::test(flavor = "multi_thread")]
async fn accept_devolve_o_pid_de_quem_conectou() {
    let dir = tempfile::tempdir().unwrap();
    let path = socket_in(&dir);
    let listener = SystemLocalConn.listen(&path).unwrap();

    let _client = UnixStream::connect(&path).unwrap();
    let conn = listener.accept().await.unwrap();

    assert_eq!(conn.peer_pid, my_pid());
}

#[tokio::test(flavor = "multi_thread")]
async fn conexao_aceita_le_e_escreve() {
    let dir = tempfile::tempdir().unwrap();
    let path = socket_in(&dir);
    let listener = SystemLocalConn.listen(&path).unwrap();

    let mut client = UnixStream::connect(&path).unwrap();
    let mut conn = listener.accept().await.unwrap();
    client.write_all(b"GET /targets").unwrap();
    let mut received = [0u8; 12];
    conn.stream.read_exact(&mut received).await.unwrap();
    conn.stream.write_all(b"ok").await.unwrap();
    conn.stream.flush().await.unwrap();
    let mut reply = [0u8; 2];
    client.read_exact(&mut reply).unwrap();

    assert_eq!(&received, b"GET /targets");
    assert_eq!(&reply, b"ok");
}

/// O core larga a conexão depois de responder (`Connection: close`): o par
/// tem de ver o fim, ou o `egeon` esperaria para sempre.
#[tokio::test(flavor = "multi_thread")]
async fn largar_a_conexao_fecha_para_o_par_e_o_par_fechado_chega_ao_core() {
    let dir = tempfile::tempdir().unwrap();
    let path = socket_in(&dir);
    let listener = SystemLocalConn.listen(&path).unwrap();

    let mut client = UnixStream::connect(&path).unwrap();
    let mut conn = listener.accept().await.unwrap();
    conn.stream.write_all(b"tchau").await.unwrap();
    drop(conn);
    let mut everything = Vec::new();
    client.read_to_end(&mut everything).unwrap();
    assert_eq!(everything, b"tchau");

    let client = UnixStream::connect(&path).unwrap();
    let mut conn = listener.accept().await.unwrap();
    drop(client);
    let mut rest = Vec::new();
    let read = tokio::time::timeout(
        std::time::Duration::from_secs(10),
        conn.stream.read_to_end(&mut rest),
    )
    .await;
    assert!(matches!(read, Ok(Ok(0))), "veio {read:?}");
}

#[tokio::test(flavor = "multi_thread")]
async fn probe_enxerga_instancia_viva_e_ausente() {
    let dir = tempfile::tempdir().unwrap();
    let path = socket_in(&dir);
    assert_eq!(SystemLocalConn.probe(&path), Probe::Nobody);

    let listener = SystemLocalConn.listen(&path).unwrap();
    assert_eq!(SystemLocalConn.probe(&path), Probe::Alive { pid: my_pid() });

    drop(listener);
    assert_eq!(SystemLocalConn.probe(&path), Probe::Nobody);
    assert!(!on_disk(&path), "largar a escuta devia apagar o arquivo");
}

#[tokio::test(flavor = "multi_thread")]
async fn segunda_escuta_no_mesmo_caminho_e_recusada() {
    let dir = tempfile::tempdir().unwrap();
    let path = socket_in(&dir);
    let _first = SystemLocalConn.listen(&path).unwrap();

    let second = SystemLocalConn.listen(&path);

    assert!(
        matches!(second, Err(LocalConnError::AlreadyListening { pid }) if pid == my_pid()),
        "veio algo diferente de AlreadyListening"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn arquivo_orfao_de_crash_e_substituido() {
    let dir = tempfile::tempdir().unwrap();
    let path = socket_in(&dir);
    // Um socket largado deixa o arquivo no disco, como no unix.
    drop(StdListener::bind(&path).unwrap());
    assert!(on_disk(&path));
    assert_eq!(SystemLocalConn.probe(&path), Probe::Nobody);

    let listener = SystemLocalConn.listen(&path).unwrap();
    let _client = UnixStream::connect(&path).unwrap();

    assert_eq!(listener.accept().await.unwrap().peer_pid, my_pid());
}

#[tokio::test(flavor = "multi_thread")]
async fn is_current_acompanha_o_arquivo_e_drop_nao_apaga_o_de_outro() {
    let dir = tempfile::tempdir().unwrap();
    let path = socket_in(&dir);
    let listener = SystemLocalConn.listen(&path).unwrap();
    assert!(listener.is_current());

    // Outra instância toma o caminho logo em seguida: o mesmo nome, outro
    // arquivo (o "tunneling" do NTFS devolveria até a mesma hora de criação).
    std::fs::remove_file(&path).unwrap();
    let _outro = StdListener::bind(&path).unwrap();
    assert!(!listener.is_current());

    drop(listener);
    assert!(on_disk(&path), "o Drop apagou o socket de outra instância");
}

#[tokio::test(flavor = "multi_thread")]
async fn is_current_e_falso_quando_o_arquivo_some() {
    let dir = tempfile::tempdir().unwrap();
    let path = socket_in(&dir);
    let listener = SystemLocalConn.listen(&path).unwrap();

    std::fs::remove_file(&path).unwrap();

    assert!(!listener.is_current());
}

#[tokio::test(flavor = "multi_thread")]
async fn caminho_longo_demais_e_recusado() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("x".repeat(120));

    let result = SystemLocalConn.listen(&path);

    // O `sun_path` do Windows: 108 bytes com o terminador.
    assert!(matches!(
        result,
        Err(LocalConnError::PathTooLong { max: 107, .. })
    ));
}
