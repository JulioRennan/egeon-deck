//! Escuta local de verdade, sempre numa pasta temporária — nunca `~/.egeon`.

use std::os::unix::net::UnixListener as StdListener;
use std::path::PathBuf;

use egeon_core::ports::local_conn::{LocalConnDriver, LocalConnError, Probe};
use egeon_driver::SystemLocalConn;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixStream;

fn socket_in(dir: &tempfile::TempDir) -> PathBuf {
    dir.path().join("sock")
}

fn my_pid() -> Option<u32> {
    Some(std::process::id())
}

#[tokio::test]
async fn accept_devolve_o_pid_de_quem_conectou() {
    let dir = tempfile::tempdir().unwrap();
    let path = socket_in(&dir);
    let listener = SystemLocalConn.listen(&path).unwrap();

    let _client = UnixStream::connect(&path).await.unwrap();
    let conn = listener.accept().await.unwrap();

    assert_eq!(conn.peer_pid, my_pid());
}

#[tokio::test]
async fn conexao_aceita_le_e_escreve() {
    let dir = tempfile::tempdir().unwrap();
    let path = socket_in(&dir);
    let listener = SystemLocalConn.listen(&path).unwrap();

    let mut client = UnixStream::connect(&path).await.unwrap();
    let mut conn = listener.accept().await.unwrap();
    client.write_all(b"GET /targets").await.unwrap();
    let mut received = [0u8; 12];
    conn.stream.read_exact(&mut received).await.unwrap();
    conn.stream.write_all(b"ok").await.unwrap();
    let mut reply = [0u8; 2];
    client.read_exact(&mut reply).await.unwrap();

    assert_eq!(&received, b"GET /targets");
    assert_eq!(&reply, b"ok");
}

#[tokio::test]
async fn probe_enxerga_instancia_viva_e_ausente() {
    let dir = tempfile::tempdir().unwrap();
    let path = socket_in(&dir);
    assert_eq!(SystemLocalConn.probe(&path), Probe::Nobody);

    let listener = SystemLocalConn.listen(&path).unwrap();
    assert_eq!(SystemLocalConn.probe(&path), Probe::Alive { pid: my_pid() });

    drop(listener);
    assert_eq!(SystemLocalConn.probe(&path), Probe::Nobody);
    assert!(!path.exists(), "largar a escuta devia apagar o arquivo");
}

#[tokio::test]
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

#[tokio::test]
async fn arquivo_orfao_de_crash_e_substituido() {
    let dir = tempfile::tempdir().unwrap();
    let path = socket_in(&dir);
    // Um std::os::unix::net::UnixListener largado deixa o arquivo no disco.
    drop(StdListener::bind(&path).unwrap());
    assert!(path.exists());
    assert_eq!(SystemLocalConn.probe(&path), Probe::Nobody);

    let listener = SystemLocalConn.listen(&path).unwrap();
    let _client = UnixStream::connect(&path).await.unwrap();

    assert_eq!(listener.accept().await.unwrap().peer_pid, my_pid());
}

#[tokio::test]
async fn is_current_acompanha_o_inode_e_drop_nao_apaga_o_de_outro() {
    let dir = tempfile::tempdir().unwrap();
    let path = socket_in(&dir);
    let listener = SystemLocalConn.listen(&path).unwrap();
    assert!(listener.is_current());

    // Outra instância toma o caminho: o arquivo agora tem outro inode.
    std::fs::remove_file(&path).unwrap();
    let _outro = StdListener::bind(&path).unwrap();
    assert!(!listener.is_current());

    drop(listener);
    assert!(path.exists(), "o Drop apagou o socket de outra instância");
}

#[tokio::test]
async fn is_current_e_falso_quando_o_arquivo_some() {
    let dir = tempfile::tempdir().unwrap();
    let path = socket_in(&dir);
    let listener = SystemLocalConn.listen(&path).unwrap();

    std::fs::remove_file(&path).unwrap();

    assert!(!listener.is_current());
}

#[tokio::test]
async fn caminho_longo_demais_e_recusado() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("x".repeat(120));

    let result = SystemLocalConn.listen(&path);

    assert!(matches!(
        result,
        Err(LocalConnError::PathTooLong { max: 103, .. })
    ));
}
