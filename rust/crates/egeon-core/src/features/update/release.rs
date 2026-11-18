//! Uma versão publicada, lida da release do GitHub.

use serde_json::Value;

use super::version::AppVersion;

/// O identificador do app novo (decisão 17), que a conferência do download
/// exige igual ao do app instalado. Provisório até o corte.
pub const NEXT_BUNDLE_ID: &str = "dev.duckcoder.egeondeck.next";

/// Os nomes dos arquivos da release. Parâmetro, e não constante: o app novo
/// publica outros nomes que o Swift, para o zip de um não servir ao outro.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AssetNames {
    pub zip: String,
    pub signature: String,
}

impl AssetNames {
    pub fn new(zip: impl Into<String>, signature: impl Into<String>) -> Self {
        AssetNames {
            zip: zip.into(),
            signature: signature.into(),
        }
    }

    /// Os do app Swift, `EgeonDeck.zip` e `EgeonDeck.zip.sig`.
    pub fn legacy() -> Self {
        Self::new("EgeonDeck.zip", "EgeonDeck.zip.sig")
    }
}

impl Default for AssetNames {
    /// Provisório, à espera do Julio: o mesmo repositório, com
    /// `EgeonDeckNext.zip` e `EgeonDeckNext.zip.sig`.
    fn default() -> Self {
        Self::new("EgeonDeckNext.zip", "EgeonDeckNext.zip.sig")
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AvailableUpdate {
    pub version: String,
    pub notes: String,
    pub page: String,
    pub zip: String,
    /// `None` em release sem assinatura — que o app não instala.
    pub signature: Option<String>,
}

impl AvailableUpdate {
    /// `None` quando o JSON não é uma release com o zip de nome fixo.
    pub fn parse(release: &[u8], names: &AssetNames) -> Option<AvailableUpdate> {
        let json: Value = serde_json::from_slice(release).ok()?;
        let tag = json.get("tag_name")?.as_str()?;
        AppVersion::parse(tag)?;
        let page = url(json.get("html_url")?.as_str()?)?;
        let assets = json.get("assets")?.as_array()?;
        let asset = |name: &str| -> Option<String> {
            assets
                .iter()
                .find(|a| a.get("name").and_then(Value::as_str) == Some(name))
                .and_then(|a| a.get("browser_download_url")?.as_str())
                .and_then(url)
        };
        let zip = asset(&names.zip)?;
        Some(AvailableUpdate {
            version: tag.strip_prefix('v').unwrap_or(tag).to_owned(),
            notes: json
                .get("body")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned(),
            page,
            zip,
            signature: asset(&names.signature),
        })
    }

    pub fn is_newer(&self, installed: &str) -> bool {
        match (
            AppVersion::parse(installed),
            AppVersion::parse(&self.version),
        ) {
            (Some(mine), Some(theirs)) => theirs > mine,
            _ => false,
        }
    }

    /// O último pedaço do caminho do zip, sem a query.
    pub fn zip_file_name(&self) -> &str {
        let path = self.zip.split(['?', '#']).next().unwrap_or(&self.zip);
        path.rsplit('/').next().unwrap_or(path)
    }
}

/// O que o `URL(string:)` do Swift aceitava: texto sem espaço nem controle.
fn url(text: &str) -> Option<String> {
    (!text.is_empty() && !text.chars().any(|c| c.is_whitespace() || c.is_control()))
        .then(|| text.to_owned())
}
