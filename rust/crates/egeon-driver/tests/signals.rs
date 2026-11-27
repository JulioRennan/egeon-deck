//! Sinais de verdade enviados ao próprio processo de teste. Um teste só: os
//! sinais são do processo inteiro e se cruzariam entre testes em paralelo.

#![cfg(unix)]

use std::time::Duration;

use egeon_driver::signals::shutdown;

async fn resolve_com(signal: libc::c_int) -> bool {
    // Registrado na chamada: o sinal abaixo já encontra o tratador instalado.
    let pending = shutdown();
    // SAFETY: `raise` só entrega o sinal à própria thread; há tratador instalado.
    assert_eq!(unsafe { libc::raise(signal) }, 0);
    tokio::time::timeout(Duration::from_secs(5), pending)
        .await
        .is_ok()
}

#[tokio::test]
async fn sigterm_sigint_e_sighup_encerram() {
    assert!(resolve_com(libc::SIGTERM).await, "SIGTERM não resolveu");
    assert!(resolve_com(libc::SIGINT).await, "SIGINT não resolveu");
    assert!(resolve_com(libc::SIGHUP).await, "SIGHUP não resolveu");
    criado_fora_do_runtime_registra_no_primeiro_poll()
        .await
        .unwrap();
}

/// Criado fora do runtime, o registro espera o primeiro `poll`. Roda dentro do
/// teste acima, em sequência: em paralelo os dois cruzariam os sinais.
async fn criado_fora_do_runtime_registra_no_primeiro_poll() -> Result<(), String> {
    let pending = std::thread::spawn(shutdown)
        .join()
        .map_err(|_| "shutdown() entrou em pânico fora do runtime".to_string())?;
    let task = tokio::spawn(pending);
    // Dá tempo de a tarefa ser sondada e registrar os tratadores.
    for _ in 0..10 {
        tokio::task::yield_now().await;
    }
    tokio::time::sleep(Duration::from_millis(100)).await;
    // SAFETY: `raise` só entrega o sinal; há tratador instalado.
    assert_eq!(unsafe { libc::raise(libc::SIGTERM) }, 0);

    let done = tokio::time::timeout(Duration::from_secs(5), task).await;
    if matches!(done, Ok(Ok(()))) {
        Ok(())
    } else {
        Err(format!("veio {done:?}"))
    }
}
