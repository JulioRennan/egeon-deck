//! Exemplos do tópico `app` (decisão 34) que vão para as fixtures do `/ui`.

use super::app::*;
use super::message::{Command, CommandKind, Event, EventBody, Topic};

pub fn commands() -> Vec<(&'static str, Command)> {
    let c = |id, kind| Command { id, kind };
    vec![
        (
            "subscribe_app",
            c(400, CommandKind::Subscribe { topic: Topic::App }),
        ),
        ("update_menu", c(401, CommandKind::UpdateMenu)),
        (
            "update_answer",
            c(
                402,
                CommandKind::UpdateAnswer(UpdateAnswer {
                    version: "1.7.0".into(),
                    accept: true,
                    auto: false,
                }),
            ),
        ),
        (
            "update_auto",
            c(403, CommandKind::UpdateAuto(UpdateAuto { on: true })),
        ),
        (
            "reaper_enabled",
            c(404, CommandKind::ReaperEnabled(ReaperEnabled { on: false })),
        ),
        (
            "open_url",
            c(
                450,
                CommandKind::OpenUrl(OpenUrl {
                    url: "https://example.com/docs".into(),
                }),
            ),
        ),
    ]
}

fn state(update: UpdateView, enabled: bool) -> Event {
    Event {
        topic: Topic::App,
        body: EventBody::App(AppState {
            update,
            reaper: ReaperView { enabled },
        }),
    }
}

fn effect(effect: AppEffect) -> Event {
    Event {
        topic: Topic::App,
        body: EventBody::AppEffect(effect),
    }
}

pub fn events() -> Vec<(&'static str, Event)> {
    vec![
        (
            "app_idle",
            state(
                UpdateView {
                    phase: UpdatePhase::Idle,
                    version: None,
                    menu: "Procurar atualizações…".into(),
                    menu_enabled: true,
                    auto: false,
                    installed: "1.6.0".into(),
                    staged: false,
                },
                true,
            ),
        ),
        (
            "app_update_ready",
            state(
                UpdateView {
                    phase: UpdatePhase::Ready,
                    version: Some("1.7.0".into()),
                    menu: "Reiniciar para atualizar para a versão 1.7.0".into(),
                    menu_enabled: true,
                    auto: true,
                    installed: "1.6.0".into(),
                    staged: true,
                },
                false,
            ),
        ),
        (
            "app_update_prompt",
            effect(AppEffect::UpdatePrompt {
                version: "1.7.0".into(),
                title: "Versão 1.7.0 do Egeon Deck disponível".into(),
                text: "novidades\n\nReiniciar encerra o que estiver rodando: 2 agentes abertos. \
                       As conversas são retomadas quando o app voltar.\n\nO app não tem \
                       assinatura da Apple. Ao atualizar, ele confere a assinatura própria da \
                       versão baixada e tira dela a quarentena do macOS."
                    .into(),
                auto: false,
                auto_label:
                    "Atualizar automaticamente: baixar sozinho e trocar quando eu fechar o app"
                        .into(),
                accept_label: "Atualizar e reiniciar".into(),
                later_label: "Depois".into(),
            }),
        ),
        (
            "app_update_message",
            effect(AppEffect::UpdateMessage {
                title: "Você está na última versão".into(),
                text: "Egeon Deck 1.6.0.".into(),
            }),
        ),
        ("app_terminate", effect(AppEffect::Terminate)),
        ("app_show_processes", effect(AppEffect::ShowProcesses)),
        ("app_activate", effect(AppEffect::Activate)),
    ]
}
