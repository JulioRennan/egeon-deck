//! Os pedidos de encerramento no Windows são eventos do console, e o evento
//! vai a todo processo ligado a ele — inclusive o `cargo` que roda o teste.
//! Aqui só se confere que o futuro nasce, dentro e fora do runtime, e espera.
//! Gerar o evento de verdade fica para o teste do `egeon-app` no CI.

#![cfg(windows)]

use std::time::Duration;

use egeon_driver::signals::shutdown;

#[tokio::test]
async fn sem_evento_o_encerramento_espera() {
    let pending = shutdown();
    assert!(
        tokio::time::timeout(Duration::from_millis(300), pending)
            .await
            .is_err()
    );

    let outside = std::thread::spawn(shutdown).join();
    let Ok(pending) = outside else {
        unreachable!("shutdown() entrou em pânico fora do runtime");
    };
    assert!(
        tokio::time::timeout(Duration::from_millis(300), pending)
            .await
            .is_err()
    );
}
