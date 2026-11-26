//! A thread principal do Linux não tem run loop do sistema: nada do driver
//! depende dela (o D-Bus e o som rodam em qualquer thread). Ela fica parada
//! numa fila, para o `on_main` continuar valendo como no macOS.

use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Mutex, PoisonError};

type Job = Box<dyn FnOnce() + Send>;

enum Message {
    Job(Job),
    Stop,
}

/// A fila da principal enquanto um `run` gira; `None` fora dele.
static MAIN: Mutex<Option<Sender<Message>>> = Mutex::new(None);

pub(super) fn is_main_thread() -> bool {
    // SAFETY: `gettid` e `getpid` não têm pré-condição. Na thread principal o
    // id da thread é o do processo.
    unsafe { libc::gettid() == libc::getpid() }
}

pub(super) struct Spinner {
    queue: Receiver<Message>,
    sender: Sender<Message>,
}

pub(super) struct Stopper(Sender<Message>);

impl Spinner {
    pub(super) fn new() -> Option<Self> {
        let (sender, queue) = mpsc::channel();
        *MAIN.lock().unwrap_or_else(PoisonError::into_inner) = Some(sender.clone());
        Some(Self { queue, sender })
    }

    pub(super) fn stopper(&self) -> Stopper {
        Stopper(self.sender.clone())
    }

    pub(super) fn spin(&self) {
        while let Ok(Message::Job(job)) = self.queue.recv() {
            job();
        }
    }
}

impl Drop for Spinner {
    fn drop(&mut self) {
        // Um `on_main` depois do fim não fica preso numa fila que ninguém lê.
        *MAIN.lock().unwrap_or_else(PoisonError::into_inner) = None;
    }
}

impl Stopper {
    pub(super) fn stop(&self) {
        let _ = self.0.send(Message::Stop);
    }
}

pub(super) fn on_main(job: impl FnOnce() + Send + 'static) {
    let main = MAIN.lock().unwrap_or_else(PoisonError::into_inner);
    if let Some(sender) = main.as_ref() {
        let _ = sender.send(Message::Job(Box::new(job)));
    }
}
