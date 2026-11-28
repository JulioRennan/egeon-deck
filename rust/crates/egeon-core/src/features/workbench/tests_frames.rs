//! O layout de quem não tem frame e o resgate de nó fora do documento
//! (`defaultFrames` e o build da bancada no `main.swift`).

use super::frames::apply_default_frames;
use super::model::WorkbenchConfig;
use crate::features::node::model::{Frame, NodeConfig, NodeKind};

fn bench(ids: &[&str]) -> WorkbenchConfig {
    let nodes = ids
        .iter()
        .map(|id| NodeConfig::new(NodeKind::Shell, *id))
        .collect();
    WorkbenchConfig::new("deck", "/tmp/deck", nodes)
}

fn frames(bench: &WorkbenchConfig) -> Vec<[f64; 4]> {
    bench
        .nodes
        .iter()
        .map(|n| {
            let f = n.frame().expect("frame gravado");
            [f.x, f.y, f.w, f.h]
        })
        .collect()
}

#[test]
fn sem_janela_a_coluna_ocupa_900_por_600_empilhada() {
    let mut one = bench(&["a"]);
    assert!(apply_default_frames(&mut one, None).is_empty());
    assert_eq!(frames(&one), [[40.0, 40.0, 900.0, 600.0]]);

    let mut two = bench(&["a", "b"]);
    apply_default_frames(&mut two, None);
    assert_eq!(
        frames(&two),
        [[40.0, 40.0, 900.0, 292.0], [40.0, 348.0, 900.0, 292.0]]
    );
}

#[test]
fn janela_grande_estica_a_coluna_e_a_pequena_vale_o_minimo() {
    let mut big = bench(&["a", "b"]);
    apply_default_frames(&mut big, Some((1400.0, 1000.0)));
    // largura 1400−80, altura da linha (920−16)/2.
    assert_eq!(
        frames(&big),
        [[40.0, 40.0, 1320.0, 452.0], [40.0, 508.0, 1320.0, 452.0]]
    );
    let mut small = bench(&["a"]);
    apply_default_frames(&mut small, Some((300.0, 200.0)));
    assert_eq!(frames(&small), [[40.0, 40.0, 900.0, 600.0]]);
}

#[test]
fn quem_ja_tem_frame_fica_e_a_linha_conta_todos_os_nos() {
    let mut b = bench(&["a", "b", "c"]);
    b.nodes[0].set_frame(Frame {
        x: 500.0,
        y: 70.0,
        w: 300.0,
        h: 200.0,
    });
    apply_default_frames(&mut b, None);
    let f = frames(&b);
    assert_eq!(f[0], [500.0, 70.0, 300.0, 200.0]);
    // Três linhas de (600−32)/3 = 189: a do `b` é a segunda e a do `c`, a terceira.
    assert_eq!(f[1], [40.0, 40.0 + 189.0 + 16.0, 900.0, 189.0]);
    assert_eq!(f[2], [40.0, 40.0 + 2.0 * (189.0 + 16.0), 900.0, 189.0]);
}

#[test]
fn coordenada_negativa_e_resgatada_para_zero_e_dita() {
    let mut b = bench(&["a", "b"]);
    b.nodes[0].set_frame(Frame {
        x: -120.7,
        y: 30.0,
        w: 300.0,
        h: 200.0,
    });
    b.nodes[1].set_frame(Frame {
        x: 10.0,
        y: -5.0,
        w: 300.0,
        h: 200.0,
    });
    let notes = apply_default_frames(&mut b, None);
    assert_eq!(
        notes,
        [
            "bancada deck: nó \"a\" estava fora do documento em (-121,30) — resgatado",
            "bancada deck: nó \"b\" estava fora do documento em (10,-5) — resgatado",
        ]
    );
    assert_eq!(
        frames(&b),
        [[0.0, 30.0, 300.0, 200.0], [10.0, 0.0, 300.0, 200.0]]
    );
}

#[test]
fn bancada_sem_nos_nao_faz_nada() {
    let mut b = bench(&[]);
    assert!(apply_default_frames(&mut b, None).is_empty());
}
