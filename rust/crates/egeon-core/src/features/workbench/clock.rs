//! Quanto tempo a bancada passou rodando, esperando você e em erro (ADR-074), e
//! os cronômetros de todas as bancadas guardados em `workbenches/<id>/clock.json`.
//! Porte do `WorkbenchClock` e do `WorkbenchClocks`.
//!
//! Cada fase conta um segundo por segundo enquanto houver pelo menos um
//! terminal nela — com cinco agentes trabalhando juntos, um segundo, não cinco.
//! As fases andam juntas: um agente perguntando algo não para o relógio de quem
//! segue trabalhando ao lado (ADR-078). Parada sem pendência (todos
//! terminaram, ou nem subiram) não conta em nenhuma.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use serde::de::Error as _;
use serde::{Deserialize, Deserializer, Serialize, Serializer};

use crate::features::activity::model::ActivitySummary;
use crate::features::json_file::{PersistError, read_bytes, write_pretty};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum ClockPhase {
    Running,
    Waiting,
    Failed,
}

/// Segundos entre 1970 e 2001, a data de referência do `Date` do Swift.
const REFERENCE_OFFSET: f64 = 978_307_200.0;

/// O `Date` no `JSONEncoder` do Swift é um número: segundos desde 2001-01-01.
fn to_reference(time: SystemTime) -> f64 {
    let unix = match time.duration_since(SystemTime::UNIX_EPOCH) {
        Ok(d) => d.as_secs_f64(),
        Err(e) => -e.duration().as_secs_f64(),
    };
    unix - REFERENCE_OFFSET
}

fn from_reference(seconds: f64) -> Option<SystemTime> {
    let unix = seconds + REFERENCE_OFFSET;
    if !unix.is_finite() {
        return None;
    }
    if unix >= 0.0 {
        SystemTime::UNIX_EPOCH.checked_add(Duration::try_from_secs_f64(unix).ok()?)
    } else {
        SystemTime::UNIX_EPOCH.checked_sub(Duration::try_from_secs_f64(-unix).ok()?)
    }
}

mod date_option {
    use super::*;

    pub fn serialize<S: Serializer>(value: &Option<SystemTime>, ser: S) -> Result<S::Ok, S::Error> {
        match value {
            Some(time) => ser.serialize_f64(to_reference(*time)),
            None => ser.serialize_none(),
        }
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(de: D) -> Result<Option<SystemTime>, D::Error> {
        match Option::<f64>::deserialize(de)? {
            None => Ok(None),
            Some(seconds) => from_reference(seconds)
                .map(Some)
                .ok_or_else(|| D::Error::custom("data fora do alcance")),
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Serialize, Deserialize)]
pub struct WorkbenchClock {
    pub running: f64,
    pub waiting: f64,
    pub failed: f64,
    /// O último instante com alguma fase andando — o "rodou por último" da aba
    /// Ativas (ADR-082). Sobrevive ao "zerar": é quando a bancada trabalhou, não
    /// quanto. Gravado como o `Date` do Swift: segundos desde 2001.
    #[serde(
        default,
        rename = "lastActive",
        with = "date_option",
        skip_serializing_if = "Option::is_none"
    )]
    pub last_active: Option<SystemTime>,
}

impl WorkbenchClock {
    /// O maior passo que um tique soma. O laço roda a cada 0,12 s; um buraco
    /// maior é o Mac dormindo ou o app travado, e esse tempo não foi de trabalho
    /// de ninguém.
    pub const MAX_STEP: f64 = 2.0;

    /// As fases em curso pelo estado dos terminais da bancada (ADR-078).
    ///
    /// Esperar você é só pergunta e permissão: quem aguarda um vizinho está em
    /// `background` e conta como trabalho, porque o trabalho seguiu no outro
    /// card. O erro sai das outras duas — o desistido conta em `attention` e a
    /// tentativa agendada em `background`, e nenhum dos dois é você nem
    /// trabalho.
    pub fn phases(summary: &ActivitySummary) -> BTreeSet<ClockPhase> {
        let mut out = BTreeSet::new();
        let gave_up = i64::from(summary.failed) - i64::from(summary.retrying);
        if summary.failed > 0 {
            out.insert(ClockPhase::Failed);
        }
        if i64::from(summary.attention) - gave_up > 0 {
            out.insert(ClockPhase::Waiting);
        }
        if i64::from(summary.working) + i64::from(summary.background) - i64::from(summary.retrying)
            > 0
        {
            out.insert(ClockPhase::Running);
        }
        out
    }

    pub fn add(&mut self, seconds: f64, phase: ClockPhase) {
        let step = if seconds.is_nan() {
            0.0
        } else {
            seconds.clamp(0.0, Self::MAX_STEP)
        };
        match phase {
            ClockPhase::Running => self.running += step,
            ClockPhase::Waiting => self.waiting += step,
            ClockPhase::Failed => self.failed += step,
        }
    }

    pub fn get(&self, phase: ClockPhase) -> f64 {
        match phase {
            ClockPhase::Running => self.running,
            ClockPhase::Waiting => self.waiting,
            ClockPhase::Failed => self.failed,
        }
    }

    /// "00:42", "12:05", "1:05:12" — minuto e segundo sempre, como relógio; a
    /// hora só quando existe.
    pub fn format(seconds: f64) -> String {
        let total = seconds.max(0.0) as u64;
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60);
        if h > 0 {
            format!("{h}:{m:02}:{s:02}")
        } else {
            format!("{m:02}:{s:02}")
        }
    }
}

/// Os cronômetros de todas as bancadas, somados a cada tique e guardados em
/// disco de tempos em tempos.
///
/// Por `id`, e não por nome, como tudo que é da bancada: renomear não zera. O
/// disco é gravado a cada 15 s, e não a cada tique — perder alguns segundos num
/// encerramento brusco não muda a leitura. A hora entra como parâmetro.
#[derive(Debug)]
pub struct WorkbenchClocks {
    directory: PathBuf,
    clocks: HashMap<String, WorkbenchClock>,
    dirty: HashSet<String>,
    last_tick: Option<SystemTime>,
    last_save: Option<SystemTime>,
}

impl WorkbenchClocks {
    pub const SAVE_INTERVAL: Duration = Duration::from_secs(15);

    /// `directory` é `workbenches/` dentro da pasta de dados.
    pub fn new(directory: PathBuf) -> Self {
        Self {
            directory,
            clocks: HashMap::new(),
            dirty: HashSet::new(),
            last_tick: None,
            last_save: None,
        }
    }

    pub fn file(&self, workbench_id: &str) -> PathBuf {
        self.directory.join(workbench_id).join("clock.json")
    }

    /// O cronômetro da bancada, lido do disco na primeira vez.
    pub fn clock(&mut self, id: &str) -> WorkbenchClock {
        if let Some(clock) = self.clocks.get(id) {
            return *clock;
        }
        let path = self.file(id);
        let mut loaded: WorkbenchClock = read_bytes(&path)
            .and_then(|bytes| crate::features::json_file::parse(&bytes).ok())
            .unwrap_or_default();
        // Arquivo de antes do `lastActive`: ele só é gravado quando alguma fase
        // andou, então a data dele é a última vez que a bancada rodou.
        if loaded.last_active.is_none() {
            loaded.last_active = modified(&path);
        }
        self.clocks.insert(id.to_owned(), loaded);
        loaded
    }

    /// Soma o tempo desde o tique anterior a cada fase em curso de cada
    /// bancada. Bancada fora de `phases` (parada, ou sem terminais de pé) não
    /// anda. O primeiro tique só marca a hora.
    pub fn tick(
        &mut self,
        phases: &BTreeMap<String, BTreeSet<ClockPhase>>,
        now: SystemTime,
    ) -> Result<(), PersistError> {
        let previous = self.last_tick.replace(now);
        let Some(previous) = previous else {
            self.last_save = Some(now);
            return Ok(());
        };
        let elapsed = now
            .duration_since(previous)
            .map_or_else(|e| -e.duration().as_secs_f64(), |d| d.as_secs_f64());
        for (id, current) in phases.iter().filter(|(_, p)| !p.is_empty()) {
            let mut clock = self.clock(id);
            for phase in current {
                clock.add(elapsed, *phase);
            }
            clock.last_active = Some(now);
            self.clocks.insert(id.clone(), clock);
            self.dirty.insert(id.clone());
        }
        let since_save = now
            .duration_since(self.last_save.unwrap_or(now))
            .unwrap_or_default();
        if since_save >= Self::SAVE_INTERVAL {
            self.flush(now)?;
        }
        Ok(())
    }

    /// "Limpar a bancada" e o menu do cronômetro: começa outro período, sem
    /// apagar quando ela rodou.
    pub fn reset(&mut self, id: &str, now: SystemTime) -> Result<(), PersistError> {
        let last_active = self.clock(id).last_active;
        self.clocks.insert(
            id.to_owned(),
            WorkbenchClock {
                last_active,
                ..WorkbenchClock::default()
            },
        );
        self.dirty.insert(id.to_owned());
        self.flush(now)
    }

    /// Grava o que mudou. Atômico: encerrar no meio não deixa meio arquivo.
    pub fn flush(&mut self, now: SystemTime) -> Result<(), PersistError> {
        self.last_save = Some(now);
        let mut first_error = None;
        for id in self.dirty.drain().collect::<Vec<_>>() {
            let Some(clock) = self.clocks.get(&id) else {
                continue;
            };
            if let Err(error) = write_pretty(&self.file(&id), clock) {
                first_error.get_or_insert(error);
            }
        }
        first_error.map_or(Ok(()), Err)
    }
}

fn modified(path: &Path) -> Option<SystemTime> {
    std::fs::metadata(path).ok()?.modified().ok()
}
