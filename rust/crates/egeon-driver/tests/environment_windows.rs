//! O ambiente do filho no Windows (composto pelo core com os diretórios do
//! driver) a partir do ambiente real do processo. O par do `environment.rs`
//! do unix; um teste só, porque mexe em variável de ambiente.

#![cfg(windows)]
#![allow(clippy::unwrap_used)]

use std::path::PathBuf;
use std::time::Duration;

use egeon_core::features::terminal::environment::for_child;
use egeon_core::ports::pty::{PtyDriver, PtyEvent, PtySize, PtySpec};
use egeon_driver::SystemPty;

#[tokio::test]
async fn filho_nao_herda_claude_code_e_o_path_fica_com_a_chave_do_windows() {
    // SAFETY: único teste deste binário, nenhuma outra thread lê o ambiente agora.
    unsafe {
        std::env::set_var("CLAUDE_CODE_ENTRYPOINT", "cli");
        std::env::set_var("CLAUDECODE", "1");
        std::env::set_var("EGEON_NODE", "deck/outro");
        std::env::set_var("EGEON_TESTE_FICA", "sim");
    }
    let mut env = for_child(
        &SystemPty,
        &PathBuf::from(r"C:\egeon\bin"),
        &["EGEON_NODE".into()],
    );
    env.push(("CLAUDE_CODE_EFFORT_LEVEL".into(), "high".into()));
    // Uma chave de PATH só, sem caixa: duas deixariam ao acaso qual vale.
    let path_keys = env
        .iter()
        .filter(|(k, _)| k.eq_ignore_ascii_case("PATH"))
        .count();
    assert_eq!(path_keys, 1, "{env:?}");

    let root = std::env::var("SystemRoot").unwrap_or_else(|_| r"C:\Windows".into());
    let child = SystemPty
        .spawn(PtySpec {
            program: PathBuf::from(root).join("System32").join("cmd.exe"),
            args: vec!["/d".into(), "/c".into(), "set".into()],
            env,
            cwd: None,
            size: PtySize {
                cols: 200,
                rows: 50,
            },
        })
        .unwrap();
    let mut events = child.events;
    let mut output = String::new();
    while let Ok(Some(PtyEvent::Output(bytes))) =
        tokio::time::timeout(Duration::from_secs(30), events.recv()).await
    {
        output.push_str(&String::from_utf8_lossy(&bytes));
    }

    assert!(
        !output.contains("CLAUDE_CODE_ENTRYPOINT"),
        "saída: {output}"
    );
    assert!(!output.contains("CLAUDECODE="), "saída: {output}");
    assert!(!output.contains("EGEON_NODE"), "saída: {output}");
    assert!(
        output.contains("CLAUDE_CODE_EFFORT_LEVEL=high"),
        "saída: {output}"
    );
    assert!(output.contains("EGEON_TESTE_FICA=sim"), "saída: {output}");
    assert!(
        output.to_uppercase().contains(r"PATH=C:\EGEON\BIN;"),
        "saída: {output}"
    );
}
