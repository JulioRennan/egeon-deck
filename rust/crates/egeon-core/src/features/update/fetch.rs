//! A rede da atualização: consultar a release e baixar o zip e a assinatura.
//!
//! É o executor dos [`Effect`]s `FetchRelease` e `Download` do
//! [`UpdateController`]: o core o chama de uma tarefa fora do ator e devolve a
//! [`Completion`] ao controller. Só o que mexe na rede mora aqui; o que decide
//! é do controller.

use std::sync::Arc;
use std::time::Duration;

use super::controller::{Effect, FetchOutcome, UpdateController};
use super::installer::{Failure, UpdateInstaller};
use super::policy::Reason;
use super::release::AvailableUpdate;

/// Sem resposta por este tempo a conexão cai. O zip é grande, então o prazo é
/// de silêncio e não da transferência inteira.
const READ_TIMEOUT: Duration = Duration::from_secs(60);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(15);

/// Tetos de tamanho, bem acima do real: a release é um JSON de poucos KB, a
/// assinatura tem 88 caracteres e o zip do app, algumas dezenas de MB. O
/// Swift não tinha teto; aqui um servidor que não para de mandar não enche a
/// memória.
const MAX_RELEASE: u64 = 4 << 20;
const MAX_SIGNATURE: u64 = 64 << 10;
const MAX_ZIP: u64 = 1 << 30;

pub struct UpdateClient {
    client: reqwest::Client,
    max_release: u64,
    max_signature: u64,
    max_zip: u64,
}

/// O que um [`Effect`] de rede terminou de fazer, para devolver ao controller.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Completion {
    Fetched {
        reason: Reason,
        outcome: FetchOutcome,
    },
    Prepared {
        update: AvailableUpdate,
        outcome: Result<String, Failure>,
    },
}

impl Completion {
    /// Entrega o resultado ao controller e devolve o que ele pede a seguir.
    pub fn apply(self, controller: &mut UpdateController) -> Vec<Effect> {
        match self {
            Completion::Fetched { reason, outcome } => controller.release_fetched(reason, outcome),
            Completion::Prepared { update, outcome } => controller.prepared(update, outcome),
        }
    }
}

impl UpdateClient {
    /// `User-Agent: EgeonDeck/<versão instalada>`, como o Swift: a API do
    /// GitHub recusa quem não se identifica.
    ///
    /// Só HTTPS, como o app Swift, que vivia sob a ATS: o zip tem a assinatura
    /// para protegê-lo, mas o JSON da release (versão, notas, endereços) não.
    /// `allow_http` existe para o dev testar a rota `/update?feed=` com uma
    /// release falsa em `http://localhost`; o estável passa `false`.
    pub fn new(installed_version: &str, allow_http: bool) -> Result<Self, reqwest::Error> {
        let client = reqwest::Client::builder()
            .user_agent(format!("EgeonDeck/{installed_version}"))
            .connect_timeout(CONNECT_TIMEOUT)
            .read_timeout(READ_TIMEOUT)
            .https_only(!allow_http)
            .build()?;
        Ok(UpdateClient {
            client,
            max_release: MAX_RELEASE,
            max_signature: MAX_SIGNATURE,
            max_zip: MAX_ZIP,
        })
    }

    /// Outros tetos, para o teste não precisar de um gigabyte.
    pub fn with_limits(mut self, release: u64, signature: u64, zip: u64) -> Self {
        self.max_release = release;
        self.max_signature = signature;
        self.max_zip = zip;
        self
    }

    /// Executa um efeito de rede; os outros (aviso, mensagem, encerrar) são da
    /// tela e voltam como `None`.
    pub async fn execute(
        &self,
        effect: Effect,
        installer: Arc<UpdateInstaller>,
    ) -> Option<Completion> {
        match effect {
            Effect::FetchRelease { reason, feed } => Some(Completion::Fetched {
                reason,
                outcome: self.fetch_release(&feed).await,
            }),
            Effect::Download(update) => {
                let outcome = self.download(&update, installer).await;
                Some(Completion::Prepared { update, outcome })
            }
            Effect::Prompt(_) | Effect::Message { .. } | Effect::Terminate => None,
        }
    }

    pub async fn fetch_release(&self, feed: &str) -> FetchOutcome {
        match self.get(feed, self.max_release).await {
            Ok(body) => FetchOutcome::Body(body),
            Err(why) => FetchOutcome::Failed(why),
        }
    }

    /// Baixa a assinatura e o zip e roda o `prepare` fora do ator. Qualquer
    /// falha de rede é "o download falhou", como no Swift.
    pub async fn download(
        &self,
        update: &AvailableUpdate,
        installer: Arc<UpdateInstaller>,
    ) -> Result<String, Failure> {
        let failed = |why: String| {
            crate::log!("atualização: download falhou — {why}");
            Failure::NotInstallable("o download falhou".into())
        };
        let Some(signature_url) = &update.signature else {
            return Err(failed("release sem assinatura".into()));
        };
        let signature = self
            .get(signature_url, self.max_signature)
            .await
            .map_err(failed)?;
        let zip = self.get(&update.zip, self.max_zip).await.map_err(failed)?;
        let signature = String::from_utf8_lossy(&signature).into_owned();
        // A conferência lê e escreve em disco: fora dos executores assíncronos.
        tokio::task::spawn_blocking(move || installer.prepare(&zip, &signature))
            .await
            .unwrap_or_else(|_| {
                Err(Failure::NotInstallable(
                    "a conferência foi interrompida".into(),
                ))
            })
    }

    /// `GET` que só aceita 200 (os redirecionamentos o `reqwest` já segue: o
    /// zip do GitHub mora noutro endereço) e corpo de até `limit` bytes.
    async fn get(&self, url: &str, limit: u64) -> Result<Vec<u8>, String> {
        let mut response = self
            .client
            .get(url)
            .send()
            .await
            .map_err(|e| e.to_string())?;
        if response.status() != reqwest::StatusCode::OK {
            return Err(format!("resposta {}", response.status().as_u16()));
        }
        let too_big = || format!("resposta maior que {limit} bytes");
        if response.content_length().is_some_and(|len| len > limit) {
            return Err(too_big());
        }
        // Lido aos pedaços: sem `Content-Length` (ou mentindo) o teto vale do
        // mesmo jeito.
        let mut body = Vec::new();
        while let Some(chunk) = response.chunk().await.map_err(|e| e.to_string())? {
            if body.len() as u64 + chunk.len() as u64 > limit {
                return Err(too_big());
            }
            body.extend_from_slice(&chunk);
        }
        Ok(body)
    }
}
