//! Da fileira de células lida do Ghostty à linha do protocolo: células vizinhas
//! de mesmo estilo viram um trecho, e o branco sem estilo do fim sai.

use egeon_core::protocol::screen::{Line, Span, Style};

/// Uma célula já lida. A cauda de um caractere largo não chega aqui: ela é
/// contada no `width` da célula que a ocupa.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Cell {
    /// Vazio quando a célula não tem texto.
    pub text: String,
    pub width: u16,
    pub style: Style,
}

impl Cell {
    fn is_blank(&self) -> bool {
        self.text.is_empty() || self.text == " "
    }

    /// O texto como se vê: célula sem texto ocupa a coluna com um espaço.
    pub fn shown(&self) -> &str {
        if self.text.is_empty() {
            " "
        } else {
            &self.text
        }
    }
}

pub(crate) fn line(row: u16, cells: &[Cell]) -> Line {
    // Só o branco de estilo padrão é cortado: espaço com fundo colorido é
    // pintado, e a UI precisa dele.
    let keep = cells
        .iter()
        .rposition(|c| !c.is_blank() || c.style != Style::default())
        .map_or(0, |i| i + 1);

    let mut spans: Vec<Span> = Vec::new();
    let mut col: u16 = 0;
    for cell in &cells[..keep] {
        let text = cell.shown();
        match spans.last_mut() {
            Some(span) if span.style == cell.style => {
                span.text.push_str(text);
                span.cells += cell.width;
            }
            _ => spans.push(Span {
                col,
                cells: cell.width,
                text: text.to_owned(),
                style: cell.style,
            }),
        }
        col = col.saturating_add(cell.width);
    }
    Line {
        row,
        spans,
        selection: None,
    }
}

/// O texto da linha, sem estilo: célula em branco vira espaço, e nada é
/// cortado (o corte do `peek` é do core).
pub(crate) fn text(cells: &[Cell]) -> String {
    cells.iter().map(Cell::shown).collect()
}

#[cfg(test)]
mod tests {
    use egeon_core::protocol::screen::Color;

    use super::*;

    fn cell(text: &str, style: Style) -> Cell {
        Cell {
            text: text.to_owned(),
            width: 1,
            style,
        }
    }

    fn plain(text: &str) -> Vec<Cell> {
        text.chars()
            .map(|c| cell(&c.to_string(), Style::default()))
            .collect()
    }

    #[test]
    fn junta_celulas_de_mesmo_estilo_e_corta_o_branco_do_fim() {
        let mut cells = plain("ab  ");
        cells.push(cell("", Style::default()));
        let l = line(3, &cells);
        assert_eq!(l.row, 3);
        assert_eq!(l.spans.len(), 1);
        assert_eq!(l.spans[0].text, "ab");
        assert_eq!(l.spans[0].cells, 2);
    }

    #[test]
    fn estilo_novo_abre_trecho_na_coluna_certa() {
        let red = Style {
            fg: Some(Color::Palette(1)),
            ..Style::default()
        };
        let mut cells = plain("a ");
        cells.push(cell("b", red));
        let l = line(0, &cells);
        assert_eq!(l.spans.len(), 2);
        assert_eq!((l.spans[1].col, l.spans[1].text.as_str()), (2, "b"));
        assert_eq!(l.spans[1].style, red);
    }

    #[test]
    fn espaco_com_fundo_fica() {
        let bg = Style {
            bg: Some(Color::Palette(4)),
            ..Style::default()
        };
        let mut cells = plain("x");
        cells.push(cell("", bg));
        let l = line(0, &cells);
        assert_eq!(l.spans.len(), 2);
        assert_eq!(l.spans[1].text, " ");
    }

    #[test]
    fn caractere_largo_ocupa_duas_celulas() {
        let mut cells = vec![Cell {
            text: "日".to_owned(),
            width: 2,
            style: Style::default(),
        }];
        cells.extend(plain("x"));
        let l = line(0, &cells);
        assert_eq!(l.spans[0].cells, 3);
        assert_eq!(l.spans[0].text, "日x");
    }

    #[test]
    fn linha_vazia_nao_tem_trecho() {
        assert!(line(0, &plain("   ")).spans.is_empty());
    }

    #[test]
    fn texto_poe_espaco_no_branco_e_nao_corta() {
        let mut cells = plain(" a");
        cells.push(cell("", Style::default()));
        cells.extend(plain("b  "));
        assert_eq!(text(&cells), " a b  ");
    }
}
