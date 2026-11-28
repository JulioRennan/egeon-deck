//! Declarações da API C do libghostty-vt 1.0.1 que este crate usa.
//!
//! Escritas à mão a partir de `include/ghostty/vt/*.h` da versão fixada no
//! `build.rs`, em vez de geradas: o bindgen exigiria libclang no build, e o
//! subconjunto é pequeno. Trocar de versão é reler estes cabeçalhos. A ABI C é
//! estável desde a 1.0 (`vt.h`, seção "stability").
//!
//! Enum C sem tipo fixo é `int` no clang; aqui viram `c_int`.

use std::ffi::{c_int, c_void};
use std::marker::{PhantomData, PhantomPinned};

macro_rules! opaque {
    ($($name:ident),*) => {$(
        #[repr(C)]
        pub struct $name {
            _data: [u8; 0],
            _marker: PhantomData<(*mut u8, PhantomPinned)>,
        }
    )*};
}

opaque!(
    TerminalImpl,
    RenderStateImpl,
    RowIteratorImpl,
    RowCellsImpl,
    KeyEncoderImpl,
    KeyEventImpl,
    MouseEncoderImpl,
    MouseEventImpl,
    GestureImpl,
    GestureEventImpl,
    FormatterImpl,
    AllocatorImpl
);

pub type Terminal = *mut TerminalImpl;
pub type RenderState = *mut RenderStateImpl;
pub type RowIterator = *mut RowIteratorImpl;
pub type RowCells = *mut RowCellsImpl;
pub type KeyEncoder = *mut KeyEncoderImpl;
pub type KeyEvent = *mut KeyEventImpl;
pub type MouseEncoder = *mut MouseEncoderImpl;
pub type MouseEvent = *mut MouseEventImpl;
pub type Gesture = *mut GestureImpl;
pub type GestureEvent = *mut GestureEventImpl;
pub type Formatter = *mut FormatterImpl;
/// Só passamos `NULL` (alocador padrão); o tipo existe para a assinatura.
pub type Allocator = *const AllocatorImpl;

pub type GhosttyResult = c_int;
pub const SUCCESS: GhosttyResult = 0;
pub const OUT_OF_SPACE: GhosttyResult = -3;

// terminal.h — GhosttyTerminalOption
pub const TERMINAL_OPT_USERDATA: c_int = 1;
pub const TERMINAL_OPT_WRITE_PTY: c_int = 2;
pub const TERMINAL_OPT_BELL: c_int = 3;
pub const TERMINAL_OPT_SELECTION: c_int = 22;
pub const TERMINAL_OPT_CLIPBOARD_WRITE: c_int = 27;
pub const TERMINAL_OPT_SCROLLBACK_MAX_BYTES: c_int = 28;
pub const TERMINAL_OPT_SCROLLBACK_MAX_LINES: c_int = 29;
pub const TERMINAL_OPT_CLIPBOARD_READ: c_int = 39;

// terminal.h — GhosttyTerminalData
pub const TERMINAL_DATA_ACTIVE_SCREEN: c_int = 6;
pub const TERMINAL_DATA_SCROLLBAR: c_int = 9;
pub const TERMINAL_DATA_MOUSE_TRACKING: c_int = 11;
pub const TERMINAL_DATA_SELECTION: c_int = 31;
pub const TERMINAL_DATA_MODE: c_int = 37;

// terminal.h — GhosttyTerminalScreen
pub const TERMINAL_SCREEN_ALTERNATE: c_int = 1;

// terminal.h — GhosttyTerminalScrollViewportTag
pub const SCROLL_VIEWPORT_TOP: c_int = 0;
pub const SCROLL_VIEWPORT_BOTTOM: c_int = 1;
pub const SCROLL_VIEWPORT_DELTA: c_int = 2;

// point.h — GhosttyPointTag
pub const POINT_TAG_VIEWPORT: c_int = 1;

// terminal.h — GhosttyClipboardWriteResult, GhosttyClipboardReadResult
pub const CLIPBOARD_WRITE_SUCCESS: c_int = 0;
pub const CLIPBOARD_READ_UNSUPPORTED: c_int = 2;

// selection.h — tipos de evento, opções e dados do gesto
pub const GESTURE_EVENT_PRESS: c_int = 0;
pub const GESTURE_EVENT_RELEASE: c_int = 1;
pub const GESTURE_EVENT_DRAG: c_int = 2;
pub const GESTURE_EVENT_AUTOSCROLL_TICK: c_int = 3;
pub const GESTURE_OPT_REF: c_int = 1;
pub const GESTURE_OPT_POSITION: c_int = 2;
pub const GESTURE_OPT_REPEAT_DISTANCE: c_int = 3;
pub const GESTURE_OPT_TIME_NS: c_int = 4;
pub const GESTURE_OPT_REPEAT_INTERVAL_NS: c_int = 5;
pub const GESTURE_OPT_GEOMETRY: c_int = 9;
pub const GESTURE_OPT_VIEWPORT: c_int = 10;
pub const GESTURE_DATA_AUTOSCROLL: c_int = 3;
pub const GESTURE_AUTOSCROLL_UP: c_int = 1;
pub const GESTURE_AUTOSCROLL_DOWN: c_int = 2;

// mouse/encoder.h e mouse/event.h
pub const MOUSE_ENCODER_OPT_SIZE: c_int = 3;
pub const MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED: c_int = 4;
pub const MOUSE_ACTION_PRESS: c_int = 0;
pub const MOUSE_ACTION_RELEASE: c_int = 1;
pub const MOUSE_ACTION_MOTION: c_int = 2;
pub const MOUSE_BUTTON_LEFT: c_int = 1;
pub const MOUSE_BUTTON_RIGHT: c_int = 2;
pub const MOUSE_BUTTON_MIDDLE: c_int = 3;
pub const MOUSE_BUTTON_FOUR: c_int = 4;
pub const MOUSE_BUTTON_FIVE: c_int = 5;

// formatter.h — GhosttyFormatterOption
pub const FORMATTER_OPT_UNWRAP: c_int = 2;
pub const FORMATTER_OPT_TRIM: c_int = 3;
pub const FORMATTER_OPT_SELECTION: c_int = 4;

// modes.h — `ghostty_mode_new(2004, false)`: modo DEC, bit 15 (ANSI) desligado.
pub const MODE_BRACKETED_PASTE: u16 = 2004;

/// `GhosttyTerminalModeConfig`, de layout congelado pelo cabeçalho.
#[repr(C)]
pub struct TerminalModeConfig {
    pub mode: u16,
    pub value: bool,
}

pub type WritePtyFn =
    unsafe extern "C" fn(terminal: Terminal, userdata: *mut c_void, data: *const u8, len: usize);
pub type BellFn = unsafe extern "C" fn(terminal: Terminal, userdata: *mut c_void);
pub type ClipboardWriteFn =
    unsafe extern "C" fn(terminal: Terminal, userdata: *mut c_void, write: *const ClipboardWrite);
pub type ClipboardReadFn =
    unsafe extern "C" fn(terminal: Terminal, userdata: *mut c_void, read: *const ClipboardRead);
pub type ClipboardWriteReplyFn =
    unsafe extern "C" fn(write: *const ClipboardWrite, reply: *const ClipboardWriteReply);
pub type ClipboardReadReplyFn =
    unsafe extern "C" fn(read: *const ClipboardRead, reply: *const ClipboardReadReply);

// render.h — GhosttyRenderStateData
pub const RS_DATA_DIRTY: c_int = 3;
pub const RS_DATA_ROW_ITERATOR: c_int = 4;
pub const RS_DATA_CURSOR: c_int = 18;

// render.h — GhosttyRenderStateDirty
pub const DIRTY_FALSE: c_int = 0;
pub const DIRTY_FULL: c_int = 2;

// render.h — GhosttyRenderStateRowData
pub const ROW_DATA_RAW: c_int = 2;
pub const ROW_DATA_CELLS: c_int = 3;
pub const ROW_DATA_SELECTION: c_int = 4;

// render.h — GhosttyRenderStateRowCellsData
pub const CELLS_DATA_RAW: c_int = 1;
pub const CELLS_DATA_STYLE: c_int = 2;
pub const CELLS_DATA_GRAPHEMES_UTF8: c_int = 9;

// screen.h — GhosttyCellData, GhosttyCellContentTag, GhosttyCellWide
pub const CELL_DATA_CONTENT_TAG: c_int = 2;
pub const CELL_DATA_WIDE: c_int = 3;
pub const CELL_DATA_COLOR_PALETTE: c_int = 10;
pub const CELL_DATA_COLOR_RGB: c_int = 11;
pub const CELL_CONTENT_BG_COLOR_PALETTE: c_int = 2;
pub const CELL_CONTENT_BG_COLOR_RGB: c_int = 3;
pub const CELL_WIDE_WIDE: c_int = 1;
pub const CELL_WIDE_SPACER_TAIL: c_int = 2;
pub const CELL_WIDE_SPACER_HEAD: c_int = 3;

// types.h — GhosttyCursorStyle
pub const CURSOR_BAR: c_int = 0;
pub const CURSOR_BLOCK: c_int = 1;
pub const CURSOR_UNDERLINE: c_int = 2;

// style.h — GhosttyStyleColorTag e bits de GhosttyStyleFlags
pub const STYLE_COLOR_PALETTE: u8 = 1;
pub const STYLE_COLOR_RGB: u8 = 2;
pub const STYLE_BOLD: u16 = 1 << 0;
pub const STYLE_ITALIC: u16 = 1 << 1;
pub const STYLE_FAINT: u16 = 1 << 2;
pub const STYLE_INVERSE: u16 = 1 << 4;
pub const STYLE_STRIKETHROUGH: u16 = 1 << 6;
pub const STYLE_UNDERLINE_MASK: u16 = 0x7 << 8;

// key/event.h — GhosttyKeyAction e bits de GhosttyMods
pub const KEY_ACTION_PRESS: c_int = 1;
pub const MODS_SHIFT: u16 = 1 << 0;
pub const MODS_CTRL: u16 = 1 << 1;
pub const MODS_ALT: u16 = 1 << 2;
pub const MODS_SUPER: u16 = 1 << 3;

// key/encoder.h — GhosttyKeyEncoderOption e GhosttyOptionAsAlt
pub const KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT: c_int = 7;
pub const OPTION_AS_ALT_TRUE: c_int = 1;

pub type GhosttyCell = u64;
pub type GhosttyRow = u64;

// screen.h — GhosttyRowData
pub const ROW_WRAP_CONTINUATION: c_int = 2;

#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct ColorRgb {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union StyleColorValue {
    pub palette: u8,
    pub rgb: ColorRgb,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct StyleColor {
    pub tag: u8,
    pub value: StyleColorValue,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Style {
    pub fg_color: StyleColor,
    pub bg_color: StyleColor,
    pub underline_color: StyleColor,
    pub flags: u16,
    pub reserved: u16,
}

#[repr(C)]
pub struct GhosttyString {
    pub ptr: *const u8,
    pub len: usize,
}

#[repr(C)]
pub struct GhosttyBuffer {
    pub ptr: *mut u8,
    pub cap: usize,
    pub len: usize,
}

/// Struct "sized": o primeiro campo diz o tamanho que quem chama conhece, para
/// a biblioteca não escrever além dele numa versão mais nova.
#[repr(C)]
pub struct RenderStateCursor {
    pub size: usize,
    pub viewport_has_value: bool,
    pub viewport_x: u16,
    pub viewport_y: u16,
    pub wide_tail: bool,
    pub visible: bool,
    pub blinking: bool,
    pub password_input: bool,
    pub visual_style: c_int,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union ScrollViewportValue {
    pub delta: isize,
    pub _padding: [u64; 2],
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct ScrollViewport {
    pub tag: c_int,
    pub value: ScrollViewportValue,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct TerminalScrollbar {
    pub total: u64,
    pub offset: u64,
    pub len: u64,
}

/// Referência a uma célula, válida só até a próxima mudança no terminal.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct GridRef {
    pub node: *mut c_void,
    pub x: u16,
    pub y: u16,
}

impl GridRef {
    pub const NONE: Self = Self {
        node: std::ptr::null_mut(),
        x: 0,
        y: 0,
    };
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct PointCoordinate {
    pub x: u16,
    pub y: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union PointValue {
    pub coordinate: PointCoordinate,
    pub _padding: [u64; 2],
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Point {
    pub tag: c_int,
    pub value: PointValue,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Selection {
    pub start: GridRef,
    pub end: GridRef,
    pub rectangle: bool,
}

impl Selection {
    pub const NONE: Self = Self {
        start: GridRef::NONE,
        end: GridRef::NONE,
        rectangle: false,
    };
}

#[repr(C)]
pub struct RowSelection {
    pub size: usize,
    pub start_x: u16,
    pub end_x: u16,
}

#[repr(C)]
pub struct SurfacePosition {
    pub x: f64,
    pub y: f64,
}

#[repr(C)]
pub struct GestureGeometry {
    pub columns: u32,
    pub cell_width: u32,
    pub padding_left: u32,
    pub screen_height: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct MousePosition {
    pub x: f32,
    pub y: f32,
}

#[repr(C)]
pub struct MouseEncoderSize {
    pub size: usize,
    pub screen_width: u32,
    pub screen_height: u32,
    pub cell_width: u32,
    pub cell_height: u32,
    pub padding_top: u32,
    pub padding_bottom: u32,
    pub padding_right: u32,
    pub padding_left: u32,
}

#[repr(C)]
pub struct ClipboardContent {
    pub mime: GhosttyString,
    pub data: GhosttyString,
}

/// Pedido de gravação na área de transferência (OSC 52 e afins), emprestado
/// só durante o callback.
#[repr(C)]
pub struct ClipboardWrite {
    pub location: c_int,
    pub contents: *const ClipboardContent,
    pub contents_len: usize,
    pub name: GhosttyString,
    pub granted: bool,
    pub can_remember: bool,
    pub ctx: *const c_void,
    pub reply: Option<ClipboardWriteReplyFn>,
}

#[repr(C)]
pub struct ClipboardWriteReply {
    pub size: usize,
    pub result: c_int,
    pub remember: bool,
}

#[repr(C)]
pub struct ClipboardRead {
    pub location: c_int,
    pub mimes: *const GhosttyString,
    pub mimes_len: usize,
    pub list: bool,
    pub name: GhosttyString,
    pub granted: bool,
    pub can_remember: bool,
    pub ctx: *const c_void,
    pub reply: Option<ClipboardReadReplyFn>,
}

#[repr(C)]
pub struct ClipboardReadReply {
    pub size: usize,
    pub result: c_int,
    pub contents: *const ClipboardContent,
    pub contents_len: usize,
    pub available: *const GhosttyString,
    pub available_len: usize,
    pub remember: bool,
}

// Os tamanhos dos cabeçalhos da 1.0.1 (64 bits). Na troca de versão, avisam do
// que a releitura dos cabeçalhos deixar passar.
const _: () = {
    use std::mem::size_of;
    assert!(size_of::<ColorRgb>() == 3);
    assert!(size_of::<StyleColor>() == 4);
    assert!(size_of::<Style>() == 16);
    assert!(size_of::<GhosttyString>() == 16);
    assert!(size_of::<GhosttyBuffer>() == 24);
    assert!(size_of::<RenderStateCursor>() == 24);
    assert!(size_of::<TerminalModeConfig>() == 4);
    assert!(size_of::<ScrollViewport>() == 24);
    assert!(size_of::<TerminalScrollbar>() == 24);
    assert!(size_of::<GridRef>() == 16);
    assert!(size_of::<Point>() == 24);
    // "frozen layout … 40 bytes on 64-bit targets" (selection.h)
    assert!(size_of::<Selection>() == 40);
    assert!(size_of::<RowSelection>() == 16);
    assert!(size_of::<SurfacePosition>() == 16);
    assert!(size_of::<GestureGeometry>() == 16);
    assert!(size_of::<MousePosition>() == 8);
    assert!(size_of::<MouseEncoderSize>() == 40);
    assert!(size_of::<ClipboardContent>() == 32);
    // "64 bytes on 64-bit targets" e "72 bytes" (terminal.h)
    assert!(size_of::<ClipboardWrite>() == 64);
    assert!(size_of::<ClipboardRead>() == 72);
    assert!(size_of::<ClipboardWriteReply>() == 16);
    assert!(size_of::<ClipboardReadReply>() == 56);
};

#[link(name = "ghostty-vt", kind = "static")]
unsafe extern "C" {
    pub fn ghostty_terminal_new(
        allocator: Allocator,
        terminal: *mut Terminal,
        cols: u16,
        rows: u16,
    ) -> GhosttyResult;
    pub fn ghostty_terminal_free(terminal: Terminal);
    pub fn ghostty_terminal_resize(
        terminal: Terminal,
        cols: u16,
        rows: u16,
        cell_width_px: u32,
        cell_height_px: u32,
    ) -> GhosttyResult;
    pub fn ghostty_terminal_set(
        terminal: Terminal,
        option: c_int,
        value: *const c_void,
    ) -> GhosttyResult;
    pub fn ghostty_terminal_get(terminal: Terminal, data: c_int, out: *mut c_void)
    -> GhosttyResult;
    pub fn ghostty_terminal_vt_write(terminal: Terminal, data: *const u8, len: usize);
    pub fn ghostty_terminal_scroll_viewport(
        terminal: Terminal,
        behavior: ScrollViewport,
    ) -> GhosttyResult;
    pub fn ghostty_terminal_grid_ref(
        terminal: Terminal,
        point: Point,
        out_ref: *mut GridRef,
    ) -> GhosttyResult;
    pub fn ghostty_terminal_select_all(
        terminal: Terminal,
        out_selection: *mut Selection,
    ) -> GhosttyResult;

    pub fn ghostty_selection_gesture_new(
        allocator: Allocator,
        out_gesture: *mut Gesture,
    ) -> GhosttyResult;
    pub fn ghostty_selection_gesture_free(gesture: Gesture, terminal: Terminal);
    pub fn ghostty_selection_gesture_get(
        gesture: Gesture,
        terminal: Terminal,
        data: c_int,
        value: *mut c_void,
    ) -> GhosttyResult;
    pub fn ghostty_selection_gesture_event(
        gesture: Gesture,
        terminal: Terminal,
        event: GestureEvent,
        out_selection: *mut Selection,
    ) -> GhosttyResult;
    pub fn ghostty_selection_gesture_event_new(
        allocator: Allocator,
        out_event: *mut GestureEvent,
        kind: c_int,
    ) -> GhosttyResult;
    pub fn ghostty_selection_gesture_event_free(event: GestureEvent);
    pub fn ghostty_selection_gesture_event_set(
        event: GestureEvent,
        option: c_int,
        value: *const c_void,
    ) -> GhosttyResult;

    pub fn ghostty_formatter_terminal_new(
        allocator: Allocator,
        formatter: *mut Formatter,
        terminal: Terminal,
    ) -> GhosttyResult;
    pub fn ghostty_formatter_free(formatter: Formatter);
    pub fn ghostty_formatter_set(
        formatter: Formatter,
        option: c_int,
        value: *const c_void,
    ) -> GhosttyResult;
    pub fn ghostty_formatter_format_buf(
        formatter: Formatter,
        buf: *mut u8,
        buf_len: usize,
        out_written: *mut usize,
    ) -> GhosttyResult;

    pub fn ghostty_mouse_encoder_new(
        allocator: Allocator,
        encoder: *mut MouseEncoder,
    ) -> GhosttyResult;
    pub fn ghostty_mouse_encoder_free(encoder: MouseEncoder);
    pub fn ghostty_mouse_encoder_set(
        encoder: MouseEncoder,
        option: c_int,
        value: *const c_void,
    ) -> GhosttyResult;
    pub fn ghostty_mouse_encoder_set_from_terminal(
        encoder: MouseEncoder,
        terminal: Terminal,
    ) -> GhosttyResult;
    pub fn ghostty_mouse_encoder_encode(
        encoder: MouseEncoder,
        event: MouseEvent,
        buf: *mut u8,
        buf_len: usize,
        out_written: *mut usize,
    ) -> GhosttyResult;
    pub fn ghostty_mouse_event_new(allocator: Allocator, event: *mut MouseEvent) -> GhosttyResult;
    pub fn ghostty_mouse_event_free(event: MouseEvent);
    pub fn ghostty_mouse_event_set_action(event: MouseEvent, action: c_int) -> GhosttyResult;
    pub fn ghostty_mouse_event_set_button(event: MouseEvent, button: c_int) -> GhosttyResult;
    pub fn ghostty_mouse_event_clear_button(event: MouseEvent) -> GhosttyResult;
    pub fn ghostty_mouse_event_set_mods(event: MouseEvent, mods: u16) -> GhosttyResult;
    pub fn ghostty_mouse_event_set_position(
        event: MouseEvent,
        position: MousePosition,
    ) -> GhosttyResult;

    pub fn ghostty_render_state_new(allocator: Allocator, state: *mut RenderState)
    -> GhosttyResult;
    pub fn ghostty_render_state_free(state: RenderState);
    pub fn ghostty_render_state_update(state: RenderState, terminal: Terminal) -> GhosttyResult;
    pub fn ghostty_render_state_clean(state: RenderState) -> GhosttyResult;
    pub fn ghostty_render_state_get(
        state: RenderState,
        data: c_int,
        out: *mut c_void,
    ) -> GhosttyResult;

    pub fn ghostty_render_state_row_iterator_new(
        allocator: Allocator,
        iterator: *mut RowIterator,
    ) -> GhosttyResult;
    pub fn ghostty_render_state_row_iterator_free(iterator: RowIterator);
    pub fn ghostty_render_state_row_iterator_next(iterator: RowIterator) -> bool;
    pub fn ghostty_render_state_row_iterator_next_dirty(
        iterator: RowIterator,
        out_y: *mut u16,
    ) -> bool;
    pub fn ghostty_render_state_row_get(
        iterator: RowIterator,
        data: c_int,
        out: *mut c_void,
    ) -> GhosttyResult;

    pub fn ghostty_render_state_row_cells_new(
        allocator: Allocator,
        cells: *mut RowCells,
    ) -> GhosttyResult;
    pub fn ghostty_render_state_row_cells_free(cells: RowCells);
    pub fn ghostty_render_state_row_cells_next(cells: RowCells) -> bool;
    pub fn ghostty_render_state_row_cells_get(
        cells: RowCells,
        data: c_int,
        out: *mut c_void,
    ) -> GhosttyResult;

    pub fn ghostty_cell_get(cell: GhosttyCell, data: c_int, out: *mut c_void) -> GhosttyResult;
    pub fn ghostty_row_get(row: GhosttyRow, data: c_int, out: *mut c_void) -> GhosttyResult;
    pub fn ghostty_grid_ref_hyperlink_uri(
        reference: *const GridRef,
        buf: *mut u8,
        buf_len: usize,
        out_written: *mut usize,
    ) -> GhosttyResult;

    pub fn ghostty_key_encoder_new(allocator: Allocator, encoder: *mut KeyEncoder)
    -> GhosttyResult;
    pub fn ghostty_key_encoder_free(encoder: KeyEncoder);
    pub fn ghostty_key_encoder_set(
        encoder: KeyEncoder,
        option: c_int,
        value: *const c_void,
    ) -> GhosttyResult;
    pub fn ghostty_key_encoder_set_from_terminal(
        encoder: KeyEncoder,
        terminal: Terminal,
    ) -> GhosttyResult;
    pub fn ghostty_key_encoder_encode(
        encoder: KeyEncoder,
        event: KeyEvent,
        buf: *mut u8,
        buf_len: usize,
        out_written: *mut usize,
    ) -> GhosttyResult;

    pub fn ghostty_key_event_new(allocator: Allocator, event: *mut KeyEvent) -> GhosttyResult;
    pub fn ghostty_key_event_free(event: KeyEvent);
    pub fn ghostty_key_event_set_action(event: KeyEvent, action: c_int) -> GhosttyResult;
    pub fn ghostty_key_event_set_key(event: KeyEvent, key: c_int) -> GhosttyResult;
    pub fn ghostty_key_event_set_mods(event: KeyEvent, mods: u16) -> GhosttyResult;
    pub fn ghostty_key_event_set_consumed_mods(event: KeyEvent, mods: u16) -> GhosttyResult;
    pub fn ghostty_key_event_set_utf8(event: KeyEvent, utf8: GhosttyString) -> GhosttyResult;
    pub fn ghostty_key_event_set_unshifted_codepoint(
        event: KeyEvent,
        codepoint: u32,
    ) -> GhosttyResult;
}
