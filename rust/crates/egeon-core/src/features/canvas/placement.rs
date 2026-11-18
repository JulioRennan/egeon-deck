//! O frame que o arrasto da tela dá a um nó novo.
//!
//! No Swift, o nó nasce onde você arrasta o retângulo da ferramenta, com
//! largura e altura nunca abaixo de `NodeView.minSize`. Quem chega SEM frame é
//! outra regra: `workbench::frames::apply_default_frames`.

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
