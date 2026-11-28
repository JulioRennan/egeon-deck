//! O que fazer ao saber que há versão nova — depende de quem perguntou e da
//! opção do menu.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reason {
    Launch,
    Periodic,
    Manual,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    /// Nada novo, e ninguém perguntou.
    Nothing,
    /// Pediu pelo menu e já está na última: diz isso.
    SayUpToDate,
    /// Avisa e deixa você escolher.
    Prompt,
    /// Só o item do menu muda: aviso modal fica para quando o app abre.
    ShowInMenu,
    /// Baixa sem perguntar, e a troca fica para quando você fechar o app.
    DownloadQuietly,
}

pub struct UpdatePolicy;

impl UpdatePolicy {
    pub fn action(newer: bool, reason: Reason, auto: bool) -> Action {
        if !newer {
            return if reason == Reason::Manual {
                Action::SayUpToDate
            } else {
                Action::Nothing
            };
        }
        if reason == Reason::Manual {
            return Action::Prompt;
        }
        if auto {
            return Action::DownloadQuietly;
        }
        if reason == Reason::Launch {
            Action::Prompt
        } else {
            Action::ShowInMenu
        }
    }
}
