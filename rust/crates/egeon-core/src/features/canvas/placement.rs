//! O frame que o arrasto da tela dá a um nó novo.
//!
//! No Swift, o nó nasce onde você arrasta o retângulo da ferramenta, com
//! largura e altura nunca abaixo de `NodeView.minSize`. Quem chega SEM frame é
//! outra regra: `workbench::frames::apply_default_frames` — ou, quando a tela
//! diz o que está à vista, [`spawn`].

use crate::features::node::model::Frame;

pub const MIN_WIDTH: f64 = 280.0;
pub const MIN_HEIGHT: f64 = 180.0;

/// O frame do arrasto, dentro do que o canvas aceita: dentro do documento
/// (x e y negativos são resgatados para 0) e nunca menor que o mínimo do
/// cartão.
pub fn fit(frame: Frame) -> Frame {
    Frame {
        x: frame.x.max(0.0),
        y: frame.y.max(0.0),
        w: frame.w.max(MIN_WIDTH),
        h: frame.h.max(MIN_HEIGHT),
    }
}

/// O tamanho de um terminal novo sem desenho (`CanvasTool.terminal`).
pub const TERMINAL_SIZE: (f64, f64) = (720.0, 460.0);

/// Ponto livre perto do canto superior esquerdo do que está visível
/// (`CanvasContainer.spawnRect`): para quando um nó nasce sem alguém ter
/// desenhado onde. [visible] é a área à vista, no espaço do canvas.
///
/// Empilha em diagonal enquanto o lugar estiver ocupado — um nó com o canto a
/// menos de 8 pontos dali —, senão nós novos nasceriam exatamente em cima uns
/// dos outros.
pub fn spawn(visible: Frame, taken: &[Frame], size: (f64, f64)) -> Frame {
    let (mut x, mut y) = (visible.x + 40.0, visible.y + 40.0);
    while taken
        .iter()
        .any(|f| (f.x - x).abs() < 8.0 && (f.y - y).abs() < 8.0)
    {
        x += 32.0;
        y += 32.0;
    }
    Frame {
        x,
        y,
        w: size.0,
        h: size.1,
    }
}
