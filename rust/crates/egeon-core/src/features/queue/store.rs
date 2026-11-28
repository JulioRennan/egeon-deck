//! O disco de uma fila: `workbenches/<bancada>/queues/<nó>/queue.json`, com as
//! imagens ao lado. Na pasta da bancada porque é dela, como o chat e a trilha
//! (ADR-036); por nó porque cada fila é um card.
//!
//! Funções síncronas: o core as chama de `spawn_blocking`.

use std::fs;
use std::path::{Path, PathBuf};

use super::model::PromptQueue;
use crate::features::json_file::{parse, read_bytes, write_pretty};

pub const FILE: &str = "queue.json";

/// As extensões que contam como imagem ao colar ou arrastar arquivos.
pub const IMAGE_EXTENSIONS: [&str; 8] =
    ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"];

/// Arquivo que conta como imagem pela extensão (sem caixa): sem extensão, ou
/// com outra, não é — o Swift o deixava de fora ao colar ou arrastar.
pub fn is_image_file(path: &Path) -> bool {
    path.extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .is_some_and(|e| IMAGE_EXTENSIONS.contains(&e.as_str()))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QueueStore {
    folder: PathBuf,
}

impl QueueStore {
    pub fn new(folder: PathBuf) -> Self {
        QueueStore { folder }
    }

    pub fn for_node(workbenches: &Path, workbench_id: &str, node_id: &str) -> Self {
        Self::new(workbenches.join(workbench_id).join("queues").join(node_id))
    }

    pub fn folder(&self) -> &Path {
        &self.folder
    }

    fn file(&self) -> PathBuf {
        self.folder.join(FILE)
    }

    /// Arquivo ausente ou ilegível é fila vazia, como no Swift.
    pub fn load(&self) -> PromptQueue {
        read_bytes(&self.file())
            .and_then(|bytes| parse(&bytes).ok())
            .unwrap_or_default()
    }

    pub fn save(&self, queue: &PromptQueue) {
        if let Err(error) = write_pretty(&self.file(), queue) {
            crate::log!("fila: não gravei {} — {error}", self.file().display());
        }
    }

    /// O caminho de uma imagem da fila.
    pub fn url_of(&self, image: &str) -> PathBuf {
        self.folder.join(image)
    }

    /// Grava o PNG e devolve o nome dele na pasta.
    pub fn save_image(&self, png: &[u8]) -> Option<String> {
        let name = format!("{}.png", image_stem());
        let written = fs::create_dir_all(&self.folder).and_then(|()| self.write_atomic(&name, png));
        match written {
            Ok(()) => Some(name),
            Err(error) => {
                crate::log!("fila: não gravei a imagem — {error}");
                None
            }
        }
    }

    /// Arquivo temporário e `rename`, como o `.atomic` do Swift: quem lê no
    /// meio da gravação, ou o app morto no meio dela, nunca vê meia imagem.
    fn write_atomic(&self, name: &str, bytes: &[u8]) -> std::io::Result<()> {
        let tmp = self.folder.join(format!(".{name}.tmp"));
        let renamed = fs::write(&tmp, bytes).and_then(|()| fs::rename(&tmp, self.url_of(name)));
        if renamed.is_err() {
            let _ = fs::remove_file(&tmp);
        }
        renamed
    }

    /// Copia para dentro da pasta: o arquivo arrastado pode sumir (print na
    /// mesa, download temporário) antes de o item ser enviado.
    pub fn import_image(&self, source: &Path) -> Option<String> {
        let ext = source
            .extension()
            .map(|e| e.to_string_lossy().to_lowercase())
            .filter(|e| !e.is_empty())
            .unwrap_or_else(|| "png".to_owned());
        let name = format!("{}.{ext}", image_stem());
        let copied =
            fs::create_dir_all(&self.folder).and_then(|()| fs::copy(source, self.url_of(&name)));
        match copied {
            Ok(_) => Some(name),
            Err(error) => {
                crate::log!("fila: não copiei {} — {error}", source.display());
                None
            }
        }
    }

    pub fn remove_images(&self, images: &[String]) {
        for name in images {
            let _ = fs::remove_file(self.url_of(name));
        }
    }

    pub fn remove_all(&self) {
        let _ = fs::remove_dir_all(&self.folder);
    }
}

/// `img-` e os 8 primeiros dígitos de um UUID, em minúsculas.
fn image_stem() -> String {
    let id = uuid::Uuid::new_v4().simple().to_string();
    format!("img-{}", &id[..8])
}
