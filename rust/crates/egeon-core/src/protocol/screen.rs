//! O que a tela de um terminal manda à UI pelo tópico `screen/<id>` e o que a
//! UI manda de volta como tecla.
//!
//! Os mesmos tipos saem da interface de tela (`ports::screen`): o terminal os
//! preenche e o runtime só os embrulha no evento, sem conversão no meio.

use serde::{Deserialize, Serialize};

/// Colunas × linhas da grade visível.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Size {
    pub cols: u16,
    pub rows: u16,
}

/// Cor de uma célula. Ausente no span quer dizer a cor padrão do tema.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Color {
    /// Índice da paleta de 256 cores (0–15 são as cores do tema).
    Palette(u8),
    /// Cor direta, `#rrggbb`.
    Rgb(RgbHex),
}

/// Cor direta gravada como `"#rrggbb"`: no fio é uma string só, e não três
/// campos, porque é a forma que a UI já sabe ler.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RgbHex(pub [u8; 3]);

impl Serialize for RgbHex {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let [r, g, b] = self.0;
        s.serialize_str(&format!("#{r:02x}{g:02x}{b:02x}"))
    }
}

impl<'de> Deserialize<'de> for RgbHex {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let raw = String::deserialize(d)?;
        let hex = raw
            .strip_prefix('#')
            .filter(|h| h.len() == 6 && h.is_ascii())
            .ok_or_else(|| {
                serde::de::Error::custom(format!("cor fora do formato #rrggbb: {raw}"))
            })?;
        let byte = |i: usize| {
            u8::from_str_radix(&hex[i..i + 2], 16).map_err(|_| {
                serde::de::Error::custom(format!("cor fora do formato #rrggbb: {raw}"))
            })
        };
        Ok(Self([byte(0)?, byte(2)?, byte(4)?]))
    }
}

fn is_false(v: &bool) -> bool {
    !*v
}

/// Atributos de um trecho. Campo falso ou cor padrão não vai para o fio: a
/// maior parte da tela é texto sem estilo, e é ela que pesa no volume.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Style {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fg: Option<Color>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bg: Option<Color>,
    #[serde(default, skip_serializing_if = "is_false")]
    pub bold: bool,
    #[serde(default, skip_serializing_if = "is_false")]
    pub dim: bool,
    #[serde(default, skip_serializing_if = "is_false")]
    pub italic: bool,
    #[serde(default, skip_serializing_if = "is_false")]
    pub underline: bool,
    #[serde(default, skip_serializing_if = "is_false")]
    pub strike: bool,
    #[serde(default, skip_serializing_if = "is_false")]
    pub inverse: bool,
}

/// Células vizinhas com o mesmo estilo, juntas.
///
/// `col` é a coluna da primeira célula e `cells` quantas ela ocupa: com
/// caractere largo (CJK, emoji) o número de células não é o de caracteres, e
/// a UI posiciona pelo que veio daqui em vez de medir.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Span {
    pub col: u16,
    pub cells: u16,
    pub text: String,
    #[serde(flatten)]
    pub style: Style,
}

/// Uma linha da grade. Células em branco com estilo padrão no fim da linha
/// não vêm; a UI pinta o resto com o fundo do tema.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Line {
    pub row: u16,
    pub spans: Vec<Span>,
    /// Colunas da seleção nesta linha, as duas inclusas.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub selection: Option<[u16; 2]>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum CursorShape {
    Block,
    Bar,
    Underline,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Cursor {
    pub row: u16,
    pub col: u16,
    pub visible: bool,
    pub shape: CursorShape,
}

/// `full` traz todas as linhas (ao assinar e depois de resize); `delta`, só as
/// que mudaram desde o último quadro.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FrameKind {
    Full,
    Delta,
}

/// Um quadro da tela: o corpo do evento `screen/<id>`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Frame {
    pub kind: FrameKind,
    pub cols: u16,
    pub rows: u16,
    pub cursor: Cursor,
    /// Vem no `full` sempre e no `delta` só quando mudou.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scrollbar: Option<Scrollbar>,
    pub lines: Vec<Line>,
}

/// Tecla com nome; o que não está aqui chega como texto em [`Key::Char`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum NamedKey {
    Enter,
    Tab,
    Backspace,
    Escape,
    Space,
    Up,
    Down,
    Left,
    Right,
    Home,
    End,
    PageUp,
    PageDown,
    Insert,
    Delete,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Key {
    Named(NamedKey),
    /// Um caractere sem modificador de layout aplicado (`"a"`, não `"A"` com
    /// shift): o terminal precisa da tecla para codificar ctrl/alt.
    Char(String),
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Mods {
    #[serde(default, skip_serializing_if = "is_false")]
    pub shift: bool,
    #[serde(default, skip_serializing_if = "is_false")]
    pub ctrl: bool,
    #[serde(default, skip_serializing_if = "is_false")]
    pub alt: bool,
    #[serde(default, skip_serializing_if = "is_false")]
    pub meta: bool,
}

/// Uma tecla apertada. Quem a transforma em bytes é o terminal, porque a
/// codificação depende do modo em que a tela está (cursor de aplicação,
/// protocolo de teclado do kitty…).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KeyPress {
    pub key: Key,
    #[serde(default)]
    pub mods: Mods,
    /// O texto que a tecla produz no layout do usuário (`"A"`, `"ç"`), quando
    /// produz.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
}

/// Para onde levar a vista. Negativo em `Rows` sobe para o histórico.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Scroll {
    Rows(i32),
    Top,
    Bottom,
}

/// Onde a vista está no histórico, em linhas: `offset` é a primeira linha
/// visível contada do topo do histórico e `len` quantas cabem na vista.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Scrollbar {
    pub total: u64,
    pub offset: u64,
    pub len: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PointerKind {
    Press,
    Release,
    Drag,
    Move,
    Wheel,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MouseButton {
    Left,
    Middle,
    Right,
}

/// Um gesto do ponteiro sobre a tela, cru: quem decide se vira relatório de
/// mouse para o programa, seleção ou rolagem é o terminal, pelo modo em que o
/// programa deixou a tela.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Pointer {
    pub kind: PointerKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub button: Option<MouseButton>,
    /// Posição em células, fracionária e relativa ao canto da vista (`3.4` é
    /// 40% dentro da coluna 3). No arrasto pode vir fora da vista, e é isso
    /// que rola a seleção.
    pub x: f32,
    pub y: f32,
    #[serde(default)]
    pub mods: Mods,
    /// Relógio da UI em milissegundos, para contar o clique duplo e o triplo.
    #[serde(default)]
    pub time_ms: u64,
    /// Só na roda: linhas, positivo sobe.
    #[serde(default, skip_serializing_if = "is_zero")]
    pub lines: i32,
}

fn is_zero(v: &i32) -> bool {
    *v == 0
}

/// O que o programa pediu ao app, fora da tela. No fio: `{"effect":"bell"}`,
/// `{"effect":"clipboard","text":…}` e `{"effect":"clipboard_request"}`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "effect", rename_all = "snake_case")]
pub enum Effect {
    Bell,
    /// Texto que o programa gravou na área de transferência (OSC 52).
    Clipboard {
        text: String,
    },
    /// O programa quer ler a área de transferência (OSC 52 com `?`); a
    /// resposta volta pela tela, em [`crate::ports::screen::Screen::clipboard_answer`].
    ClipboardRequest,
}
