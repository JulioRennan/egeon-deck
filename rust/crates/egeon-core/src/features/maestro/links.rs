//! As ligações do maestro, que não se desenham (ADR-066). Porte de
//! `MaestroLinks.swift`.
//!
//! O maestro alcança todo terminal da bancada, e todo agente o alcança de
//! volta — é por onde chega a resposta de quem ele acionou (ADR-058). O canvas
//! mostra `edges`; as guardas e o `egeon peers` leem [`effective`].

use crate::features::edge::model::EdgeConfig;
use crate::features::node::model::NodeKind;
use crate::features::workbench::model::WorkbenchConfig;

/// As arestas da bancada mais as implícitas do maestro. A desenhada entre o
/// maestro e alguém vence a implícita; a implícita não tem limite por seta.
pub fn effective(bench: &WorkbenchConfig) -> Vec<EdgeConfig> {
    let mut edges = bench.edge_list().to_vec();
    let add = |edge: EdgeConfig, edges: &mut Vec<EdgeConfig>| {
        if !edges.contains(&edge) {
            edges.push(edge);
        }
    };
    for maestro in bench.nodes.iter().filter(|n| n.is_maestro()) {
        for node in bench.nodes.iter().filter(|n| n.id != maestro.id) {
            match node.kind {
                NodeKind::Agent => {
                    add(EdgeConfig::new(&maestro.id, &node.id, None), &mut edges);
                    add(EdgeConfig::new(&node.id, &maestro.id, None), &mut edges);
                }
                // Shell não responde: a volta seria uma seta morta.
                NodeKind::Shell => add(EdgeConfig::new(&maestro.id, &node.id, None), &mut edges),
                NodeKind::Web | NodeKind::Queue => {}
            }
        }
    }
    edges
}
