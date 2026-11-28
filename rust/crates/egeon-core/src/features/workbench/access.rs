//! O app consegue LER a pasta da bancada? Porte do `FolderAccess`.
//!
//! `exists` responde sim para pasta que o macOS bloqueou: o bloqueio é da
//! privacidade (Documentos, Mesa, Transferências), e ele só aparece ao listar.
//! Sem esta conferência a bancada abria normal e o agente morria no arranque com
//! "possibly due to low max file descriptors" — a mensagem genérica do Claude
//! Code para o EPERM que ele não esperava.
//!
//! Ler a pasta é também o que faz o macOS perguntar quando ainda não há
//! decisão: conferir na criação traz o pedido de permissão para a hora em que
//! você escolheu a pasta, e não para o primeiro agente.

use std::io::ErrorKind;
use std::path::Path;

use crate::features::path_text;
use crate::ports::folder_access::FolderPermissions;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FolderAccess {
    Ok,
    Missing,
    /// Existe, mas o sistema não deixa ler. `folder` é a pasta protegida do
    /// macOS por cima dela, quando é uma delas.
    Denied {
        folder: Option<String>,
    },
}

/// As pastas protegidas, como o Ajustes as mostra: o nome no disco e o do
/// Ajustes.
const PROTECTED: [(&str, &str); 3] = [
    ("Documents", "Documentos"),
    ("Desktop", "Mesa"),
    ("Downloads", "Transferências"),
];

impl FolderAccess {
    /// Abre a pasta para listar: é o que o sistema bloqueia e o `exists` não vê.
    /// `PermissionDenied` cobre `EPERM` e `EACCES`; qualquer outro erro conta
    /// como ok, como no Swift.
    pub fn check(path: &str, home: &str) -> FolderAccess {
        match std::fs::read_dir(Path::new(path)) {
            Ok(_) => FolderAccess::Ok,
            Err(error) => match error.kind() {
                ErrorKind::NotFound | ErrorKind::NotADirectory => FolderAccess::Missing,
                ErrorKind::PermissionDenied => FolderAccess::Denied {
                    folder: Self::protected_folder(path, home),
                },
                _ => FolderAccess::Ok,
            },
        }
    }

    /// Confere e, se o macOS recusou uma pasta protegida, pede de novo.
    ///
    /// Recusa é permanente para o macOS: ele não pergunta outra vez sozinho. O
    /// `tccutil reset` da própria pasta, do próprio app — sem senha, medido —
    /// volta a decisão para "não perguntado", e a leitura seguinte faz o pedido
    /// aparecer. Bloqueia até você responder: chamar fora do ator.
    pub fn request(path: &str, home: &str, permissions: &dyn FolderPermissions) -> FolderAccess {
        let first = Self::check(path, home);
        let FolderAccess::Denied {
            folder: Some(folder),
        } = &first
        else {
            return first;
        };
        let Some(service) = Self::service(folder) else {
            return first;
        };
        if !permissions.reset(service) {
            return first;
        }
        Self::check(path, home)
    }

    /// O serviço do TCC de cada pasta protegida.
    pub fn service(folder: &str) -> Option<&'static str> {
        match folder {
            "Documentos" => Some("SystemPolicyDocumentsFolder"),
            "Mesa" => Some("SystemPolicyDesktopFolder"),
            "Transferências" => Some("SystemPolicyDownloadsFolder"),
            _ => None,
        }
    }

    /// O nome como o Ajustes mostra, para o aviso dizer o que ligar.
    pub fn protected_folder(path: &str, home: &str) -> Option<String> {
        let standardized = path_text::standardize(path);
        PROTECTED.iter().find_map(|(name, shown)| {
            let root = format!("{}/{name}", home.trim_end_matches('/'));
            (standardized == root || standardized.starts_with(&format!("{root}/")))
                .then(|| (*shown).to_owned())
        })
    }

    /// O aviso para quem abriu a bancada. `None` quando dá para ler.
    pub fn message(&self) -> Option<String> {
        let FolderAccess::Denied { folder } = self else {
            return None;
        };
        let place = folder
            .as_ref()
            .map_or_else(|| "esta pasta".to_owned(), |f| format!("a pasta {f}"));
        Some(format!(
            "Sem acesso a {place}: libere o Egeon Deck em Ajustes › Privacidade › Arquivos e Pastas."
        ))
    }
}
