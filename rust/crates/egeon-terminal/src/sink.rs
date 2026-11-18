//! O que o Ghostty entrega por callback durante um `vt_write`: respostas ao
//! programa, sino e a área de transferência.

use std::collections::VecDeque;
use std::ffi::c_void;
use std::mem::size_of;
use std::ptr;

use egeon_core::protocol::screen::Effect;

use crate::ffi;

/// Onde os callbacks juntam o que acontece num `vt_write`. Vive fora da tela
/// (em `Box::into_raw`) porque o Ghostty guarda o endereço: mover a tela não
/// pode movê-lo.
#[derive(Default)]
pub(crate) struct Sink {
    pub replies: Vec<u8>,
    pub effects: Vec<Effect>,
    /// O envelope de cada consulta OSC 52 ainda sem resposta, como o Ghostty
    /// o escreveria vazio (`ESC]52;c;` mais o terminador do pedido).
    pending_reads: VecDeque<Vec<u8>>,
}

impl Sink {
    /// A resposta à consulta mais antiga, com `text` em base64 no envelope
    /// dela — o que o SwiftTerm manda (`52;<sel>;<base64>`).
    pub fn answer_clipboard(&mut self, text: &str) -> Vec<u8> {
        let Some(envelope) = self.pending_reads.pop_front() else {
            return Vec::new();
        };
        let Some(split) = envelope.iter().rposition(|&b| b == b';') else {
            return Vec::new();
        };
        let (head, terminator) = envelope.split_at(split + 1);
        let mut out = head.to_vec();
        out.extend_from_slice(base64(text.as_bytes()).as_bytes());
        out.extend_from_slice(terminator);
        out
    }
}

/// Liga os callbacks ao terminal, com `sink` como userdata.
///
/// # Safety
/// `term` vivo e `sink` vindo de `Box::into_raw`, solto só depois do terminal.
pub(crate) unsafe fn install(term: ffi::Terminal, sink: *mut Sink) -> Result<(), &'static str> {
    let write_pty: ffi::WritePtyFn = on_write_pty;
    let bell: ffi::BellFn = on_bell;
    let clip_write: ffi::ClipboardWriteFn = on_clipboard_write;
    let clip_read: ffi::ClipboardReadFn = on_clipboard_read;
    let options: [(i32, *const c_void, &'static str); 5] = [
        (ffi::TERMINAL_OPT_USERDATA, sink.cast(), "opt_userdata"),
        (
            ffi::TERMINAL_OPT_WRITE_PTY,
            write_pty as *const c_void,
            "opt_write_pty",
        ),
        (ffi::TERMINAL_OPT_BELL, bell as *const c_void, "opt_bell"),
        (
            ffi::TERMINAL_OPT_CLIPBOARD_WRITE,
            clip_write as *const c_void,
            "opt_clipboard_write",
        ),
        (
            ffi::TERMINAL_OPT_CLIPBOARD_READ,
            clip_read as *const c_void,
            "opt_clipboard_read",
        ),
    ];
    for (option, value, what) in options {
        // SAFETY: cada opção recebe o tipo que o cabeçalho pede; o contrato da
        // função garante `term` e `sink`.
        if unsafe { ffi::ghostty_terminal_set(term, option, value) } != ffi::SUCCESS {
            return Err(what);
        }
    }
    Ok(())
}

/// # Safety
/// Só o Ghostty chama, dentro do `vt_write` da tela dona de `userdata`, sem
/// outra referência viva ao `Sink`.
unsafe fn sink<'a>(userdata: *mut c_void) -> Option<&'a mut Sink> {
    // SAFETY: ver o contrato acima.
    unsafe { userdata.cast::<Sink>().as_mut() }
}

/// # Safety
/// `s.ptr` vale por `s.len` bytes, ou `s.len` é zero.
unsafe fn bytes<'a>(s: &ffi::GhosttyString) -> &'a [u8] {
    if s.ptr.is_null() || s.len == 0 {
        return &[];
    }
    // SAFETY: ver o contrato acima.
    unsafe { std::slice::from_raw_parts(s.ptr, s.len) }
}

unsafe extern "C" fn on_write_pty(
    _terminal: ffi::Terminal,
    userdata: *mut c_void,
    data: *const u8,
    len: usize,
) {
    // SAFETY: chamado pelo Ghostty dentro do `vt_write`; `data` vale por `len`
    // bytes durante a chamada.
    unsafe {
        let (Some(out), false) = (sink(userdata), data.is_null()) else {
            return;
        };
        out.replies
            .extend_from_slice(std::slice::from_raw_parts(data, len));
    }
}

unsafe extern "C" fn on_bell(_terminal: ffi::Terminal, userdata: *mut c_void) {
    // SAFETY: chamado pelo Ghostty dentro do `vt_write`.
    if let Some(out) = unsafe { sink(userdata) } {
        out.effects.push(Effect::Bell);
    }
}

unsafe extern "C" fn on_clipboard_write(
    _terminal: ffi::Terminal,
    userdata: *mut c_void,
    write: *const ffi::ClipboardWrite,
) {
    // SAFETY: o pedido e o que ele aponta valem durante o callback.
    let Some(req) = (unsafe { write.as_ref() }) else {
        return;
    };
    // SAFETY: chamado pelo Ghostty dentro do `vt_write`.
    if let Some(out) = unsafe { sink(userdata) } {
        // Gravação sem conteúdo é limpar a área; o SwiftTerm grava a string
        // vazia nesse caso.
        let text = (0..req.contents_len)
            .filter_map(|i| {
                // SAFETY: `contents` tem `contents_len` entradas.
                let c = unsafe { &*req.contents.add(i) };
                // SAFETY: as strings do pedido valem durante o callback.
                let mime = unsafe { bytes(&c.mime) };
                mime.starts_with(b"text/")
                    .then(|| String::from_utf8_lossy(unsafe { bytes(&c.data) }).into_owned())
            })
            .next()
            .unwrap_or_default();
        out.effects.push(Effect::Clipboard { text });
    }
    let reply = ffi::ClipboardWriteReply {
        size: size_of::<ffi::ClipboardWriteReply>(),
        result: ffi::CLIPBOARD_WRITE_SUCCESS,
        remember: false,
    };
    if let Some(answer) = req.reply {
        // SAFETY: responder dentro do callback é o contrato do cabeçalho.
        unsafe { answer(write, &reply) };
    }
}

unsafe extern "C" fn on_clipboard_read(
    _terminal: ffi::Terminal,
    userdata: *mut c_void,
    read: *const ffi::ClipboardRead,
) {
    // SAFETY: o pedido vale durante o callback.
    let Some(answer) = (unsafe { read.as_ref() }).and_then(|r| r.reply) else {
        return;
    };
    // A leitura no Ghostty é síncrona, e a área de transferência mora na UI:
    // responde-se "não sei" na hora, e o envelope vazio que o Ghostty escreve
    // por isso sai das respostas e fica guardado até a UI mandar o conteúdo.
    // Nenhuma referência ao `Sink` atravessa a chamada a `answer`, que escreve
    // nele pelo `on_write_pty`.
    // SAFETY: chamado pelo Ghostty dentro do `vt_write`.
    let Some(before) = (unsafe { sink(userdata) }).map(|s| s.replies.len()) else {
        return;
    };
    let reply = ffi::ClipboardReadReply {
        size: size_of::<ffi::ClipboardReadReply>(),
        result: ffi::CLIPBOARD_READ_UNSUPPORTED,
        contents: ptr::null(),
        contents_len: 0,
        available: ptr::null(),
        available_len: 0,
        remember: false,
    };
    // SAFETY: `reply` vive até o fim desta função, e o Ghostty só o lê durante
    // a chamada.
    unsafe { answer(read, &reply) };
    // SAFETY: como acima; a chamada a `answer` já voltou.
    if let Some(out) = unsafe { sink(userdata) } {
        let envelope = out.replies.split_off(before.min(out.replies.len()));
        out.pending_reads.push_back(envelope);
        out.effects.push(Effect::ClipboardRequest);
    }
}

const BASE64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn base64(data: &[u8]) -> String {
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let b = [
            chunk[0],
            chunk.get(1).copied().unwrap_or(0),
            chunk.get(2).copied().unwrap_or(0),
        ];
        let n = (u32::from(b[0]) << 16) | (u32::from(b[1]) << 8) | u32::from(b[2]);
        for i in 0..4 {
            if i <= chunk.len() {
                out.push(char::from(BASE64[(n >> (18 - 6 * i)) as usize & 63]));
            } else {
                out.push('=');
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_com_e_sem_enchimento() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"xyz"), "eHl6");
        assert_eq!(base64(b"hello"), "aGVsbG8=");
        assert_eq!(base64(b"hi"), "aGk=");
        assert_eq!(base64("ç".as_bytes()), "w6c=");
    }

    #[test]
    fn resposta_usa_o_envelope_da_consulta() {
        let mut sink = Sink::default();
        sink.pending_reads.push_back(b"\x1b]52;p;\x1b\\".to_vec());
        assert_eq!(sink.answer_clipboard("xyz"), b"\x1b]52;p;eHl6\x1b\\");
        assert!(sink.answer_clipboard("xyz").is_empty());
    }
}
