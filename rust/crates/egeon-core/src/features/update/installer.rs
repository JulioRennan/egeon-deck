//! Do zip baixado ao bundle pronto ao lado do app, e daí à troca.
//!
//! A confiança no download é toda daqui — assinatura do zip, identificador do
//! app, versão mais nova. O que muda por sistema (descompactar preservando a
//! assinatura de código, conferi-la, copiar, trocar o app depois que ele sai)
//! é do [`AppInstaller`] do driver.

use std::io;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use super::signature;
use super::version::AppVersion;
use crate::ports::installer::{AppInstaller, InstallError, Swap};

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum Failure {
    #[error("a assinatura do download não confere")]
    BadSignature,
    #[error("o download não é um app válido ({0})")]
    NotInstallable(String),
    #[error("o download é de outro app ({0})")]
    WrongApp(String),
    #[error("o download traz a versão {0}, que não é mais nova")]
    NotNewer(String),
    #[error("a assinatura de código do app baixado está quebrada")]
    BadCodeSignature,
    #[error("sem permissão para escrever em {0}")]
    CannotWrite(String),
}

pub struct UpdateInstaller {
    /// O app instalado — o que está rodando.
    destination: PathBuf,
    bundle_id: String,
    installed_version: String,
    public_key: String,
    /// Onde o download é descompactado enquanto se confere. Apagado ao fim.
    work_root: PathBuf,
    platform: Arc<dyn AppInstaller>,
}

impl UpdateInstaller {
    pub fn new(
        destination: PathBuf,
        bundle_id: impl Into<String>,
        installed_version: impl Into<String>,
        work_root: PathBuf,
        platform: Arc<dyn AppInstaller>,
    ) -> Self {
        UpdateInstaller {
            destination,
            bundle_id: bundle_id.into(),
            installed_version: installed_version.into(),
            public_key: signature::PUBLIC_KEY.to_owned(),
            work_root,
            platform,
        }
    }

    /// Outra chave, para o teste assinar com uma que ele tenha.
    pub fn with_public_key(mut self, public_key: impl Into<String>) -> Self {
        self.public_key = public_key.into();
        self
    }

    pub fn destination(&self) -> &Path {
        &self.destination
    }

    /// Ao lado do destino: no mesmo volume o `mv` é instantâneo. Sem `.app` no
    /// nome de propósito, para não virar uma segunda cópia que o Spotlight
    /// abre.
    pub fn staged(&self) -> PathBuf {
        let mut path = self.destination.clone().into_os_string();
        path.push(".novo");
        PathBuf::from(path)
    }

    /// App rodando translocado, ou em pasta sem escrita, não tem como se
    /// trocar.
    pub fn can_install(&self) -> bool {
        self.platform.can_install(&self.destination)
    }

    pub fn is_staged(&self) -> bool {
        self.staged().exists()
    }

    pub fn discard_staged(&self) {
        let staged = self.staged();
        let _ = std::fs::remove_dir_all(&staged).or_else(|_| std::fs::remove_file(&staged));
    }

    /// Confere tudo e deixa o bundle em `staged`. Devolve a versão preparada.
    pub fn prepare(&self, zip: &[u8], signature_b64: &str) -> Result<String, Failure> {
        if !signature::is_valid(zip, signature_b64, &self.public_key) {
            return Err(Failure::BadSignature);
        }
        let work = self
            .work_root
            .join(format!("egeon-update-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&work)
            .map_err(|_| Failure::NotInstallable("sem pasta de trabalho".into()))?;
        let prepared = self.stage_from(zip, &work);
        let _ = std::fs::remove_dir_all(&work);
        prepared
    }

    fn stage_from(&self, zip: &[u8], work: &Path) -> Result<String, Failure> {
        let archive = work.join("update.zip");
        std::fs::write(&archive, zip)
            .map_err(|_| Failure::NotInstallable("sem pasta de trabalho".into()))?;
        let app = self
            .platform
            .unpack(&archive, &work.join("x"))
            .map_err(|e| self.failure(e))?;
        if app.bundle_id != self.bundle_id {
            return Err(Failure::WrongApp(app.bundle_id));
        }
        // A assinatura vale para qualquer zip já publicado: sem esta conta,
        // servir uma versão antiga e com falha passaria como atualização.
        match (
            AppVersion::parse(&self.installed_version),
            AppVersion::parse(&app.version),
        ) {
            (Some(mine), Some(theirs)) if theirs > mine => {}
            _ => return Err(Failure::NotNewer(app.version)),
        }
        // A interface manda quem chama apagar o antigo antes de `stage`.
        self.discard_staged();
        self.platform
            .stage(&app, &self.staged())
            .map_err(|e| self.failure(e))?;
        Ok(app.version)
    }

    fn failure(&self, error: InstallError) -> Failure {
        match error {
            InstallError::NotInstallable(why) => Failure::NotInstallable(why),
            InstallError::BadCodeSignature => Failure::BadCodeSignature,
            InstallError::CannotWrite(_) => Failure::CannotWrite(
                self.destination
                    .parent()
                    .map(|p| p.display().to_string())
                    .unwrap_or_default(),
            ),
        }
    }

    /// Solta o processo da troca e volta: ele espera `app_pid` sair para trocar.
    pub fn launch_swap(&self, app_pid: u32, reopen: bool, log: &Path) -> io::Result<()> {
        let staged = self.staged();
        self.platform.launch_swap(Swap {
            app_pid,
            staged: &staged,
            destination: &self.destination,
            reopen,
            log,
        })
    }
}
