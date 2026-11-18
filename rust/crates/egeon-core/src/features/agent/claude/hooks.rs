//! Faz o CLI do agente contar ao app o que acabou de acontecer no terminal.
//!
//! Três ganchos, e cada um responde uma pergunta que de fora não tem resposta:
//!
//! - `UserPromptSubmit` — qual conversa está aberta. Sem isso o app só conhece a
//!   que ele mesmo criou: um `/resume`, `/clear` ou fork feito pelo usuário na
//!   TUI é invisível, e o arranque seguinte retoma a conversa antiga (ADR-014).
//! - `Stop` — o turno acabou. É o instante exato, sem depender de o pty se calar
//!   nem de o modelo lembrar de escrever o marcador; e diz se ficou trabalho de
//!   fundo rodando, que é fato do CLI e não palavra do modelo (ADR-067).
//! - `Notification` — o CLI está pedindo permissão: o diálogo é desenhado pelo
//!   programa, não é mensagem do modelo (ADR-024).
//!
//! O `UserPromptSubmit` é a cada prompt de propósito, e não `SessionStart`: o app
//! se corrige sozinho no turno seguinte mesmo que uma transição escape.
//!
//! O gancho é o próprio `egeon hook <evento>` (decisão 15): um processo nativo no
//! lugar do `agent-hook.sh`, que fazia bash, curl e python3 a cada prompt. O
//! arquivo de settings é nosso e vai por `--settings`. Nada é escrito no
//! `~/.claude/settings.json` do usuário.

use std::fs;
use std::path::{Path, PathBuf};

use serde_json::{Value, json};

/// Variável de ambiente que diz ao gancho que ele está dentro do Egeon. Não é
/// identidade: quem fala vem do pid da conexão (ADR-040).
pub const TARGET_VARIABLE: &str = "EGEON_TARGET";
/// A pasta de dados do app: o `egeon` acha o socket por ela.
pub const HOME_VARIABLE: &str = "EGEON_HOME";
/// Qual cópia do app roda (estável ou dev).
pub const FLAVOR_VARIABLE: &str = "EGEON_FLAVOR";

/// As variáveis que o core põe no ambiente dos terminais filhos para o `egeon`
/// e os ganchos acharem o app.
pub const CHILD_ENVIRONMENT: [&str; 3] = [TARGET_VARIABLE, HOME_VARIABLE, FLAVOR_VARIABLE];

/// Quanto o gancho de permissão espera a resposta do chat. Esgotado, sai calado
/// e o diálogo do terminal segue sozinho — não é prazo para o usuário, é o teto
/// de um processo parado.
pub const PERMISSION_WAIT: u32 = 580;

pub fn settings_file(directory: &Path) -> PathBuf {
    directory.join("claude-hooks.json")
}

/// A linha de comando é interpretada por um shell e o caminho carrega o nome da
/// pasta do usuário: as aspas são o que faz o gancho sobreviver a um home com
/// espaço no nome.
fn command(egeon: &Path, event: &str) -> String {
    format!("\"{}\" hook {event}", egeon.display())
}

/// Só os ganchos. Nada de chave interna do CLI aqui dentro: o que este arquivo
/// quebrar, quebra todo terminal de agente de uma vez. Os eventos são os do
/// `egeon hook`: `start`, `prompt`, `stop`, `failure`, `permission` e `ask`.
pub fn settings_body(egeon: &Path) -> String {
    let hook = |event: &str, timeout: u32| json!([{ "type": "command", "command": command(egeon, event), "timeout": timeout }]);
    let plain = |event: &str| json!([{ "hooks": hook(event, 5) }]);
    let value: Value = json!({
        "hooks": {
            "SessionStart": plain("start"),
            "UserPromptSubmit": plain("prompt"),
            "Stop": plain("stop"),
            "StopFailure": plain("failure"),
            "PermissionRequest": [{ "hooks": hook("permission", PERMISSION_WAIT + 20) }],
            "Notification": [{ "matcher": "permission_prompt", "hooks": hook("ask", 5) }],
        }
    });
    serde_json::to_string_pretty(&value).unwrap_or_default()
}

/// Escrito no arranque: é um arquivo feito para ser lido e ajustado, e para isso
/// precisa existir antes de alguém precisar dele. `egeon` é o caminho do binário
/// `egeon`. Devolve o erro de gravação, que o chamador registra.
pub fn install(directory: &Path, egeon: &Path) -> std::io::Result<()> {
    fs::create_dir_all(directory)?;
    // Nomes anteriores: o script de relato da conversa e o `agent-hook.sh` que o
    // `egeon hook` substituiu. Deixá-los no diretório é convidar a editar o
    // arquivo errado.
    for old in ["report-session.sh", "agent-hook.sh"] {
        let _ = fs::remove_file(directory.join(old));
    }
    super::write_atomic(&settings_file(directory), settings_body(egeon).as_bytes())
}
