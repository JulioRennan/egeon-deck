//! Quantas sessões de PowerShell os testes abrem ao mesmo tempo. O PowerShell
//! 5.1 abrindo vinte de uma vez num runner do CI chegou a levar mais que o
//! prazo para rodar a primeira linha (ci/win-11 a 15): com poucas por vez o
//! teste mede o terminal, não a fila da máquina. O prazo de cada teste só
//! começa depois de a vaga sair.

use std::sync::{Condvar, Mutex, PoisonError};

const AT_ONCE: usize = 2;

static OPEN: Mutex<usize> = Mutex::new(0);
static FREED: Condvar = Condvar::new();

/// Uma vaga; largá-la libera a próxima.
pub struct Slot(());

pub fn slot() -> Slot {
    let mut open = OPEN.lock().unwrap_or_else(PoisonError::into_inner);
    while *open >= AT_ONCE {
        open = FREED.wait(open).unwrap_or_else(PoisonError::into_inner);
    }
    *open += 1;
    Slot(())
}

impl Drop for Slot {
    fn drop(&mut self) {
        let mut open = OPEN.lock().unwrap_or_else(PoisonError::into_inner);
        *open = open.saturating_sub(1);
        FREED.notify_one();
    }
}
