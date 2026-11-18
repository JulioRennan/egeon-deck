//! Mantém o consumo de cada bancada em dia: lê o que os transcripts dos agentes
//! ganharam, soma no `usage.json` e diz o que mudou.
//!
//! Quem chama (o ator) decide o relógio — a cada fim de turno e de tempos em
//! tempos, porque o custo anda enquanto o agente trabalha. A leitura é só do
//! que o arquivo cresceu: um `stat` quando nada mudou.

use std::collections::BTreeMap;
use std::fs;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

use super::ledger::{Cursor, UsageLedger};
use super::model::ModelPrice;
use super::prices::{PriceTable, file_overrides};
use super::trace::parse_conversations;
use crate::features::agent::claude::usage as claude_usage;
use crate::features::json_file::write_pretty;

/// Uma fonte de consumo: o nó e o transcript que o gancho relatou.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Source {
    pub node: String,
    pub transcript: PathBuf,
}

pub fn pricing_file(home: &Path) -> PathBuf {
    home.join("pricing.json")
}

fn usage_file(home: &Path, workbench: &str) -> PathBuf {
    home.join("workbenches").join(workbench).join("usage.json")
}

/// O arquivo nasce vazio — é o lugar das exceções. A cópia antiga da tabela
/// inteira, intocada, é trocada pelo vazio.
pub fn seed_pricing_file_if_missing(home: &Path) {
    let file = pricing_file(home);
    if let Ok(bytes) = fs::read(&file) {
        let seeded = crate::features::json_file::parse::<BTreeMap<String, ModelPrice>>(&bytes)
            .map(|custom| super::prices::is_seed_copy(&custom))
            .unwrap_or(false);
        if !seeded {
            return;
        }
    }
    let _ = fs::create_dir_all(home);
    let _ = crate::features::agent::claude::write_atomic(&file, b"{}\n");
}

/// As três camadas, com o `pricing.json` lido do disco. `catalog` é o que o
/// Claude Code instalado traz.
pub fn load_prices(home: &Path, catalog: &BTreeMap<String, ModelPrice>) -> PriceTable {
    let custom = fs::read(pricing_file(home))
        .ok()
        .and_then(|b| crate::features::json_file::parse::<BTreeMap<String, ModelPrice>>(&b).ok())
        .unwrap_or_default();
    PriceTable::layered(catalog, &file_overrides(custom))
}

#[derive(Debug)]
pub struct UsageStore {
    home: PathBuf,
    user_home: PathBuf,
    /// O que a tela lê.
    ledgers: BTreeMap<String, UsageLedger>,
    working: BTreeMap<String, UsageLedger>,
}

impl UsageStore {
    /// `home` é a pasta de dados do app; `user_home`, o HOME do usuário, onde
    /// ficam as pastas `.claude*` com os transcripts do passado.
    pub fn new(home: PathBuf, user_home: PathBuf) -> UsageStore {
        UsageStore {
            home,
            user_home,
            ledgers: BTreeMap::new(),
            working: BTreeMap::new(),
        }
    }

    /// A pasta de dados e o HOME do usuário com que foi aberto — para abrir outro
    /// igual se o que andava num job se perder.
    pub fn dirs(&self) -> (PathBuf, PathBuf) {
        (self.home.clone(), self.user_home.clone())
    }

    /// O que o `/usage` lê: o último registro publicado de cada bancada.
    pub fn ledgers(&self) -> &BTreeMap<String, UsageLedger> {
        &self.ledgers
    }

    pub fn ledger(&self, workbench: &str) -> UsageLedger {
        self.ledgers.get(workbench).cloned().unwrap_or_default()
    }

    /// Lê o que os transcripts ganharam, grava o que mudou e devolve as bancadas
    /// alteradas.
    pub fn refresh(
        &mut self,
        sources: &BTreeMap<String, Vec<Source>>,
        prices: &PriceTable,
    ) -> BTreeMap<String, UsageLedger> {
        let mut changed = BTreeMap::new();
        for (workbench, list) in sources {
            let mut ledger = match self.working.get(workbench) {
                Some(ledger) => ledger.clone(),
                None => self.load(workbench, list, prices),
            };
            let before = ledger.clone();
            ledger.settle(prices);
            for source in list {
                for file in claude_usage::files(&source.transcript) {
                    read(&file, &source.node, &mut ledger, prices);
                }
            }
            self.working.insert(workbench.clone(), ledger.clone());
            if ledger != before || !self.ledgers.contains_key(workbench) {
                self.save(&ledger, workbench);
                changed.insert(workbench.clone(), ledger);
            }
        }
        for (workbench, ledger) in &changed {
            self.ledgers.insert(workbench.clone(), ledger.clone());
        }
        changed
    }

    fn save(&self, ledger: &UsageLedger, workbench: &str) {
        let file = usage_file(&self.home, workbench);
        if let Err(error) = write_pretty(&file, ledger) {
            crate::log!("consumo: {error}");
        }
    }

    /// Do disco; na primeira vez, com o passado que a trilha deixa achar — as
    /// conversas de antes de cada `/clear`.
    fn load(&self, workbench: &str, sources: &[Source], prices: &PriceTable) -> UsageLedger {
        if let Ok(bytes) = fs::read(usage_file(&self.home, workbench))
            && let Ok(ledger) = crate::features::json_file::parse::<UsageLedger>(&bytes)
        {
            return ledger;
        }
        // O `settle` de `refresh` congela o que entrou sem preço — e o formato
        // de antes, que só tinha tokens.
        let mut ledger = UsageLedger::default();
        let current: Vec<&Path> = sources.iter().map(|s| s.transcript.as_path()).collect();
        for (node, transcript) in self.past_transcripts(workbench) {
            if current.contains(&transcript.as_path()) {
                continue;
            }
            for file in claude_usage::files(&transcript) {
                read(&file, &node, &mut ledger, prices);
            }
        }
        crate::log!(
            "consumo: bancada {workbench} começou o registro com {} transcript(s) do passado",
            ledger.cursors.len()
        );
        ledger
    }

    fn past_transcripts(&self, workbench: &str) -> Vec<(String, PathBuf)> {
        let folder = self.home.join("workbenches").join(workbench);
        let mut traces = vec![folder.join("trace.md")];
        if let Ok(entries) = fs::read_dir(folder.join("trace-archive")) {
            traces.extend(entries.flatten().map(|e| e.path()));
        }
        let stamps: Vec<(String, String)> = traces
            .iter()
            .filter_map(|p| fs::read_to_string(p).ok())
            .flat_map(|text| parse_conversations(&text))
            .collect();
        if stamps.is_empty() {
            return Vec::new();
        }
        let index = transcript_index(&self.user_home);
        stamps
            .into_iter()
            .filter_map(|(node, prefix)| {
                index
                    .get(&prefix.to_lowercase())
                    .map(|path| (node, path.clone()))
            })
            .collect()
    }
}

/// Lê o trecho novo de um transcript e soma no registro.
fn read(file: &Path, node: &str, ledger: &mut UsageLedger, prices: &PriceTable) {
    let path = file.to_string_lossy().into_owned();
    let Ok(size) = fs::metadata(file).map(|m| m.len()) else {
        return;
    };
    let offset = ledger.cursors.get(&path).map_or(0, |c| c.offset);
    // Encolheu: foi reescrito. Recomeçar contaria de novo o que já entrou.
    if size < offset {
        ledger.cursors.insert(
            path,
            Cursor {
                offset: size,
                last_id: None,
            },
        );
        return;
    }
    if size <= offset {
        return;
    }
    let Ok(mut handle) = fs::File::open(file) else {
        return;
    };
    if handle.seek(SeekFrom::Start(offset)).is_err() {
        return;
    }
    let mut data = Vec::new();
    if handle.read_to_end(&mut data).is_err() || data.is_empty() {
        return;
    }
    // Só o Claude Code grava consumo no transcript hoje; outro CLI entra pelo
    // leitor dele, quando existir.
    ledger.absorb_chunk(&data, &path, node, prices, claude_usage::entries);
}

/// Prefixo de 8 → transcript, em todos os `<home>/.claude*/projects/*/`.
fn transcript_index(user_home: &Path) -> BTreeMap<String, PathBuf> {
    let mut index = BTreeMap::new();
    let Ok(entries) = fs::read_dir(user_home) else {
        return index;
    };
    let mut configs: Vec<PathBuf> = entries
        .flatten()
        .filter(|e| e.file_name().to_string_lossy().starts_with(".claude"))
        .map(|e| e.path())
        .collect();
    configs.sort();
    for config in configs {
        let Ok(projects) = fs::read_dir(config.join("projects")) else {
            continue;
        };
        for project in projects.flatten() {
            let Ok(files) = fs::read_dir(project.path()) else {
                continue;
            };
            for file in files.flatten() {
                let path = file.path();
                if path.extension().and_then(|e| e.to_str()) != Some("jsonl") {
                    continue;
                }
                if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                    index.insert(
                        stem.chars().take(8).collect::<String>().to_lowercase(),
                        path,
                    );
                }
            }
        }
    }
    index
}
