//! O layout de quem ainda não tem frame (`defaultFrames` do `main.swift`) e o
//! resgate de nó gravado fora do documento.
//!
//! Os nós sem frame ficam empilhados numa coluna que ocupa a janela; o
//! resultado é gravado no `workbenches.json` na primeira vez, e dali em diante
//! quem manda é o arquivo.

use super::model::WorkbenchConfig;
use crate::features::node::model::Frame;

const MARGIN: f64 = 40.0;
const GAP: f64 = 16.0;
/// A área útil nunca é menor que isto, com ou sem janela.
const MIN_WIDTH: f64 = 900.0;
const MIN_HEIGHT: f64 = 600.0;

/// Dá frame a cada nó que não tem, empilhando a coluna pela janela
/// (`largura × altura`; sem janela vale o mínimo de 900×600), e resgata para 0
/// quem foi gravado em coordenada negativa: o scroll não vai a x<0 nem y<0, e
/// um nó lá não teria gesto que o trouxesse de volta.
///
/// A linha de cada nó sai da posição dele entre TODOS os nós, também dos que já
/// têm frame — como no Swift. Devolve as linhas de log do resgate.
pub fn apply_default_frames(
    bench: &mut WorkbenchConfig,
    window: Option<(f64, f64)>,
) -> Vec<String> {
    let (width, height) = window.unwrap_or((0.0, 0.0));
    let usable_width = (width - MARGIN * 2.0).max(MIN_WIDTH);
    let usable_height = (height - MARGIN * 2.0).max(MIN_HEIGHT);
    let count = bench.nodes.len().max(1);
    let row_height = ((usable_height - GAP * (count - 1) as f64) / count as f64).round();

    let mut notes = Vec::new();
    let name = bench.name.clone();
    for (row, node) in bench.nodes.iter_mut().enumerate() {
        let mut frame = node.frame().unwrap_or(Frame {
            x: MARGIN,
            y: MARGIN + row as f64 * (row_height + GAP),
            w: usable_width,
            h: row_height,
        });
        if frame.x < 0.0 || frame.y < 0.0 {
            notes.push(format!(
                "bancada {name}: nó \"{}\" estava fora do documento em ({},{}) — resgatado",
                node.id, frame.x as i64, frame.y as i64
            ));
            frame.x = frame.x.max(0.0);
            frame.y = frame.y.max(0.0);
        }
        node.set_frame(frame);
    }
    notes
}
