//! O tópico `app` do canal `/ui` (decisão 34): o estado da atualização e da
//! limpeza de órfãos, e os efeitos que o core pede à UI — o aviso de versão
//! nova, a mensagem, encerrar o app e abrir a janela "Processos".
//!
//! O core manda o resultado pronto (decisão 33.3): título, texto e rótulos do
//! aviso saem daqui, e a UI só os desenha e devolve o gesto.

use serde::{Deserialize, Serialize};

/// Em que pé está a atualização.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum UpdatePhase {
    Idle,
    Checking,
    Available,
    Downloading,
    Ready,
}

/// O item de menu "Procurar atualizações…" e o que há por trás dele.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UpdateView {
    #[serde(rename = "state")]
    pub phase: UpdatePhase,
    /// A versão disponível, baixando ou pronta.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
    /// O título do item de menu, já escolhido pelo estado.
    pub menu: String,
    pub menu_enabled: bool,
    /// "Atualizar automaticamente" ligado.
    pub auto: bool,
    pub installed: String,
    /// Há um app novo esperando ao lado do instalado.
    pub staged: bool,
}

/// A limpeza automática de órfãos (ADR-083), do menu.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReaperView {
    pub enabled: bool,
}

/// O estado inteiro do tópico: vai na assinatura e a cada mudança.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppState {
    pub update: UpdateView,
    pub reaper: ReaperView,
}

/// `{"effect":…}` no tópico `app`. Efeito é aviso de uma vez só: quem assina
/// depois não o recebe.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "effect", rename_all = "snake_case")]
pub enum AppEffect {
    /// O aviso de versão nova (a folha do `UpdatePrompt` do Swift). A UI
    /// responde com `update_answer`.
    UpdatePrompt {
        version: String,
        title: String,
        text: String,
        /// Como a caixa "atualizar automaticamente" começa.
        auto: bool,
        auto_label: String,
        accept_label: String,
        later_label: String,
    },
    /// Uma mensagem de uma linha e um texto (consulta que falhou, "você está
    /// na última versão").
    UpdateMessage { title: String, text: String },
    /// A troca está agendada: a UI encerra o app.
    Terminate,
    /// O `show=1` do `/processes`: abre a janela "Processos".
    ShowProcesses,
    /// Trazer a janela para a frente: o `NSApp.activate` do clique numa
    /// notificação (a bancada e o foco do chat já vêm nos tópicos deles).
    Activate,
    /// Decisão 35: uma rota de tela do Swift (`/layout`, `/sidebar`,
    /// `/geometry`, `/shot`) que o `egeon` ou um teste chamou. A UI faz e
    /// responde com `ui_reply{request: id, status, body}`.
    UiRequest {
        id: u64,
        route: String,
        params: std::collections::BTreeMap<String, String>,
    },
}

// ---- Comandos ----

/// A resposta ao aviso: atualizar e reiniciar, ou depois — e a caixa de
/// atualizar sozinho como ficou.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UpdateAnswer {
    /// A versão do aviso que está sendo respondido.
    pub version: String,
    pub accept: bool,
    pub auto: bool,
}

/// O item de menu "Atualizar automaticamente".
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UpdateAuto {
    pub on: bool,
}

/// O item de menu "Limpar órfãos automaticamente".
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReaperEnabled {
    pub on: bool,
}

/// Abre um link no navegador do sistema, como o `NSWorkspace.open` do Swift
/// no clique do link da resposta do chat. Recusa se o sistema não abrir.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OpenUrl {
    pub url: String,
}
