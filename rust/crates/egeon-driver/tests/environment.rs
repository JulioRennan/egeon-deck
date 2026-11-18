//! O ambiente do filho (composto pelo core com os diretórios do driver) a partir
//! do ambiente real do processo. Fica num arquivo
//! só, com um teste só: mexer em variável de ambiente corre contra qualquer outra
//! thread que a leia.

use std::path::PathBuf;
use std::time::Duration;

use egeon_core::features::terminal::environment::for_child;
use egeon_core::ports::pty::{PtyDriver, PtyEvent, PtySize, PtySpec};
use egeon_driver::SystemPty;

#[tokio::test]
async fn filho_lancado_nao_enxerga_claude_code_nem_procedencia_herdada() {
    // SAFETY: único teste deste binário, nenhuma outra thread lê o ambiente agora.
    unsafe {
        std::env::set_var("CLAUDE_CODE_ENTRYPOINT", "cli");
        std::env::set_var("CLAUDECODE", "1");
        std::env::set_var("EGEON_NODE", "deck/outro");
        std::env::set_var("EGEON_TESTE_FICA", "sim");
    }
    // A composição é do core; o driver só diz os diretórios deste sistema.
    let mut env = for_child(
        &SystemPty,
        &PathBuf::from("/egeon/bin"),
        &["EGEON_NODE".into()],
    );
    // O do esforço é do core e entra de propósito, depois da limpeza.
    env.push(("CLAUDE_CODE_EFFORT_LEVEL".into(), "high".into()));

    let child = SystemPty
        .spawn(PtySpec {
            program: PathBuf::from("/usr/bin/env"),
            args: vec![],
            env,
            cwd: None,
            size: PtySize { cols: 80, rows: 24 },
        })
        .unwrap();
    let mut events = child.events;
    let mut output = String::new();
    while let Ok(Some(PtyEvent::Output(bytes))) =
        tokio::time::timeout(Duration::from_secs(10), events.recv()).await
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
    assert!(output.contains("PATH=/egeon/bin:"), "saída: {output}");
}
