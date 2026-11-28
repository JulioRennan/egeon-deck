//! O histórico do chat de uma bancada em disco (ADR-037): a conversa corrente em
//! `workbenches/<id>/chat.jsonl`, uma linha por turno; as arquivadas em
//! `workbenches/<id>/chat-archive/chat-<início>_<fim>.jsonl`, nomeadas pelo
//! período que cobrem — do primeiro prompt à última resposta.
//!
//! JSON e não banco porque o que se guarda é o que o chat mostra — uns KB por
//! turno — e não o transcript do CLI. Só-append, legível com `jq`, editável à mão
//! como todo arquivo do `~/.egeon`.
//!
//! "Limpar a conversa" é arquivar: o `chat.jsonl` vai para `chat-archive/` e um
//! novo começa vazio. Nada é apagado, e a conversa do CLI dentro de cada agente
//! continua a mesma; o que muda é o que o chat monta na tela. A corrente fica na
//! raiz de propósito: é a que o usuário abre.
//!
//! Funções síncronas sobre `&mut self`: o core as chama de `spawn_blocking`, fora
//! do ator, com o histórico atrás de um dono só.

use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use super::model::ChatRecord;
use super::time::{Offset, format_clock, parse_clock};
use crate::features::json_file::canonical;

pub const CURRENT_NAME: &str = "chat.jsonl";
pub const ARCHIVE_NAME: &str = "chat-archive";
const PREFIX: &str = "chat-";
const SUFFIX: &str = ".jsonl";

pub struct ChatHistory {
    workbenches: PathBuf,
    /// Fuso (segundos a leste de UTC) do relógio do nome do arquivo arquivado: o
    /// Swift usa o do sistema, e o core não o lê por conta própria. É só um rótulo
    /// legível; o mesmo valor lê o período de volta.
    clock_offset: Offset,
    /// Chaves já gravadas na conversa corrente, por bancada. Carregado do arquivo
    /// no primeiro toque; zera ao arquivar.
    seen: BTreeMap<String, BTreeSet<String>>,
}

impl ChatHistory {
    pub fn new(workbenches: PathBuf, clock_offset: Offset) -> ChatHistory {
        ChatHistory {
            workbenches,
            clock_offset,
            seen: BTreeMap::new(),
        }
    }

    pub fn directory(&self, workbench: &str) -> PathBuf {
        self.workbenches.join(workbench)
    }

    /// A conversa corrente. Pode ainda não existir.
    pub fn current(&self, workbench: &str) -> PathBuf {
        self.directory(workbench).join(CURRENT_NAME)
    }

    pub fn archive_directory(&self, workbench: &str) -> PathBuf {
        self.directory(workbench).join(ARCHIVE_NAME)
    }

    /// As conversas arquivadas, da mais antiga à mais recente.
    pub fn archived(&self, workbench: &str) -> Vec<PathBuf> {
        let dir = self.archive_directory(workbench);
        let mut names: Vec<String> = fs::read_dir(&dir)
            .into_iter()
            .flatten()
            .flatten()
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .filter(|n| n.starts_with(PREFIX) && n.ends_with(SUFFIX))
            .collect();
        names.sort();
        names.into_iter().map(|n| dir.join(n)).collect()
    }

    /// O período de uma conversa arquivada — lido do nome, para listar sem abrir o
    /// arquivo.
    pub fn period_of_file(&self, file: &Path) -> Option<(SystemTime, SystemTime)> {
        let name = file.file_name()?.to_string_lossy().into_owned();
        let body = name.strip_prefix(PREFIX)?.strip_suffix(SUFFIX)?;
        let mut parts = body.split('_');
        let start = parse_clock(parts.next()?, self.clock_offset)?;
        let end = parse_clock(parts.next()?, self.clock_offset)?;
        Some((start, end))
    }

    /// Do primeiro prompt à última resposta. É a data da CONVERSA, não a da
    /// limpeza: quem procura "a vez que o revisor achou o bug" lembra de quando
    /// foi, não de quando limpou.
    pub fn period_of_records(records: &[ChatRecord]) -> Option<(SystemTime, SystemTime)> {
        let start = records.iter().map(|r| r.turn.prompt_at).min()?;
        let end = records
            .iter()
            .map(|r| r.turn.reply_at.unwrap_or(r.turn.prompt_at))
            .max()?;
        Some((start, end.max(start)))
    }

    pub fn append(&mut self, record: &ChatRecord, workbench: &str) {
        let url = self.current(workbench);
        if !self.seen.contains_key(workbench) {
            let keys = read(&url).iter().map(ChatRecord::key).collect();
            self.seen.insert(workbench.to_owned(), keys);
        }
        let key = record.key();
        if self
            .seen
            .get(workbench)
            .is_some_and(|keys| keys.contains(&key))
        {
            return;
        }
        let line = serde_json::to_value(record)
            .ok()
            .and_then(|v| serde_json::to_string(&canonical(v)).ok());
        let Some(line) = line else {
            crate::log!(
                "chat[{workbench}/{}]: turno não serializável, não gravado",
                record.node
            );
            return;
        };
        if let Some(keys) = self.seen.get_mut(workbench) {
            keys.insert(key);
        }
        if let Some(dir) = url.parent() {
            let _ = fs::create_dir_all(dir);
        }
        let written = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&url)
            .and_then(|mut file| file.write_all(format!("{line}\n").as_bytes()));
        match written {
            Ok(()) => crate::log!("chat[{workbench}/{}]: turno gravado", record.node),
            Err(error) => {
                crate::log!(
                    "chat[{workbench}/{}]: não gravei {} — {error}",
                    record.node,
                    url.display()
                );
            }
        }
    }

    /// Arquiva a conversa corrente e começa outra. Devolve para onde a antiga foi,
    /// ou `None` se não havia o que arquivar — conversa vazia não vira arquivo
    /// vazio na pasta.
    pub fn archive(&mut self, workbench: &str, now: SystemTime) -> Option<PathBuf> {
        let file = self.current(workbench);
        if is_empty(&file) {
            return None;
        }
        let dir = self.archive_directory(workbench);
        let _ = fs::create_dir_all(&dir);
        // Arquivo com linhas que não decodificam não fica sem data: vale o instante
        // da limpeza para as duas pontas.
        let (start, end) = Self::period_of_records(&read(&file)).unwrap_or((now, now));
        let stamp = format!(
            "{}_{}",
            format_clock(start, (self.clock_offset)(start)),
            format_clock(end, (self.clock_offset)(end))
        );
        let mut target = dir.join(format!("{PREFIX}{stamp}{SUFFIX}"));
        // Mesmo período duas vezes (conversa restaurada e limpa de novo): sufixo, em
        // vez de sobrescrever. `_` e não `-`: ordena depois de `.`.
        let mut n = 2;
        while target.exists() {
            target = dir.join(format!("{PREFIX}{stamp}_{n}{SUFFIX}"));
            n += 1;
        }
        if let Err(error) = fs::rename(&file, &target) {
            crate::log!(
                "chat[{workbench}]: não consegui arquivar {} — {error}",
                file.display()
            );
            return None;
        }
        self.seen.insert(workbench.to_owned(), BTreeSet::new());
        Some(target)
    }

    /// Os turnos de uma conversa; sem `file`, a corrente.
    pub fn load(&self, workbench: &str, file: Option<&Path>) -> Vec<ChatRecord> {
        match file {
            Some(file) => read(file),
            None => read(&self.current(workbench)),
        }
    }
}

/// Linha que não decodifica é pulada, não derruba a conversa: arquivo editado à
/// mão ou meia linha de um crash não podem apagar o resto.
pub fn read(url: &Path) -> Vec<ChatRecord> {
    let Ok(bytes) = fs::read(url) else {
        return Vec::new();
    };
    // Como `String(data:encoding:.utf8)`: um byte inválido derruba o arquivo todo.
    let Ok(text) = String::from_utf8(bytes) else {
        return Vec::new();
    };
    text.split('\n')
        .filter(|l| !l.is_empty())
        .filter_map(|line| crate::features::json_file::parse::<ChatRecord>(line.as_bytes()).ok())
        .collect()
}

fn is_empty(path: &Path) -> bool {
    fs::metadata(path).map_or(true, |m| m.len() == 0)
}
