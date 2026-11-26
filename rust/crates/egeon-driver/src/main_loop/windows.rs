//! Como no Linux: nada do driver do Windows depende de um laço de mensagens na
//! thread principal (o ConPTY, o socket e o som rodam em qualquer thread).
//! Ela fica parada numa fila, para o `on_main` continuar valendo.

use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::{Mutex, PoisonError};

type Job = Box<dyn FnOnce() + Send>;

enum Message {
    Job(Job),
    Stop,
}

static MAIN: Mutex<Option<Sender<Message>>> = Mutex::new(None);

/// O Windows não diz qual é a thread principal; o Rust dá o nome `main` a ela
/// e a nenhuma outra.
pub(super) fn is_main_thread() -> bool {
    std::thread::current().name() == Some("main")
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
