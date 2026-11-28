//! A aba "Ativas" da barra lateral (ADR-082): as bancadas de pé, da que rodou
//! por último para a que rodou há mais tempo, separadas em quem rodou nas
//! últimas 24 horas e quem está parada há mais que isso. Porte do
//! `ActiveWorkbenches`.

use std::cmp::Ordering;
use std::collections::HashMap;
use std::time::{Duration, SystemTime};

/// A janela do "recente".
pub const WINDOW: Duration = Duration::from_secs(24 * 3600);

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ActiveWorkbenches {
    pub recent: Vec<usize>,
    pub stale: Vec<usize>,
}

impl ActiveWorkbenches {
    /// `last_active` é o último instante com alguma fase do cronômetro andando.
    /// Bancada que nunca rodou vai para o fim das paradas — está de pé, mas não
    /// há o que ordenar nela. Empate pela posição na lista, para a ordem não
    /// pular entre um quadro e outro. `now` é parâmetro para o teste andar o
    /// relógio.
    pub fn new(live: &[usize], last_active: &HashMap<usize, SystemTime>, now: SystemTime) -> Self {
        let mut sorted: Vec<usize> = live.to_vec();
        sorted.sort_unstable();
        sorted.dedup();
        sorted.sort_by(|a, b| match (last_active.get(a), last_active.get(b)) {
            (Some(x), Some(y)) if x != y => y.cmp(x),
            (Some(_), None) => Ordering::Less,
            (None, Some(_)) => Ordering::Greater,
            _ => a.cmp(b),
        });
        let mut out = ActiveWorkbenches::default();
        for index in sorted {
            // Instante no futuro (relógio mexido) conta como agora.
            let recent = last_active.get(&index).is_some_and(|date| {
                now.duration_since(*date)
                    .map_or(true, |elapsed| elapsed < WINDOW)
            });
            if recent {
                out.recent.push(index);
            } else {
                out.stale.push(index);
            }
        }
        out
    }

    pub fn is_empty(&self) -> bool {
        self.recent.is_empty() && self.stale.is_empty()
    }
}
