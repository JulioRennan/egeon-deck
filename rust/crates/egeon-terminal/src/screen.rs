//! A tela sobre o libghostty-vt: um terminal, o estado de renderização que
//! diz quais linhas mudaram, e o codificador de teclas.

use std::ffi::{c_int, c_void};
use std::mem::size_of;
use std::ptr;

use egeon_core::ports::screen::{LinkHit, Screen, ScreenError, ScreenFactory};
use egeon_core::protocol::screen::{
    Color, Cursor, CursorShape, Effect, Frame, FrameKind, KeyPress, Pointer, RgbHex, Scroll,
    Scrollbar, Size, Style,
};

use crate::ffi;
use crate::key;
use crate::line::{self, Cell};
use crate::sink::{self, Sink};

mod hit;
mod pointer;

/// O histórico do SwiftTerm do app de hoje (`TerminalOptions.default`).
const SCROLLBACK_LINES: usize = 500;

/// Células de uma página do Ghostty 1.0.1, medido: ~47 mil (≈ 400 KB). Ele
/// poda o histórico descartando a página mais antiga inteira.
const PAGE_CELLS: usize = 48_000;

/// O teto de linhas que mantém pelo menos [`SCROLLBACK_LINES`] no histórico.
/// Com o teto em 500, a poda de uma página derrubava o histórico para bem
/// menos — num terminal estreito a página passa de 2 mil linhas e sobrava
/// uma. Uma página de folga garante as 500 em qualquer largura.
fn scrollback_limit(cols: u16) -> usize {
    SCROLLBACK_LINES + PAGE_CELLS.div_ceil(usize::from(cols.max(1)))
}

/// Uma linha lida da vista.
struct Row {
    y: u16,
    cells: Vec<Cell>,
    selection: Option<[u16; 2]>,
    /// Continua a linha de cima, que o terminal quebrou por falta de espaço.
    continued: bool,
}

/// Abre uma [`GhosttyScreen`] por nó.
#[derive(Debug, Default, Clone, Copy)]
pub struct GhosttyScreens;

impl ScreenFactory for GhosttyScreens {
    fn create(&self, size: Size) -> Result<Box<dyn Screen>, ScreenError> {
        Ok(Box::new(GhosttyScreen::new(size)?))
    }
}

/// Uma tela. Os ponteiros são donos exclusivos dos objetos do Ghostty, criados
/// em [`GhosttyScreen::new`] e liberados no `Drop`.
pub struct GhosttyScreen {
    term: ffi::Terminal,
    render: ffi::RenderState,
    rows: ffi::RowIterator,
    cells: ffi::RowCells,
    encoder: ffi::KeyEncoder,
    event: ffi::KeyEvent,
    mouse: ffi::MouseEncoder,
    mouse_event: ffi::MouseEvent,
    gesture: ffi::Gesture,
    press: ffi::GestureEvent,
    release: ffi::GestureEvent,
    drag: ffi::GestureEvent,
    tick: ffi::GestureEvent,
    formatter: ffi::Formatter,
    sink: *mut Sink,
    size: Size,
    sent_cursor: Option<Cursor>,
    sent_scrollbar: Option<Scrollbar>,
}

// SAFETY: o Ghostty não amarra os objetos a uma thread; o que ele exige é que
// ninguém os use ao mesmo tempo (`terminal.h`, junto de
// `ghostty_terminal_compress`), e todo acesso aqui passa por `&mut self`.
unsafe impl Send for GhosttyScreen {}

impl GhosttyScreen {
    pub fn new(size: Size) -> Result<Self, ScreenError> {
        check_size(size)?;
        let mut screen = Self {
            term: ptr::null_mut(),
            render: ptr::null_mut(),
            rows: ptr::null_mut(),
            cells: ptr::null_mut(),
            encoder: ptr::null_mut(),
            event: ptr::null_mut(),
            mouse: ptr::null_mut(),
            mouse_event: ptr::null_mut(),
            gesture: ptr::null_mut(),
            press: ptr::null_mut(),
            release: ptr::null_mut(),
            drag: ptr::null_mut(),
            tick: ptr::null_mut(),
            formatter: ptr::null_mut(),
            sink: Box::into_raw(Box::default()),
            size,
            sent_cursor: None,
            sent_scrollbar: None,
        };
        // Se um passo falha, o `Drop` libera os anteriores: ele pula os nulos.
        // SAFETY: cada chamada recebe um ponteiro válido para o campo que
        // preenche e o alocador padrão (NULL).
        unsafe {
            ok(
                ffi::ghostty_terminal_new(ptr::null(), &mut screen.term, size.cols, size.rows),
                "terminal_new",
            )?;
            ok(
                ffi::ghostty_render_state_new(ptr::null(), &mut screen.render),
                "render_state_new",
            )?;
            ok(
                ffi::ghostty_render_state_row_iterator_new(ptr::null(), &mut screen.rows),
                "row_iterator_new",
            )?;
            ok(
                ffi::ghostty_render_state_row_cells_new(ptr::null(), &mut screen.cells),
                "row_cells_new",
            )?;
            ok(
                ffi::ghostty_key_encoder_new(ptr::null(), &mut screen.encoder),
                "key_encoder_new",
            )?;
            ok(
                ffi::ghostty_key_event_new(ptr::null(), &mut screen.event),
                "key_event_new",
            )?;
            ok(
                ffi::ghostty_mouse_encoder_new(ptr::null(), &mut screen.mouse),
                "mouse_encoder_new",
            )?;
            ok(
                ffi::ghostty_mouse_event_new(ptr::null(), &mut screen.mouse_event),
                "mouse_event_new",
            )?;
            ok(
                ffi::ghostty_selection_gesture_new(ptr::null(), &mut screen.gesture),
                "selection_gesture_new",
            )?;
            for (event, kind) in [
                (&mut screen.press, ffi::GESTURE_EVENT_PRESS),
                (&mut screen.release, ffi::GESTURE_EVENT_RELEASE),
                (&mut screen.drag, ffi::GESTURE_EVENT_DRAG),
                (&mut screen.tick, ffi::GESTURE_EVENT_AUTOSCROLL_TICK),
            ] {
                ok(
                    ffi::ghostty_selection_gesture_event_new(ptr::null(), event, kind),
                    "selection_gesture_event_new",
                )?;
            }
            ok(
                ffi::ghostty_formatter_terminal_new(
                    ptr::null(),
                    &mut screen.formatter,
                    screen.term,
                ),
                "formatter_terminal_new",
            )?;
            // O texto que o Ghostty copia: linhas quebradas pelo terminal
            // juntadas, espaço do fim cortado (`formatter.h`).
            let yes = true;
            for option in [ffi::FORMATTER_OPT_UNWRAP, ffi::FORMATTER_OPT_TRIM] {
                ok(
                    ffi::ghostty_formatter_set(
                        screen.formatter,
                        option,
                        (&raw const yes).cast::<c_void>(),
                    ),
                    "formatter_set",
                )?;
            }
            // Sem teto de bytes, senão o padrão (uma página) corta antes das
            // linhas.
            let unlimited = usize::MAX;
            ok(
                ffi::ghostty_terminal_set(
                    screen.term,
                    ffi::TERMINAL_OPT_SCROLLBACK_MAX_BYTES,
                    (&raw const unlimited).cast::<c_void>(),
                ),
                "opt_scrollback_max_bytes",
            )?;
            sink::install(screen.term, screen.sink)
                .map_err(|what| ScreenError::Engine(format!("ghostty_terminal_set: {what}")))?;
        }
        screen.limit_scrollback()?;
        Ok(screen)
    }

    /// O teto depende da largura: refeito a cada resize.
    fn limit_scrollback(&mut self) -> Result<(), ScreenError> {
        let lines = scrollback_limit(self.size.cols);
        // SAFETY: term vivo; SCROLLBACK_MAX_LINES lê um size_t.
        ok(
            unsafe {
                ffi::ghostty_terminal_set(
                    self.term,
                    ffi::TERMINAL_OPT_SCROLLBACK_MAX_LINES,
                    (&raw const lines).cast::<c_void>(),
                )
            },
            "opt_scrollback_max_lines",
        )
    }

    fn sink(&mut self) -> &mut Sink {
        // SAFETY: `sink` vem de `Box::into_raw` e só é solto no `Drop`; o
        // Ghostty só o usa dentro de um `vt_write`, e nenhum está em curso
        // enquanto temos `&mut self`.
        unsafe { &mut *self.sink }
    }

    fn scrollbar(&self) -> Scrollbar {
        let mut sb = ffi::TerminalScrollbar::default();
        // SAFETY: term vivo; DATA_SCROLLBAR escreve um GhosttyTerminalScrollbar.
        unsafe {
            ffi::ghostty_terminal_get(
                self.term,
                ffi::TERMINAL_DATA_SCROLLBAR,
                (&raw mut sb).cast::<c_void>(),
            )
        };
        Scrollbar {
            total: sb.total,
            offset: sb.offset,
            len: sb.len,
        }
    }

    fn selection(&self) -> Option<ffi::Selection> {
        let mut sel = ffi::Selection::NONE;
        // SAFETY: term vivo; DATA_SELECTION escreve um GhosttySelection.
        let r = unsafe {
            ffi::ghostty_terminal_get(
                self.term,
                ffi::TERMINAL_DATA_SELECTION,
                (&raw mut sel).cast::<c_void>(),
            )
        };
        (r == ffi::SUCCESS).then_some(sel)
    }

    fn set_selection(&mut self, sel: Option<&ffi::Selection>) {
        let value = sel.map_or(ptr::null(), |s| ptr::from_ref(s).cast::<c_void>());
        // SAFETY: term vivo; o Ghostty copia a seleção na hora, e NULL a limpa.
        unsafe { ffi::ghostty_terminal_set(self.term, ffi::TERMINAL_OPT_SELECTION, value) };
    }

    fn format_selection(&mut self, buf: &mut [u8]) -> Result<usize, usize> {
        let mut written: usize = 0;
        // SAFETY: `buf` válido com o tamanho passado; `written` é a saída.
        let r = unsafe {
            ffi::ghostty_formatter_format_buf(
                self.formatter,
                buf.as_mut_ptr(),
                buf.len(),
                &mut written,
            )
        };
        sized(r, written)
    }

    fn update(&mut self) {
        // Só falha sem memória; a tela segue com o quadro anterior.
        // SAFETY: render e term vivos, de `new`.
        let _ = unsafe { ffi::ghostty_render_state_update(self.render, self.term) };
    }

    fn dirty(&mut self) -> c_int {
        let mut dirty = ffi::DIRTY_FULL;
        // SAFETY: DATA_DIRTY escreve um GhosttyRenderStateDirty (int).
        let r = unsafe {
            ffi::ghostty_render_state_get(
                self.render,
                ffi::RS_DATA_DIRTY,
                (&raw mut dirty).cast::<c_void>(),
            )
        };
        if r == ffi::SUCCESS {
            dirty
        } else {
            ffi::DIRTY_FULL
        }
    }

    fn start_rows(&mut self) -> bool {
        // SAFETY: DATA_ROW_ITERATOR preenche o iterador que passamos.
        let r = unsafe {
            ffi::ghostty_render_state_get(
                self.render,
                ffi::RS_DATA_ROW_ITERATOR,
                (&raw mut self.rows).cast::<c_void>(),
            )
        };
        r == ffi::SUCCESS
    }

    fn all_rows(&mut self) -> Vec<Row> {
        let mut out = Vec::with_capacity(usize::from(self.size.rows));
        if !self.start_rows() {
            return out;
        }
        let mut y: u16 = 0;
        // SAFETY: iterador posicionado por `start_rows`.
        while unsafe { ffi::ghostty_render_state_row_iterator_next(self.rows) } {
            out.push(self.read_row(y));
            y = y.saturating_add(1);
        }
        out
    }

    fn dirty_rows(&mut self) -> Vec<Row> {
        let mut out = Vec::new();
        if !self.start_rows() {
            return out;
        }
        let mut y: u16 = 0;
        // SAFETY: iterador posicionado por `start_rows`; `y` é a saída.
        while unsafe { ffi::ghostty_render_state_row_iterator_next_dirty(self.rows, &mut y) } {
            out.push(self.read_row(y));
        }
        out
    }

    fn read_row(&mut self, y: u16) -> Row {
        let selection = self.row_selection();
        let continued = self.row_continued();
        Row {
            y,
            cells: self.read_cells(),
            selection,
            continued,
        }
    }

    fn row_continued(&mut self) -> bool {
        let mut raw: ffi::GhosttyRow = 0;
        let mut continued = false;
        // SAFETY: ROW_DATA_RAW escreve um GhosttyRow (u64), e
        // ROW_WRAP_CONTINUATION, um bool.
        unsafe {
            if ffi::ghostty_render_state_row_get(
                self.rows,
                ffi::ROW_DATA_RAW,
                (&raw mut raw).cast::<c_void>(),
            ) != ffi::SUCCESS
            {
                return false;
            }
            ffi::ghostty_row_get(
                raw,
                ffi::ROW_WRAP_CONTINUATION,
                (&raw mut continued).cast::<c_void>(),
            );
        }
        continued
    }

    fn row_selection(&mut self) -> Option<[u16; 2]> {
        let mut sel = ffi::RowSelection {
            size: size_of::<ffi::RowSelection>(),
            start_x: 0,
            end_x: 0,
        };
        // SAFETY: ROW_DATA_SELECTION escreve um GhosttyRenderStateRowSelection;
        // fora da seleção devolve NO_VALUE.
        let r = unsafe {
            ffi::ghostty_render_state_row_get(
                self.rows,
                ffi::ROW_DATA_SELECTION,
                (&raw mut sel).cast::<c_void>(),
            )
        };
        (r == ffi::SUCCESS).then_some([sel.start_x, sel.end_x])
    }

    /// As células da linha em que `self.rows` está.
    fn read_cells(&mut self) -> Vec<Cell> {
        let mut cells = Vec::with_capacity(usize::from(self.size.cols));
        // SAFETY: ROW_DATA_CELLS preenche o handle de células que passamos.
        let r = unsafe {
            ffi::ghostty_render_state_row_get(
                self.rows,
                ffi::ROW_DATA_CELLS,
                (&raw mut self.cells).cast::<c_void>(),
            )
        };
        if r != ffi::SUCCESS {
            return cells;
        }
        // SAFETY: handle de células posicionado acima.
        while unsafe { ffi::ghostty_render_state_row_cells_next(self.cells) } {
            if let Some(cell) = self.read_cell() {
                cells.push(cell);
            }
        }
        cells
    }

    /// `None` para a cauda de um caractere largo: a coluna dela já está no
    /// `width` da célula anterior.
    fn read_cell(&mut self) -> Option<Cell> {
        let mut raw: ffi::GhosttyCell = 0;
        // SAFETY: CELLS_DATA_RAW escreve um GhosttyCell (u64).
        let r = unsafe {
            ffi::ghostty_render_state_row_cells_get(
                self.cells,
                ffi::CELLS_DATA_RAW,
                (&raw mut raw).cast::<c_void>(),
            )
        };
        if r != ffi::SUCCESS {
            // Célula ilegível ocupa a coluna em branco, para as seguintes não
            // andarem para a esquerda.
            return Some(Cell {
                text: String::new(),
                width: 1,
                style: Style::default(),
            });
        }
        let wide = cell_int(raw, ffi::CELL_DATA_WIDE);
        if wide == ffi::CELL_WIDE_SPACER_TAIL {
            return None;
        }
        let width = if wide == ffi::CELL_WIDE_WIDE { 2 } else { 1 };
        // A cabeça espaçadora (fim de linha antes de um largo que quebrou) não
        // tem texto; conta como uma coluna em branco.
        let text = if wide == ffi::CELL_WIDE_SPACER_HEAD {
            String::new()
        } else {
            self.read_text()
        };

        let mut style = self.read_style();
        if style.bg.is_none() {
            // Célula só de fundo (apagada com cor de fundo): a cor está no
            // conteúdo da célula, não no estilo.
            style.bg = match cell_int(raw, ffi::CELL_DATA_CONTENT_TAG) {
                ffi::CELL_CONTENT_BG_COLOR_PALETTE => {
                    let mut idx: u8 = 0;
                    // SAFETY: COLOR_PALETTE escreve um GhosttyColorPaletteIndex (u8).
                    let r = unsafe {
                        ffi::ghostty_cell_get(
                            raw,
                            ffi::CELL_DATA_COLOR_PALETTE,
                            (&raw mut idx).cast::<c_void>(),
                        )
                    };
                    (r == ffi::SUCCESS).then_some(Color::Palette(idx))
                }
                ffi::CELL_CONTENT_BG_COLOR_RGB => {
                    let mut rgb = ffi::ColorRgb::default();
                    // SAFETY: COLOR_RGB escreve um GhosttyColorRgb.
                    let r = unsafe {
                        ffi::ghostty_cell_get(
                            raw,
                            ffi::CELL_DATA_COLOR_RGB,
                            (&raw mut rgb).cast::<c_void>(),
                        )
                    };
                    (r == ffi::SUCCESS).then_some(Color::Rgb(RgbHex([rgb.r, rgb.g, rgb.b])))
                }
                _ => None,
            };
        }
        Some(Cell { text, width, style })
    }

    fn read_text(&mut self) -> String {
        let bytes = grow::<64>(|buf| self.grapheme_utf8(buf));
        String::from_utf8(bytes)
            .unwrap_or_else(|e| String::from_utf8_lossy(e.as_bytes()).into_owned())
    }

    fn grapheme_utf8(&mut self, out: &mut [u8]) -> Result<usize, usize> {
        let mut buf = ffi::GhosttyBuffer {
            ptr: out.as_mut_ptr(),
            cap: out.len(),
            len: 0,
        };
        // SAFETY: o buffer aponta para `out`, com `cap` do tamanho dele.
        let r = unsafe {
            ffi::ghostty_render_state_row_cells_get(
                self.cells,
                ffi::CELLS_DATA_GRAPHEMES_UTF8,
                (&raw mut buf).cast::<c_void>(),
            )
        };
        sized(r, buf.len)
    }

    fn read_style(&mut self) -> Style {
        let none = ffi::StyleColor {
            tag: 0,
            value: ffi::StyleColorValue {
                rgb: ffi::ColorRgb::default(),
            },
        };
        let mut raw = ffi::Style {
            fg_color: none,
            bg_color: none,
            underline_color: none,
            flags: 0,
            reserved: 0,
        };
        // SAFETY: CELLS_DATA_STYLE escreve um GhosttyStyle.
        let r = unsafe {
            ffi::ghostty_render_state_row_cells_get(
                self.cells,
                ffi::CELLS_DATA_STYLE,
                (&raw mut raw).cast::<c_void>(),
            )
        };
        if r != ffi::SUCCESS {
            return Style::default();
        }
        let f = raw.flags;
        Style {
            fg: color(raw.fg_color),
            bg: color(raw.bg_color),
            bold: f & ffi::STYLE_BOLD != 0,
            dim: f & ffi::STYLE_FAINT != 0,
            italic: f & ffi::STYLE_ITALIC != 0,
            underline: f & ffi::STYLE_UNDERLINE_MASK != 0,
            strike: f & ffi::STYLE_STRIKETHROUGH != 0,
            inverse: f & ffi::STYLE_INVERSE != 0,
        }
    }

    fn cursor(&mut self) -> Cursor {
        let mut c = ffi::RenderStateCursor {
            size: size_of::<ffi::RenderStateCursor>(),
            viewport_has_value: false,
            viewport_x: 0,
            viewport_y: 0,
            wide_tail: false,
            visible: false,
            blinking: false,
            password_input: false,
            visual_style: ffi::CURSOR_BLOCK,
        };
        // SAFETY: DATA_CURSOR escreve até `c.size` bytes de um
        // GhosttyRenderStateCursor.
        let r = unsafe {
            ffi::ghostty_render_state_get(
                self.render,
                ffi::RS_DATA_CURSOR,
                (&raw mut c).cast::<c_void>(),
            )
        };
        if r != ffi::SUCCESS {
            return Cursor {
                row: 0,
                col: 0,
                visible: false,
                shape: CursorShape::Block,
            };
        }
        let (row, col) = if c.viewport_has_value {
            (c.viewport_y, c.viewport_x)
        } else {
            (0, 0)
        };
        Cursor {
            row,
            col,
            visible: c.visible && c.viewport_has_value,
            shape: match c.visual_style {
                ffi::CURSOR_BAR => CursorShape::Bar,
                ffi::CURSOR_UNDERLINE => CursorShape::Underline,
                _ => CursorShape::Block,
            },
        }
    }

    fn frame(
        &self,
        kind: FrameKind,
        rows: &[Row],
        cursor: Cursor,
        scrollbar: Option<Scrollbar>,
    ) -> Frame {
        Frame {
            kind,
            cols: self.size.cols,
            rows: self.size.rows,
            cursor,
            scrollbar,
            lines: rows
                .iter()
                .map(|row| {
                    let mut l = line::line(row.y, &row.cells);
                    l.selection = row.selection;
                    l
                })
                .collect(),
        }
    }

    fn encode(&mut self, buf: &mut [u8]) -> Result<usize, usize> {
        let mut written: usize = 0;
        // SAFETY: `buf` válido com o tamanho passado; `written` é a saída.
        let r = unsafe {
            ffi::ghostty_key_encoder_encode(
                self.encoder,
                self.event,
                buf.as_mut_ptr(),
                buf.len(),
                &mut written,
            )
        };
        sized(r, written)
    }
}

impl Screen for GhosttyScreen {
    fn feed(&mut self, bytes: &[u8]) {
        // SAFETY: term vivo; o slice vale durante a chamada. Os callbacks
        // escrevem no `sink` só dentro dela.
        unsafe { ffi::ghostty_terminal_vt_write(self.term, bytes.as_ptr(), bytes.len()) };
    }

    fn take_responses(&mut self) -> Vec<u8> {
        std::mem::take(&mut self.sink().replies)
    }

    fn resize(&mut self, size: Size) -> Result<(), ScreenError> {
        check_size(size)?;
        // O tamanho da célula em pixels só serve a imagens e a relatórios de
        // tamanho, que a tela não tem como saber; 0 diz "desconhecido".
        // SAFETY: term vivo.
        ok(
            unsafe { ffi::ghostty_terminal_resize(self.term, size.cols, size.rows, 0, 0) },
            "terminal_resize",
        )?;
        self.size = size;
        self.limit_scrollback()
    }

    fn size(&self) -> Size {
        self.size
    }

    fn full_frame(&mut self) -> Frame {
        self.update();
        let rows = self.all_rows();
        let cursor = self.cursor();
        let scrollbar = self.scrollbar();
        self.frame(FrameKind::Full, &rows, cursor, Some(scrollbar))
    }

    fn take_delta(&mut self) -> Option<Frame> {
        self.update();
        let dirty = self.dirty();
        let cursor = self.cursor();
        let scrollbar = self.scrollbar();
        let scrolled = self.sent_scrollbar != Some(scrollbar);
        // Cursor e barra são comparados aqui, e não pelo sujo do Ghostty:
        // piscar ou só andar não marca linha, e o histórico cresce sem mudar a
        // vista, mas a UI tem de saber dos dois.
        if dirty == ffi::DIRTY_FALSE && self.sent_cursor == Some(cursor) && !scrolled {
            return None;
        }
        let kind = if dirty == ffi::DIRTY_FULL {
            FrameKind::Full
        } else {
            FrameKind::Delta
        };
        let rows = match kind {
            FrameKind::Full => self.all_rows(),
            FrameKind::Delta => self.dirty_rows(),
        };
        // SAFETY: render vivo.
        unsafe { ffi::ghostty_render_state_clean(self.render) };
        self.sent_cursor = Some(cursor);
        self.sent_scrollbar = Some(scrollbar);
        Some(self.frame(kind, &rows, cursor, scrolled.then_some(scrollbar)))
    }

    fn rows_text(&mut self) -> Vec<String> {
        self.update();
        self.all_rows()
            .iter()
            .map(|row| line::text(&row.cells))
            .collect()
    }

    fn encode_key(&mut self, press: &KeyPress) -> Vec<u8> {
        let spec = key::spec(press);
        // SAFETY: encoder, event e term vivos. O texto do evento aponta para
        // `spec.text`, que vive até o fim da função, e é limpo antes de sair: o
        // Ghostty não copia esse texto.
        unsafe {
            // Os modos (cursor de aplicação, kitty…) mudam com o que o programa
            // escreve; lidos a cada tecla.
            ffi::ghostty_key_encoder_set_from_terminal(self.encoder, self.term);
            // Option como Alt, como no SwiftTerm do app de hoje. Tem de vir
            // depois do `set_from_terminal`, que o desliga.
            let option_as_alt: c_int = ffi::OPTION_AS_ALT_TRUE;
            ffi::ghostty_key_encoder_set(
                self.encoder,
                ffi::KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT,
                (&raw const option_as_alt).cast::<c_void>(),
            );
            ffi::ghostty_key_event_set_action(self.event, ffi::KEY_ACTION_PRESS);
            ffi::ghostty_key_event_set_key(self.event, spec.key);
            ffi::ghostty_key_event_set_mods(self.event, spec.mods);
            ffi::ghostty_key_event_set_consumed_mods(self.event, spec.consumed);
            ffi::ghostty_key_event_set_unshifted_codepoint(self.event, spec.unshifted);
            ffi::ghostty_key_event_set_utf8(
                self.event,
                ffi::GhosttyString {
                    ptr: spec.text.as_ptr(),
                    len: spec.text.len(),
                },
            );
        }

        let out = grow::<128>(|buf| self.encode(buf));

        // SAFETY: event vivo; comprimento zero limpa o texto sem ler o ponteiro.
        unsafe {
            ffi::ghostty_key_event_set_utf8(
                self.event,
                ffi::GhosttyString {
                    ptr: ptr::null(),
                    len: 0,
                },
            );
        }
        out
    }

    fn bracketed_paste(&self) -> bool {
        let mut query = ffi::TerminalModeConfig {
            mode: ffi::MODE_BRACKETED_PASTE,
            value: false,
        };
        // SAFETY: term vivo; DATA_MODE lê e escreve um GhosttyTerminalModeConfig.
        let r = unsafe {
            ffi::ghostty_terminal_get(
                self.term,
                ffi::TERMINAL_DATA_MODE,
                (&raw mut query).cast::<c_void>(),
            )
        };
        r == ffi::SUCCESS && query.value
    }

    fn scroll(&mut self, to: Scroll) {
        let (tag, delta) = match to {
            Scroll::Rows(n) => (ffi::SCROLL_VIEWPORT_DELTA, n as isize),
            Scroll::Top => (ffi::SCROLL_VIEWPORT_TOP, 0),
            Scroll::Bottom => (ffi::SCROLL_VIEWPORT_BOTTOM, 0),
        };
        let behavior = ffi::ScrollViewport {
            tag,
            value: ffi::ScrollViewportValue { delta },
        };
        // SAFETY: term vivo; a etiqueta é uma das do cabeçalho.
        unsafe { ffi::ghostty_terminal_scroll_viewport(self.term, behavior) };
    }

    fn pointer(&mut self, event: &Pointer) -> Vec<u8> {
        self.handle_pointer(event)
    }

    fn select_all(&mut self) {
        let mut sel = ffi::Selection::NONE;
        // SAFETY: term vivo; a saída é um GhosttySelection.
        if unsafe { ffi::ghostty_terminal_select_all(self.term, &mut sel) } == ffi::SUCCESS {
            self.set_selection(Some(&sel));
        }
    }

    fn selection_text(&mut self) -> Option<String> {
        let sel = self.selection()?;
        // SAFETY: formatter vivo; ele copia a seleção, cujas referências valem
        // porque nada mudou o terminal desde a leitura.
        unsafe {
            ffi::ghostty_formatter_set(
                self.formatter,
                ffi::FORMATTER_OPT_SELECTION,
                (&raw const sel).cast::<c_void>(),
            )
        };
        let bytes = grow::<256>(|buf| self.format_selection(buf));
        // Sem a seleção guardada, que vira referência solta na próxima escrita.
        // SAFETY: formatter vivo; NULL limpa.
        unsafe {
            ffi::ghostty_formatter_set(self.formatter, ffi::FORMATTER_OPT_SELECTION, ptr::null())
        };
        Some(String::from_utf8_lossy(&bytes).into_owned())
    }

    fn clipboard_answer(&mut self, text: &str) -> Vec<u8> {
        self.sink().answer_clipboard(text)
    }

    fn link_at(&mut self, col: u16, row: u16) -> Option<LinkHit> {
        self.link_under(col, row)
    }

    fn take_effects(&mut self) -> Vec<Effect> {
        std::mem::take(&mut self.sink().effects)
    }
}

impl Drop for GhosttyScreen {
    fn drop(&mut self) {
        // SAFETY: cada ponteiro é nulo ou veio do `_new` correspondente e não
        // foi liberado; `sink` veio de `Box::into_raw`. O gesto sai antes do
        // terminal, porque solta referências nele; o terminal sai antes do
        // `sink`, porque guarda o endereço.
        unsafe {
            if !self.formatter.is_null() {
                ffi::ghostty_formatter_free(self.formatter);
            }
            for event in [self.press, self.release, self.drag, self.tick] {
                if !event.is_null() {
                    ffi::ghostty_selection_gesture_event_free(event);
                }
            }
            if !self.gesture.is_null() {
                ffi::ghostty_selection_gesture_free(self.gesture, self.term);
            }
            if !self.mouse_event.is_null() {
                ffi::ghostty_mouse_event_free(self.mouse_event);
            }
            if !self.mouse.is_null() {
                ffi::ghostty_mouse_encoder_free(self.mouse);
            }
            if !self.event.is_null() {
                ffi::ghostty_key_event_free(self.event);
            }
            if !self.encoder.is_null() {
                ffi::ghostty_key_encoder_free(self.encoder);
            }
            if !self.cells.is_null() {
                ffi::ghostty_render_state_row_cells_free(self.cells);
            }
            if !self.rows.is_null() {
                ffi::ghostty_render_state_row_iterator_free(self.rows);
            }
            if !self.render.is_null() {
                ffi::ghostty_render_state_free(self.render);
            }
            if !self.term.is_null() {
                ffi::ghostty_terminal_free(self.term);
            }
            drop(Box::from_raw(self.sink));
        }
    }
}

/// Preenche um buffer na pilha e, se não couber, de novo no tamanho que o
/// Ghostty pediu: na pilha porque roda por célula a cada quadro, e um grafema
/// longo (emoji com modificadores) passa do tamanho comum.
fn grow<const N: usize>(mut fill: impl FnMut(&mut [u8]) -> Result<usize, usize>) -> Vec<u8> {
    let mut stack = [0u8; N];
    match fill(&mut stack) {
        Ok(n) => stack[..n.min(N)].to_vec(),
        Err(needed) => {
            let mut heap = vec![0u8; needed];
            match fill(&mut heap) {
                Ok(n) => {
                    heap.truncate(n);
                    heap
                }
                Err(_) => Vec::new(),
            }
        }
    }
}

/// O resultado de uma escrita em buffer do Ghostty no formato do [`grow`]:
/// `Err` com o tamanho que ele pediu quando não coube. Outro erro é texto
/// vazio.
fn sized(result: ffi::GhosttyResult, written: usize) -> Result<usize, usize> {
    match result {
        ffi::SUCCESS => Ok(written),
        ffi::OUT_OF_SPACE => Err(written),
        _ => Ok(0),
    }
}

fn cell_int(raw: ffi::GhosttyCell, data: c_int) -> c_int {
    let mut out: c_int = 0;
    // SAFETY: WIDE e CONTENT_TAG escrevem enums C (int).
    unsafe { ffi::ghostty_cell_get(raw, data, (&raw mut out).cast::<c_void>()) };
    out
}

fn color(c: ffi::StyleColor) -> Option<Color> {
    // SAFETY: o campo lido do union é o que a `tag` diz estar preenchido.
    match c.tag {
        ffi::STYLE_COLOR_PALETTE => Some(Color::Palette(unsafe { c.value.palette })),
        ffi::STYLE_COLOR_RGB => {
            let rgb = unsafe { c.value.rgb };
            Some(Color::Rgb(RgbHex([rgb.r, rgb.g, rgb.b])))
        }
        _ => None,
    }
}

fn check_size(size: Size) -> Result<(), ScreenError> {
    if size.cols == 0 || size.rows == 0 {
        return Err(ScreenError::InvalidSize {
            cols: size.cols,
            rows: size.rows,
        });
    }
    Ok(())
}

fn ok(result: ffi::GhosttyResult, what: &str) -> Result<(), ScreenError> {
    if result == ffi::SUCCESS {
        Ok(())
    } else {
        Err(ScreenError::Engine(format!(
            "ghostty_{what}: código {result}"
        )))
    }
}
