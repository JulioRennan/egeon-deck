//! Notificação e som de atenção: implementa `ports::notifier::Notifier`.

use egeon_core::ports::notifier::{Notice, NoticeClick, Notifier, SoundError};
use tokio::sync::mpsc;

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
use macos as platform;
#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "linux")]
use linux as platform;

/// O notificador do sistema em que o programa roda.
#[derive(Default)]
pub struct SystemNotifier {
    center: platform::Center,
    sounds: platform::Sounds,
}

impl SystemNotifier {
    pub fn new() -> Self {
        Self::default()
    }
}

/// O alerta sonoro do sistema, que o `Opener` toca no ⌘-clique sem destino.
#[cfg(target_os = "linux")]
pub(crate) fn beep() {
    platform::beep();
}

impl Notifier for SystemNotifier {
    fn start(&self) -> mpsc::Receiver<NoticeClick> {
        self.center.start()
    }

    fn authorized(&self) -> bool {
        self.center.authorized()
    }

    fn post(&self, notice: Notice) {
        self.center.post(notice);
    }

    fn withdraw(&self, identifier: &str) {
        self.center.withdraw(identifier);
    }

    fn play_sound(&self, name: &str, volume: f64) -> Result<(), SoundError> {
        self.sounds.play(name, volume)
    }
}
