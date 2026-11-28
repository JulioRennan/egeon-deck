//! O link sob uma célula, para o ⌘-clique: o explícito (OSC 8), o implícito e
//! o nome solto, nessa ordem — a de `MBTerminalView.mouseUp` do app de hoje.

use egeon_core::ports::screen::LinkHit;

use super::{GhosttyScreen, grow, sized};
use crate::link::{self, LinkRow};
use crate::{ffi, line};

impl GhosttyScreen {
    pub(super) fn link_under(&mut self, col: u16, row: u16) -> Option<LinkHit> {
        if col >= self.size.cols || row >= self.size.rows {
            return None;
        }
        if let Some(uri) = self.hyperlink((col, row)) {
            return Some(LinkHit::Link(uri));
        }
        self.update();
        let rows: Vec<LinkRow> = self
            .all_rows()
            .into_iter()
            .map(|r| LinkRow {
                cells: r.cells,
                continued: r.continued,
            })
            .collect();
        if let Some(found) = link::implicit(&rows, self.size.cols, usize::from(row), col) {
            return Some(LinkHit::Link(found));
        }
        // O nome solto lê a linha como o `translateToString(trimRight:)`.
        let text = line::text(&rows.get(usize::from(row))?.cells);
        link::word(text.trim_end(), usize::from(col)).map(LinkHit::Word)
    }

    fn hyperlink(&self, at: (u16, u16)) -> Option<String> {
        let reference = self.grid_ref(at)?;
        let uri = grow::<256>(|buf| {
            let mut written: usize = 0;
            // SAFETY: a referência acabou de ser lida e nada mudou o terminal;
            // `buf` válido com o tamanho passado.
            let r = unsafe {
                ffi::ghostty_grid_ref_hyperlink_uri(
                    &reference,
                    buf.as_mut_ptr(),
                    buf.len(),
                    &mut written,
                )
            };
            sized(r, written)
        });
        (!uri.is_empty()).then(|| String::from_utf8_lossy(&uri).into_owned())
    }
}
