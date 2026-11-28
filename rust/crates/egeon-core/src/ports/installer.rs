//! Interface da troca do app instalado, na atualização.
//!
//! Implementada por `egeon-driver`. O que varia por plataforma é o pacote
//! (bundle `.app` no macOS), a assinatura de código, a descompactação que a
//! preserva e o processo que troca o app depois que ele sai — o app não se
//! substitui estando de pé. A confiança no download (assinatura do zip,
//! identificador do app, versão mais nova) e o fluxo são do core.

use std::io;
use std::path::{Path, PathBuf};

use thiserror::Error;

/// O app que veio dentro do zip baixado.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnpackedApp {
    pub path: PathBuf,
    pub bundle_id: String,
    pub version: String,
}

#[derive(Debug, Error)]
pub enum InstallError {
    /// O download não é um app válido: não descompactou, ou não tem um só app.
    #[error("o download não é um app válido ({0})")]
    NotInstallable(String),
    /// A assinatura de código do app baixado está quebrada.
    #[error("a assinatura de código do app baixado está quebrada")]
    BadCodeSignature,
    /// Sem permissão para escrever ao lado do app instalado.
    #[error("sem permissão para escrever em {}", .0.display())]
    CannotWrite(PathBuf),
}

/// O que a troca precisa saber, passado ao processo que a faz.
#[derive(Debug, Clone, Copy)]
pub struct Swap<'a> {
    /// O app que vai sair: a troca espera por ele.
    pub app_pid: u32,
    /// O app novo, já ao lado do destino (mesmo volume: a troca é instantânea).
    pub staged: &'a Path,
    pub destination: &'a Path,
    /// Abrir o app de novo depois de trocar.
    pub reopen: bool,
    /// Onde o processo da troca escreve o que fez.
    pub log: &'a Path,
}

pub trait AppInstaller: Send + Sync {
    /// App rodando translocado, ou em pasta sem escrita, não tem como se
    /// trocar.
    fn can_install(&self, destination: &Path) -> bool;

    /// Descompacta `zip` em `into` preservando a assinatura de código, exige
    /// exatamente um app lá dentro e lê o identificador e a versão dele.
    /// `into` ainda não existe: quem cria é o driver.
    fn unpack(&self, zip: &Path, into: &Path) -> Result<UnpackedApp, InstallError>;

    /// Confere a assinatura de código do app e o copia para `staged`. Do
    /// temporário para o destino pode cruzar volume: a cópia é aqui, e a troca
    /// é que precisa ser no mesmo volume. Quem chama apaga o `staged` antigo.
    fn stage(&self, app: &UnpackedApp, staged: &Path) -> Result<(), InstallError>;

    /// Solta o processo que espera `swap.app_pid` sair e troca o app; volta
    /// sem esperar por ele. Se a segunda das duas trocas falhar, o app antigo
    /// volta.
    fn launch_swap(&self, swap: Swap<'_>) -> io::Result<()>;
}
