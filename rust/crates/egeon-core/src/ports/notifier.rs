//! Interface da notificação do sistema e do som de atenção.
//!
//! Implementada por `egeon-driver`. O que varia por plataforma é a central de
//! notificações (e a autorização que ela pede), o clique no aviso e o catálogo
//! de sons. Quando avisar, o texto e o intervalo mínimo entre dois sons são do
//! core: a interface só entrega o aviso e toca.
//!
//! O core decide se a UI está na frente (olhando para ela, a borda e o som já
//! dizem tudo): aqui `post` sempre tenta avisar.

use thiserror::Error;
use tokio::sync::mpsc;

/// Um aviso para a central de notificações.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Notice {
    /// Um por terminal: aviso novo com o mesmo identificador substitui o
    /// anterior em vez de empilhar.
    pub identifier: String,
    pub title: String,
    pub body: String,
    pub workbench: String,
    pub node: String,
}

/// O aviso clicado: o terminal para onde trazer o usuário.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoticeClick {
    pub workbench: String,
    pub node: String,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum SoundError {
    /// O sistema não tem som com esse nome.
    #[error("som \"{0}\" não existe")]
    Unknown(String),
}

pub trait Notifier: Send + Sync {
    /// Pede autorização à central e passa a entregar os cliques. Uma vez, na
    /// partida. Sem central (o executável não está num app empacotado) a
    /// interface não avisa nada e o canal não recebe nada.
    fn start(&self) -> mpsc::Receiver<NoticeClick>;

    /// Vai sair notificação com som: o core cala o som de atenção para não
    /// tocar o aviso em dobro. Falso até a autorização chegar.
    fn authorized(&self) -> bool;

    /// Não bloqueia. Falha (sem autorização, central recusou) vai para o log do
    /// driver: um aviso perdido não pode derrubar o terminal que o gerou.
    fn post(&self, notice: Notice);

    /// O terminal foi visto ou voltou a trabalhar: o aviso dele não vale mais.
    fn withdraw(&self, identifier: &str);

    /// Toca um som do sistema (ou do usuário) pelo nome, com `volume` de 0 a 1
    /// sobre o volume de alerta. Tocar de novo um som que já toca reinicia do
    /// zero. Nome vazio ou volume zero não tocam e não são erro.
    fn play_sound(&self, name: &str, volume: f64) -> Result<(), SoundError>;
}
