//! `CFRunLoop` da thread principal.

use std::ffi::c_void;
use std::ptr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use block2::RcBlock;
use objc2_core_foundation::{
    CFAbsoluteTimeGetCurrent, CFRetained, CFRunLoop, CFRunLoopTimer, kCFRunLoopCommonModes,
    kCFRunLoopDefaultMode,
};

pub(super) fn is_main_thread() -> bool {
    // SAFETY: `pthread_main_np` não tem pré-condição.
    unsafe { libc::pthread_main_np() == 1 }
}

/// A fatia de cada giro: com a parada perdida (o `core` acabou antes de o loop
/// começar) é o tempo máximo até o `spin` notar que acabou.
const SLICE: Duration = Duration::from_millis(500);

pub(super) struct Spinner {
    run_loop: CFRetained<CFRunLoop>,
    keepalive: CFRetained<CFRunLoopTimer>,
    done: Arc<AtomicBool>,
}

pub(super) struct Stopper {
    run_loop: StopHandle,
    done: Arc<AtomicBool>,
}

/// O `CFRunLoop` principal, para a thread do core pará-lo.
struct StopHandle(CFRetained<CFRunLoop>);

// SAFETY: `CFRunLoopStop` e `CFRunLoopWakeUp` são documentados como seguros
// para chamar de qualquer thread, e é só o que se faz com este valor.
unsafe impl Send for StopHandle {}

unsafe extern "C-unwind" fn nothing(_timer: *mut CFRunLoopTimer, _info: *mut c_void) {}

impl Spinner {
    pub(super) fn new() -> Option<Self> {
        let run_loop = CFRunLoop::main()?;
        // Run loop sem fonte nem timer sai no ato: este, para daqui a séculos,
        // o mantém de pé.
        // SAFETY: o `callout` não faz nada e o `context` é nulo, o que a
        // chamada aceita.
        let keepalive = unsafe {
            CFRunLoopTimer::new(
                None,
                CFAbsoluteTimeGetCurrent() + 3.0e9,
                0.0,
                0,
                0,
                Some(nothing),
                ptr::null_mut(),
            )
        };
        // Sem o timer o loop ficaria sem fonte e o `spin` giraria em falso.
        let keepalive = keepalive?;
        // SAFETY: o modo é uma constante do sistema.
        run_loop.add_timer(Some(&keepalive), unsafe { kCFRunLoopCommonModes });
        Some(Self {
            run_loop,
            keepalive,
            done: Arc::new(AtomicBool::new(false)),
        })
    }

    pub(super) fn stopper(&self) -> Stopper {
        Stopper {
            run_loop: StopHandle(self.run_loop.clone()),
            done: self.done.clone(),
        }
    }

    pub(super) fn spin(&self) {
        while !self.done.load(Ordering::Acquire) {
            // SAFETY: o modo é uma constante do sistema.
            CFRunLoop::run_in_mode(unsafe { kCFRunLoopDefaultMode }, SLICE.as_secs_f64(), false);
        }
    }
}

impl Drop for Spinner {
    fn drop(&mut self) {
        // Um `run` seguinte não herda o timer deste.
        self.keepalive.invalidate();
    }
}

impl Stopper {
    pub(super) fn stop(&self) {
        self.done.store(true, Ordering::Release);
        self.run_loop.0.stop();
        self.run_loop.0.wake_up();
    }
}

pub(super) fn on_main(job: impl FnOnce() + Send + 'static) {
    let Some(main) = CFRunLoop::main() else {
        return;
    };
    let job = Mutex::new(Some(job));
    let block = RcBlock::new(move || {
        let taken = job.lock().ok().and_then(|mut slot| slot.take());
        if let Some(job) = taken {
            job();
        }
    });
    // SAFETY: o bloco é copiado pelo sistema e roda uma vez, na principal;
    // o modo é uma constante do sistema.
    unsafe { main.perform_block(kCFRunLoopCommonModes.map(|mode| &**mode), Some(&block)) };
    main.wake_up();
}
