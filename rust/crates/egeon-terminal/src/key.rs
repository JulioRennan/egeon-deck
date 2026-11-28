//! Da tecla do protocolo ao `GhosttyKey` do codificador (`key/event.h`).

use std::ffi::c_int;

use egeon_core::protocol::screen::{Key, KeyPress, Mods, NamedKey};

use crate::ffi;

const KEY_UNIDENTIFIED: c_int = 0;
const KEY_DIGIT_0: c_int = 6;
const KEY_A: c_int = 20;

/// A tecla física, o caractere sem shift e o texto que ela produz, prontos para
/// o evento do Ghostty.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct KeySpec {
    pub key: c_int,
    pub unshifted: u32,
    pub mods: u16,
    pub consumed: u16,
    pub text: String,
}

pub(crate) fn spec(press: &KeyPress) -> KeySpec {
    let mods = mods_bits(press.mods);
    let (key, unshifted) = match &press.key {
        Key::Named(named) => (named_key(*named), named_codepoint(*named)),
        Key::Char(s) => match s.chars().next() {
            Some(c) => (char_key(c), c as u32),
            None => (KEY_UNIDENTIFIED, 0),
        },
    };

    // Sem `text`, o caractere da própria tecla é o texto — menos com ctrl/super,
    // que não produzem texto (o codificador monta a sequência pela tecla).
    let text = match (&press.text, &press.key) {
        (Some(t), _) => t.clone(),
        (None, Key::Char(s)) if !press.mods.ctrl && !press.mods.meta => s.clone(),
        (None, Key::Named(NamedKey::Space)) if !press.mods.ctrl && !press.mods.meta => {
            " ".to_owned()
        }
        _ => String::new(),
    };
    // O Ghostty proíbe controle C0 e DEL no texto: para essas teclas ele usa a
    // tecla lógica.
    let text = if text.chars().any(char::is_control) {
        String::new()
    } else {
        text
    };
    // Shift que já virou texto ("A") não é modificador de novo para o
    // codificador; sem isso, shift+a sairia como sequência CSI u.
    let consumed = if press.mods.shift && !text.is_empty() {
        ffi::MODS_SHIFT
    } else {
        0
    };
    KeySpec {
        key,
        unshifted,
        mods,
        consumed,
        text,
    }
}

/// Os modificadores no formato `GhosttyMods`, que tecla e mouse usam.
pub(crate) fn mods_bits(m: Mods) -> u16 {
    let mut bits = 0;
    if m.shift {
        bits |= ffi::MODS_SHIFT;
    }
    if m.ctrl {
        bits |= ffi::MODS_CTRL;
    }
    if m.alt {
        bits |= ffi::MODS_ALT;
    }
    if m.meta {
        bits |= ffi::MODS_SUPER;
    }
    bits
}

fn named_key(key: NamedKey) -> c_int {
    match key {
        NamedKey::Enter => 58,
        NamedKey::Tab => 64,
        NamedKey::Backspace => 53,
        NamedKey::Escape => 120,
        NamedKey::Space => 63,
        NamedKey::Up => 78,
        NamedKey::Down => 75,
        NamedKey::Left => 76,
        NamedKey::Right => 77,
        NamedKey::Home => 71,
        NamedKey::End => 69,
        NamedKey::PageUp => 74,
        NamedKey::PageDown => 73,
        NamedKey::Insert => 72,
        NamedKey::Delete => 68,
        NamedKey::F1 => 121,
        NamedKey::F2 => 122,
        NamedKey::F3 => 123,
        NamedKey::F4 => 124,
        NamedKey::F5 => 125,
        NamedKey::F6 => 126,
        NamedKey::F7 => 127,
        NamedKey::F8 => 128,
        NamedKey::F9 => 129,
        NamedKey::F10 => 130,
        NamedKey::F11 => 131,
        NamedKey::F12 => 132,
    }
}

/// O protocolo do kitty identifica Enter, Tab, Backspace, Escape e Espaço pelo
/// código do caractere; as demais teclas com nome não têm um.
fn named_codepoint(key: NamedKey) -> u32 {
    match key {
        NamedKey::Enter => '\r' as u32,
        NamedKey::Tab => '\t' as u32,
        NamedKey::Backspace => 0x7f,
        NamedKey::Escape => 0x1b,
        NamedKey::Space => ' ' as u32,
        _ => 0,
    }
}

/// Tecla física de um caractere do layout americano. Fora dele, a tecla fica
/// sem identificação e o codificador trabalha só com o texto.
fn char_key(c: char) -> c_int {
    let c = c.to_ascii_lowercase();
    match c {
        'a'..='z' => KEY_A + (c as c_int - 'a' as c_int),
        '0'..='9' => KEY_DIGIT_0 + (c as c_int - '0' as c_int),
        '`' => 1,
        '\\' => 2,
        '[' => 3,
        ']' => 4,
        ',' => 5,
        '=' => 16,
        '-' => 46,
        '.' => 47,
        '\'' => 48,
        ';' => 49,
        '/' => 50,
        ' ' => 63,
        _ => KEY_UNIDENTIFIED,
    }
}

#[cfg(test)]
mod tests {
    use egeon_core::protocol::screen::Mods;

    use super::*;

    fn press(key: Key, mods: Mods, text: Option<&str>) -> KeyPress {
        KeyPress {
            key,
            mods,
            text: text.map(str::to_owned),
        }
    }

    #[test]
    fn letra_vira_tecla_e_texto() {
        let s = spec(&press(Key::Char("q".into()), Mods::default(), None));
        assert_eq!(s.key, KEY_A + 16);
        assert_eq!(s.unshifted, 'q' as u32);
        assert_eq!(s.text, "q");
        assert_eq!(s.mods, 0);
    }

    #[test]
    fn ctrl_nao_produz_texto() {
        let mods = Mods {
            ctrl: true,
            ..Mods::default()
        };
        let s = spec(&press(Key::Char("c".into()), mods, None));
        assert_eq!(s.text, "");
        assert_eq!(s.mods, ffi::MODS_CTRL);
    }

    #[test]
    fn shift_que_virou_texto_e_consumido() {
        let mods = Mods {
            shift: true,
            ..Mods::default()
        };
        let s = spec(&press(Key::Char("a".into()), mods, Some("A")));
        assert_eq!(s.text, "A");
        assert_eq!(s.consumed, ffi::MODS_SHIFT);
    }

    #[test]
    fn texto_de_controle_e_descartado() {
        let s = spec(&press(
            Key::Named(NamedKey::Enter),
            Mods::default(),
            Some("\r"),
        ));
        assert_eq!(s.text, "");
        assert_eq!(s.key, 58);
    }

    #[test]
    fn caractere_fora_do_layout_americano_vai_so_como_texto() {
        let s = spec(&press(Key::Char("ç".into()), Mods::default(), None));
        assert_eq!(s.key, KEY_UNIDENTIFIED);
        assert_eq!(s.text, "ç");
    }
}
