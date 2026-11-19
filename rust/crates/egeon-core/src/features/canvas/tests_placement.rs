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

fn at(x: f64, y: f64) -> Frame {
    Frame {
        x,
        y,
        w: 720.0,
        h: 460.0,
    }
}

#[test]
fn spawn_nasce_a_40_do_canto_do_que_esta_a_vista() {
    let visible = Frame {
        x: 1000.0,
        y: 500.0,
        w: 1200.0,
        h: 800.0,
    };
    assert_eq!(
        super::placement::spawn(visible, &[], super::placement::TERMINAL_SIZE),
        at(1040.0, 540.0)
    );
}

#[test]
fn spawn_desce_em_diagonal_enquanto_o_lugar_esta_ocupado() {
    let visible = at(0.0, 0.0);
    // Ocupado é o canto a menos de 8 pontos; longe disso não conta.
    let taken = [at(43.0, 37.0), at(72.0, 72.0), at(200.0, 104.0)];
    assert_eq!(
        super::placement::spawn(visible, &taken, super::placement::TERMINAL_SIZE),
        at(104.0, 104.0)
    );
}
