//! O ponteiro sobre a tela: relatório de mouse para o programa, seleção ou
//! rolagem. A escolha entre os três é a do `MacTerminalView` do SwiftTerm
//! 1.18, que o app de hoje usa sem mudar.

use std::ffi::{c_int, c_void};
use std::mem::size_of;
use std::ptr;

use egeon_core::ports::screen::Screen;
use egeon_core::protocol::screen::{
    Key, KeyPress, Mods, MouseButton, NamedKey, Pointer, PointerKind, Scroll,
};

use super::{GhosttyScreen, grow, sized};
use crate::{ffi, key};

/// Pixels de uma célula na geometria passada ao Ghostty. A UI manda a posição
/// em células; o Ghostty a quer em pixels, para decidir pela metade da célula.
const CELL_PX: f32 = 16.0;

/// Intervalo do clique duplo, o padrão do macOS (`NSEvent.doubleClickInterval`).
const DOUBLE_CLICK_NS: u64 = 500_000_000;

/// Teto de linhas por evento de roda: um valor absurdo vindo da UI não vira
/// megabytes de setas.
const MAX_WHEEL_LINES: u32 = 1000;

impl GhosttyScreen {
    pub(super) fn handle_pointer(&mut self, p: &Pointer) -> Vec<u8> {
        let tracking = self.mouse_tracking();
        // Shift passa por cima do mouse do programa: dá para selecionar mesmo
        // num programa que pediu o mouse.
        let report = tracking && !p.mods.shift;
        match p.kind {
            PointerKind::Wheel => self.wheel(p, report),
            PointerKind::Press if report => self.report(p, ffi::MOUSE_ACTION_PRESS),
            PointerKind::Release if report => self.report(p, ffi::MOUSE_ACTION_RELEASE),
            PointerKind::Drag if report => self.report(p, ffi::MOUSE_ACTION_MOTION),
            // O movimento vai a quem o pediu mesmo com shift (`mouseMoved`).
            PointerKind::Move if tracking => self.report(p, ffi::MOUSE_ACTION_MOTION),
            PointerKind::Move => Vec::new(),
            PointerKind::Press => {
                self.select_press(p);
                Vec::new()
            }
            PointerKind::Release => {
                self.select_release(p);
                Vec::new()
            }
            PointerKind::Drag => {
                self.select_drag(p);
                Vec::new()
            }
        }
    }

    fn mouse_tracking(&self) -> bool {
        let mut on = false;
        // SAFETY: term vivo; DATA_MOUSE_TRACKING escreve um bool.
        unsafe {
            ffi::ghostty_terminal_get(
                self.term,
                ffi::TERMINAL_DATA_MOUSE_TRACKING,
                (&raw mut on).cast::<c_void>(),
            )
        };
        on
    }

    fn alternate(&self) -> bool {
        let mut screen: c_int = 0;
        // SAFETY: term vivo; DATA_ACTIVE_SCREEN escreve um GhosttyTerminalScreen.
        unsafe {
            ffi::ghostty_terminal_get(
                self.term,
                ffi::TERMINAL_DATA_ACTIVE_SCREEN,
                (&raw mut screen).cast::<c_void>(),
            )
        };
        screen == ffi::TERMINAL_SCREEN_ALTERNATE
    }

    /// Roda: botões 4 e 5 para quem pediu o mouse; setas na tela alternativa,
    /// que não tem histórico; senão, rolar a vista.
    fn wheel(&mut self, p: &Pointer, report: bool) -> Vec<u8> {
        let n = p.lines.unsigned_abs().min(MAX_WHEEL_LINES);
        if n == 0 {
            return Vec::new();
        }
        let up = p.lines > 0;
        let times = n as usize;
        if report {
            let button = if up {
                ffi::MOUSE_BUTTON_FOUR
            } else {
                ffi::MOUSE_BUTTON_FIVE
            };
            return self
                .encode_mouse(p, ffi::MOUSE_ACTION_PRESS, Some(button), false)
                .repeat(times);
        }
        if self.alternate() {
            let arrow = KeyPress {
                key: Key::Named(if up { NamedKey::Up } else { NamedKey::Down }),
                mods: Mods::default(),
                text: None,
            };
            return self.encode_key(&arrow).repeat(times);
        }
        let rows = n as i32;
        self.scroll(Scroll::Rows(if up { -rows } else { rows }));
        Vec::new()
    }

    fn report(&mut self, p: &Pointer, action: c_int) -> Vec<u8> {
        let button = match p.kind {
            PointerKind::Move => None,
            _ => p.button.map(button_code),
        };
        self.encode_mouse(p, action, button, p.kind == PointerKind::Drag)
    }

    fn encode_mouse(
        &mut self,
        p: &Pointer,
        action: c_int,
        button: Option<c_int>,
        pressed: bool,
    ) -> Vec<u8> {
        let px = CELL_PX as u32;
        let size = ffi::MouseEncoderSize {
            size: size_of::<ffi::MouseEncoderSize>(),
            screen_width: u32::from(self.size.cols) * px,
            screen_height: u32::from(self.size.rows) * px,
            cell_width: px,
            cell_height: px,
            padding_top: 0,
            padding_bottom: 0,
            padding_right: 0,
            padding_left: 0,
        };
        // SAFETY: codificador, evento e term vivos; cada opção recebe o tipo
        // que o cabeçalho pede.
        unsafe {
            // Formato e modo mudam com o que o programa escreve: lidos a cada
            // evento, como as teclas.
            ffi::ghostty_mouse_encoder_set_from_terminal(self.mouse, self.term);
            set_mouse(self.mouse, ffi::MOUSE_ENCODER_OPT_SIZE, &size);
            set_mouse(
                self.mouse,
                ffi::MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED,
                &pressed,
            );
            ffi::ghostty_mouse_event_set_action(self.mouse_event, action);
            match button {
                Some(b) => ffi::ghostty_mouse_event_set_button(self.mouse_event, b),
                None => ffi::ghostty_mouse_event_clear_button(self.mouse_event),
            };
            ffi::ghostty_mouse_event_set_mods(self.mouse_event, key::mods_bits(p.mods));
            ffi::ghostty_mouse_event_set_position(
                self.mouse_event,
                ffi::MousePosition {
                    x: p.x * CELL_PX,
                    y: p.y * CELL_PX,
                },
            );
        }
        grow::<64>(|buf| self.encode_mouse_into(buf))
    }

    fn encode_mouse_into(&mut self, buf: &mut [u8]) -> Result<usize, usize> {
        let mut written: usize = 0;
        // SAFETY: `buf` válido com o tamanho passado; `written` é a saída.
        let r = unsafe {
            ffi::ghostty_mouse_encoder_encode(
                self.mouse,
                self.mouse_event,
                buf.as_mut_ptr(),
                buf.len(),
                &mut written,
            )
        };
        sized(r, written)
    }

    /// A célula sob o ponto, presa à vista.
    fn cell(&self, p: &Pointer) -> (u16, u16) {
        (clamp(p.x, self.size.cols), clamp(p.y, self.size.rows))
    }

    pub(super) fn grid_ref(&self, (col, row): (u16, u16)) -> Option<ffi::GridRef> {
        let point = ffi::Point {
            tag: ffi::POINT_TAG_VIEWPORT,
            value: ffi::PointValue {
                coordinate: ffi::PointCoordinate {
                    x: col,
                    y: u32::from(row),
                },
            },
        };
        let mut at = ffi::GridRef::NONE;
        // SAFETY: term vivo; a saída é um GhosttyGridRef.
        let r = unsafe { ffi::ghostty_terminal_grid_ref(self.term, point, &mut at) };
        (r == ffi::SUCCESS).then_some(at)
    }

    fn geometry(&self) -> ffi::GestureGeometry {
        let px = CELL_PX as u32;
        ffi::GestureGeometry {
            columns: u32::from(self.size.cols),
            cell_width: px,
            padding_left: 0,
            screen_height: u32::from(self.size.rows) * px,
        }
    }

    fn select_press(&mut self, p: &Pointer) {
        let Some(at) = self.grid_ref(self.cell(p)) else {
            return;
        };
        // Shift com seleção feita a estende até o clique (`shiftExtend`).
        if p.mods.shift
            && let Some(mut sel) = self.selection()
        {
            sel.end = at;
            self.set_selection(Some(&sel));
            return;
        }
        let position = surface(p);
        let time = p.time_ms.saturating_mul(1_000_000);
        let distance = f64::from(CELL_PX);
        // SAFETY: evento vivo; cada opção recebe o tipo que o cabeçalho pede, e
        // o Ghostty copia o valor.
        unsafe {
            set_gesture(self.press, ffi::GESTURE_OPT_REF, &at);
            set_gesture(self.press, ffi::GESTURE_OPT_POSITION, &position);
            set_gesture(self.press, ffi::GESTURE_OPT_TIME_NS, &time);
            set_gesture(
                self.press,
                ffi::GESTURE_OPT_REPEAT_INTERVAL_NS,
                &DOUBLE_CLICK_NS,
            );
            set_gesture(self.press, ffi::GESTURE_OPT_REPEAT_DISTANCE, &distance);
        }
        // Clique simples desfaz a seleção; o duplo devolve a palavra e o
        // triplo, a linha.
        let sel = self.gesture_event(self.press);
        self.set_selection(sel.as_ref());
    }

    fn select_drag(&mut self, p: &Pointer) {
        let cell = self.cell(p);
        let Some(at) = self.grid_ref(cell) else {
            return;
        };
        let position = surface(p);
        let geometry = self.geometry();
        // SAFETY: como em `select_press`.
        unsafe {
            set_gesture(self.drag, ffi::GESTURE_OPT_REF, &at);
            set_gesture(self.drag, ffi::GESTURE_OPT_POSITION, &position);
            set_gesture(self.drag, ffi::GESTURE_OPT_GEOMETRY, &geometry);
        }
        if let Some(sel) = self.gesture_event(self.drag) {
            self.set_selection(Some(&sel));
        }

        // Fora da vista, rola: a UI repete o arrasto enquanto o ponteiro fica
        // lá, e cada repetição sobe ou desce na velocidade do SwiftTerm.
        let rows = f32::from(self.size.rows);
        let beyond = if p.y < 0.0 {
            -p.y
        } else if p.y >= rows {
            p.y - rows
        } else {
            return;
        };
        if !self.autoscrolling() {
            return;
        }
        let viewport = ffi::PointCoordinate {
            x: cell.0,
            y: u32::from(cell.1),
        };
        // SAFETY: como em `select_press`.
        unsafe {
            set_gesture(self.tick, ffi::GESTURE_OPT_VIEWPORT, &viewport);
            set_gesture(self.tick, ffi::GESTURE_OPT_POSITION, &position);
            set_gesture(self.tick, ffi::GESTURE_OPT_GEOMETRY, &geometry);
        }
        for _ in 0..velocity(beyond as u32, self.size.rows) {
            match self.gesture_event(self.tick) {
                Some(sel) => self.set_selection(Some(&sel)),
                None => break,
            }
        }
    }

    fn select_release(&mut self, p: &Pointer) {
        let at = self.grid_ref(self.cell(p));
        // SAFETY: como em `select_press`; sem célula, a opção é limpa.
        unsafe {
            match &at {
                Some(at) => set_gesture(self.release, ffi::GESTURE_OPT_REF, at),
                None => {
                    ffi::ghostty_selection_gesture_event_set(
                        self.release,
                        ffi::GESTURE_OPT_REF,
                        ptr::null(),
                    );
                }
            }
        }
        let _ = self.gesture_event(self.release);
    }

    fn autoscrolling(&self) -> bool {
        let mut dir: c_int = 0;
        // SAFETY: gesto e term vivos; DATA_AUTOSCROLL escreve um enum C.
        unsafe {
            ffi::ghostty_selection_gesture_get(
                self.gesture,
                self.term,
                ffi::GESTURE_DATA_AUTOSCROLL,
                (&raw mut dir).cast::<c_void>(),
            )
        };
        dir == ffi::GESTURE_AUTOSCROLL_UP || dir == ffi::GESTURE_AUTOSCROLL_DOWN
    }

    /// Aplica o evento ao gesto; a seleção que resulta, se alguma.
    fn gesture_event(&mut self, event: ffi::GestureEvent) -> Option<ffi::Selection> {
        let mut sel = ffi::Selection::NONE;
        // SAFETY: gesto, term e evento vivos; a saída é um GhosttySelection.
        let r = unsafe {
            ffi::ghostty_selection_gesture_event(self.gesture, self.term, event, &mut sel)
        };
        (r == ffi::SUCCESS).then_some(sel)
    }
}

/// # Safety
/// `encoder` vivo e `T` o tipo que o cabeçalho pede para `option`.
unsafe fn set_mouse<T>(encoder: ffi::MouseEncoder, option: c_int, value: &T) {
    // SAFETY: ver o contrato acima.
    unsafe { ffi::ghostty_mouse_encoder_set(encoder, option, ptr::from_ref(value).cast()) };
}

/// # Safety
/// `event` vivo e `T` o tipo que o cabeçalho pede para `option`.
unsafe fn set_gesture<T>(event: ffi::GestureEvent, option: c_int, value: &T) {
    // SAFETY: ver o contrato acima.
    unsafe { ffi::ghostty_selection_gesture_event_set(event, option, ptr::from_ref(value).cast()) };
}

fn button_code(b: MouseButton) -> c_int {
    match b {
        MouseButton::Left => ffi::MOUSE_BUTTON_LEFT,
        MouseButton::Middle => ffi::MOUSE_BUTTON_MIDDLE,
        MouseButton::Right => ffi::MOUSE_BUTTON_RIGHT,
    }
}

fn surface(p: &Pointer) -> ffi::SurfacePosition {
    ffi::SurfacePosition {
        x: f64::from(p.x * CELL_PX),
        y: f64::from(p.y * CELL_PX),
    }
}

/// Coordenada em células presa a `0..n`; o que não é número vira 0.
fn clamp(v: f32, n: u16) -> u16 {
    let last = n.saturating_sub(1);
    if !v.is_finite() || v <= 0.0 {
        return 0;
    }
    if v >= f32::from(last) {
        return last;
    }
    v as u16
}

/// Linhas por repetição do arrasto fora da vista, pela distância da borda —
/// a curva de `calcScrollingVelocity` do SwiftTerm.
fn velocity(beyond: u32, rows: u16) -> u16 {
    match beyond {
        0..=1 => 1,
        2..=5 => 3,
        6..=9 => 10,
        _ => rows.max(20),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn coordenada_fica_dentro_da_grade() {
        assert_eq!(clamp(-3.0, 10), 0);
        assert_eq!(clamp(3.7, 10), 3);
        assert_eq!(clamp(42.0, 10), 9);
        assert_eq!(clamp(f32::NAN, 10), 0);
    }

    #[test]
    fn velocidade_segue_a_curva_do_swiftterm() {
        assert_eq!(velocity(0, 24), 1);
        assert_eq!(velocity(1, 24), 1);
        assert_eq!(velocity(2, 24), 3);
        assert_eq!(velocity(6, 24), 10);
        assert_eq!(velocity(10, 24), 24);
        assert_eq!(velocity(10, 5), 20);
    }
}
