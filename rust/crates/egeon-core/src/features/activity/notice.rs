//! O aviso do sistema e o som de atenção: o que avisar, quando tocar. Porte de
//! `SystemNotice.swift`, da decisão do `SystemNotifier` (só com o app fora da
//! frente) e do intervalo mínimo do `AttentionSound`. Quem entrega e toca é o
//! driver, pela `ports::notifier`.

use std::time::{Duration, SystemTime};

use super::model::Activity;
use crate::log;

/// O aviso para a central, com bancada e terminal separados do endereço para o
/// clique voltar ao lugar certo. Mesmos campos da `ports::notifier::Notice`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SystemNotice {
    /// Um por terminal: o novo do mesmo terminal substitui o anterior.
    pub identifier: String,
    pub title: String,
    pub body: String,
    pub workbench: String,
    pub node: String,
}

/// Um aviso por terminal: o novo do mesmo terminal substitui o anterior.
pub fn identifier(address: &str) -> String {
    format!("egeon.{address}")
}

/// O aviso de uma parada. `None` para o que não avisa — o que volta sozinho —
/// e para endereço sem bancada. `detail` é o que está esperando você.
pub fn system_notice(
    address: &str,
    activity: &Activity,
    detail: Option<&str>,
) -> Option<SystemNotice> {
    let slash = address.rfind('/')?;
    let (headline, detail) = match activity {
        Activity::Asking => ("precisa de você", detail.map(str::to_owned)),
        Activity::Waiting => ("já terminou o serviço", detail.map(str::to_owned)),
        Activity::Failed(why) => (
            "parou por um erro",
            Some(detail.map_or_else(|| why.clone(), str::to_owned)),
        ),
        _ => return None,
    };
    let workbench = address[..slash].to_owned();
    let node = address[slash + 1..].to_owned();
    // O terminal vai no corpo: no título ele competia com a bancada, que é o
    // que você reconhece de relance.
    let extra = detail.as_deref().map(str::trim).unwrap_or_default();
    let body = if extra.is_empty() {
        node.clone()
    } else {
        format!("{node}: {}", clip(extra, 180))
    };
    Some(SystemNotice {
        identifier: identifier(address),
        title: format!("A bancada {workbench} {headline}"),
        body,
        workbench,
        node,
    })
}

fn clip(text: &str, limit: usize) -> String {
    let flat = text.replace('\n', " ");
    if flat.chars().count() > limit {
        let mut out: String = flat.chars().take(limit).collect();
        out.push('…');
        out
    } else {
        flat
    }
}

/// Quatro agentes parando no mesmo tique tocariam quatro sons sobrepostos.
pub const SOUND_INTERVAL: Duration = Duration::from_millis(1500);

/// O que fazer com uma parada anunciada.
#[derive(Debug, Clone, PartialEq)]
pub struct Announcement {
    /// Para a central — só com o app fora da frente.
    pub notice: Option<SystemNotice>,
    /// `(nome, volume)` do som de atenção.
    pub sound: Option<(String, f64)>,
}

/// Guarda o último som, que é o único estado da decisão.
#[derive(Debug, Default)]
pub struct Announcer {
    last_sound: Option<SystemTime>,
    /// O `last_sound` de antes do último som pedido, para desfazer.
    before: Option<SystemTime>,
}

impl Announcer {
    pub fn new() -> Self {
        Self::default()
    }

    /// O driver não achou o som pedido: a janela de 1,5s não vale. No
    /// Swift o `lastPlayed` só era marcado depois de o `NSSound` carregar —
    /// um nome errado não podia calar o certo.
    pub fn sound_failed(&mut self) {
        self.last_sound = self.before;
    }

    /// `app_active`: a UI está na frente — a borda já diz tudo, e a
    /// notificação seria o mesmo aviso duas vezes. `authorized`: a central
    /// vai tocar o som dela, e o de atenção cala para não tocar em dobro.
    #[allow(clippy::too_many_arguments)]
    pub fn announce(
        &mut self,
        address: &str,
        activity: &Activity,
        detail: Option<&str>,
        sound: Option<&str>,
        volume: f64,
        app_active: bool,
        authorized: bool,
        now: SystemTime,
    ) -> Announcement {
        let will_sound = authorized && !app_active;
        let sound = sound
            .filter(|_| activity.needs_attention() && !will_sound)
            .filter(|name| !name.is_empty() && volume > 0.0)
            .filter(|_| {
                self.last_sound.is_none_or(|last| {
                    now.duration_since(last).unwrap_or(Duration::ZERO) >= SOUND_INTERVAL
                })
            })
            .map(|name| {
                self.before = self.last_sound;
                self.last_sound = Some(now);
                (name.to_owned(), volume.clamp(0.0, 1.0))
            });
        let notice = system_notice(address, activity, detail);
        let notice = match notice {
            Some(n) if app_active => {
                log!(
                    "notificação[{}/{}]: app na frente, só a borda",
                    n.workbench,
                    n.node
                );
                None
            }
            other => other,
        };
        Announcement { notice, sound }
    }
}
