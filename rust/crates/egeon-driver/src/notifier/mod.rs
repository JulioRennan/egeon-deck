//! Notificação e som de atenção: implementa `ports::notifier::Notifier`.

use egeon_core::ports::notifier::{Notice, NoticeClick, Notifier, SoundError};
use tokio::sync::mpsc;

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
use macos as platform;

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
