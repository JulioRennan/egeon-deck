//! O frame do arrasto: o mínimo do cartão e o resgate de coordenada negativa.

use super::placement::*;
use crate::features::node::model::Frame;

fn frame(x: f64, y: f64, w: f64, h: f64) -> Frame {
    Frame { x, y, w, h }
}

#[test]
fn arrasto_pequeno_ou_fora_do_documento_e_ajustado() {
    assert_eq!(
        fit(frame(100.0, 50.0, 10.0, 10.0)),
        frame(100.0, 50.0, MIN_WIDTH, MIN_HEIGHT)
    );
    assert_eq!(
        fit(frame(-30.0, -5.0, 640.0, 420.0)),
        frame(0.0, 0.0, 640.0, 420.0),
        "x ou y negativos são resgatados para 0"
    );
}
