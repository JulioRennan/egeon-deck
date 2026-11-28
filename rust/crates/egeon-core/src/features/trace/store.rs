//! O arquivo da trilha: `workbenches/<id>/trace.md`, e o arquivo morto.
//!
//! Um arquivo só, e não um por agente, porque o uso é auditar a bancada: ler de
//! cima a baixo quem fez o quê, em ordem, sem cruzar arquivos. A pasta é o `id`
//! da bancada e não o nome: nome se repete (apagou, recriou) e muda
//! (renomeou); a trilha segue a bancada, não o rótulo. Fora do repositório do
//! projeto porque a bancada abre worktrees, e um arquivo dentro delas
//! apareceria no `git status` de cada uma.
//!
//! Funções síncronas: o core as chama de `spawn_blocking`, com a trilha atrás
//! de um dono só.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::SystemTime;

use super::model::{TraceEntry, header};
use crate::features::chat::time::format_clock;

pub const CURRENT_NAME: &str = "trace.md";
pub const ARCHIVE_NAME: &str = "trace-archive";
const PREFIX: &str = "trace-";
const SUFFIX: &str = ".md";

/// O deslocamento de UTC (segundos a leste) NAQUELE instante. É por instante e
/// não um número só porque o fuso do Swift vale para cada data: com horário de
/// verão, a data de criação do arquivo morto, de meses atrás, pode ter outro
/// deslocamento que a de agora. Quem sabe é o sistema; o core recebe a função.
pub type OffsetAt = Arc<dyn Fn(SystemTime) -> i64 + Send + Sync>;

pub struct TraceLog {
    workbenches: PathBuf,
    offset: OffsetAt,
}

impl TraceLog {
    pub fn new(workbenches: PathBuf, offset: OffsetAt) -> Self {
        TraceLog {
            workbenches,
            offset,
        }
    }

    /// Um deslocamento só, para teste ou para quem não tem horário de verão.
    pub fn fixed(workbenches: PathBuf, utc_offset_secs: i64) -> Self {
        Self::new(workbenches, Arc::new(move |_| utc_offset_secs))
    }

    pub fn directory(&self, workbench_id: &str) -> PathBuf {
        self.workbenches.join(workbench_id)
    }

    pub fn file(&self, entry: &TraceEntry) -> PathBuf {
        self.current(&entry.workbench_id)
    }

    pub fn current(&self, workbench_id: &str) -> PathBuf {
        self.directory(workbench_id).join(CURRENT_NAME)
    }

    pub fn archive_directory(&self, workbench_id: &str) -> PathBuf {
        self.directory(workbench_id).join(ARCHIVE_NAME)
    }

    /// As trilhas arquivadas, da mais antiga para a mais nova.
    pub fn archived(&self, workbench_id: &str) -> Vec<PathBuf> {
        let dir = self.archive_directory(workbench_id);
        let mut names: Vec<String> = fs::read_dir(&dir)
            .into_iter()
            .flatten()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .filter(|n| Path::new(n).extension().is_some_and(|e| e == "md"))
            .collect();
        names.sort();
        names.into_iter().map(|n| dir.join(n)).collect()
    }

    /// "Limpar a bancada" leva a trilha junto com o chat: `trace.md` vai para
    /// `trace-archive/trace-<início>_<fim>.md` e a próxima entrada abre outro,
    /// com cabeçalho novo. O período sai das datas do próprio arquivo — nasce
    /// na primeira entrada e é tocado na última — porque o carimbo de cada
    /// registro só tem minuto. `None` se não há trilha: nada nasce vazio.
    pub fn archive(&self, workbench_id: &str, now: SystemTime) -> Option<PathBuf> {
        let file = self.current(workbench_id);
        let metadata = fs::metadata(&file).ok()?;
        let dir = self.archive_directory(workbench_id);
        let _ = fs::create_dir_all(&dir);
        let start = metadata.created().unwrap_or(now);
        let end = metadata.modified().unwrap_or(now);
        let stamp = format!(
            "{}_{}",
            format_clock(start, (self.offset)(start)),
            format_clock(end.max(start), (self.offset)(end.max(start)))
        );
        let mut target = dir.join(format!("{PREFIX}{stamp}{SUFFIX}"));
        // Mesmo período duas vezes: sufixo, não sobrescrita. `_` e não `-`
        // pelo mesmo motivo do chat — ordena depois de `.`.
        let mut n = 2;
        while target.exists() {
            target = dir.join(format!("{PREFIX}{stamp}_{n}{SUFFIX}"));
            n += 1;
        }
        if let Err(error) = fs::rename(&file, &target) {
            crate::log!(
                "trace[{workbench_id}]: não consegui arquivar {} — {error}",
                file.display()
            );
            return None;
        }
        Some(target)
    }

    /// Acrescenta a entrada, com o cabeçalho se o arquivo ainda não existe.
    pub fn record(&self, entry: &TraceEntry) {
        let path = self.file(entry);
        if let Some(dir) = path.parent() {
            let _ = fs::create_dir_all(dir);
        }
        let mut text = entry.markdown((self.offset)(entry.at));
        if !path.exists() {
            text = header(entry.workbench(), &entry.workbench_id) + &text;
        }
        let written = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .and_then(|mut file| file.write_all(text.as_bytes()));
        match written {
            Ok(()) => crate::log!("trace[{}]: registrado", entry.address),
            Err(_) => crate::log!(
                "trace[{}]: não consegui escrever {}",
                entry.address,
                path.display()
            ),
        }
    }
}
