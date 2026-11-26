//! O run loop principal de verdade. Sem o harness do libtest: ele roda os testes
//! em threads próprias, e aqui a thread que chama `run` tem de ser a principal.

use std::process::ExitCode;
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use egeon_driver::main_loop::{MainLoopError, on_main, run};

#[cfg(target_os = "macos")]
fn main_thread() -> bool {
    // SAFETY: `pthread_main_np` não tem pré-condição.
    unsafe { libc::pthread_main_np() == 1 }
}

#[cfg(target_os = "linux")]
fn main_thread() -> bool {
    // SAFETY: `gettid` e `getpid` não têm pré-condição.
    unsafe { libc::gettid() == libc::getpid() }
}

fn check(name: &str, ok: bool, failures: &mut Vec<String>) {
    if !ok {
        failures.push(name.to_string());
    }
}

fn main() -> ExitCode {
    let mut failures = Vec::new();
    let main_id = thread::current().id();

    // Fora da principal não gira.
    let outside = thread::spawn(|| {
        run(|| ())
            .err()
            .map(|e| matches!(e, MainLoopError::NotMainThread))
    })
    .join()
    .ok()
    .flatten();
    check(
        "fora da principal é recusado",
        outside == Some(true),
        &mut failures,
    );

    // O core roda noutra thread e devolve o que calculou.
    let result = run(move || (thread::current().id() != main_id, 42));
    check(
        "core roda fora da principal e devolve o valor",
        matches!(result, Ok((true, 42))),
        &mut failures,
    );

    // Trabalho despachado para a principal roda lá, enquanto o loop gira.
    let result = run(|| {
        let (tx, rx) = mpsc::channel();
        on_main(move || {
            let _ = tx.send(main_thread());
        });
        rx.recv_timeout(Duration::from_secs(5)).ok()
    });
    check(
        "on_main roda na principal",
        matches!(result, Ok(Some(true))),
        &mut failures,
    );

    // `core` que acaba antes de o loop começar não prende a principal.
    let started = Instant::now();
    let result = run(|| ());
    check(
        "core instantâneo volta logo",
        result.is_ok() && started.elapsed() < Duration::from_secs(3),
        &mut failures,
    );

    // `core` que cai em pânico vira erro, e o loop para.
    let result = run(|| -> () { std::panic::resume_unwind(Box::new("core caiu")) });
    check(
        "pânico do core vira erro",
        matches!(result, Err(MainLoopError::CorePanicked)),
        &mut failures,
    );

    check(
        "a thread de teste é a principal",
        main_thread(),
        &mut failures,
    );

    if failures.is_empty() {
        ExitCode::SUCCESS
    } else {
        // O harness desligado não imprime nada: sem isto a falha não diria qual.
        for failure in &failures {
            let _ = std::io::Write::write_all(
                &mut std::io::stderr(),
                format!("FALHOU: {failure}\n").as_bytes(),
            );
        }
        ExitCode::FAILURE
    }
}
