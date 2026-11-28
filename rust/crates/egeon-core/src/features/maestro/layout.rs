//! O arranjo que o maestro dá à bancada quando a monta (ADR-066). Porte de
//! `MaestroLayout.swift`.
//!
//! O maestro à esquerda; os agentes em grade ao lado; os terminais normais
//! numa faixa embaixo, mais baixos — são log, não conversa; o navegador por
//! último, com o tamanho que já tem. Coordenadas do documento do canvas: y
//! cresce para baixo.

use std::collections::{BTreeMap, HashMap, HashSet};

use crate::features::edge::model::EdgeConfig;
use crate::features::node::model::{Frame, NodeConfig, NodeKind};

pub const MARGIN: f64 = 40.0;
pub const GAP: f64 = 40.0;
/// Vão entre agentes com seta desenhada entre eles: a linha, a curva e as
/// pontas precisam de onde aparecer. Maior na horizontal, onde a ligação é
/// curva e os controles dela se penduram no meio.
pub const LINKED_GAP: f64 = 160.0;
pub const LINKED_GAP_X: f64 = 320.0;
pub const AGENT: (f64, f64) = (720.0, 460.0);
pub const SHELL: (f64, f64) = (640.0, 320.0);

fn max_x(f: &Frame) -> f64 {
    f.x + f.w
}

fn max_y(f: &Frame) -> f64 {
    f.y + f.h
}

fn mid_y(f: &Frame) -> f64 {
    f.y + f.h / 2.0
}

fn rect(x: f64, y: f64, (w, h): (f64, f64)) -> Frame {
    Frame { x, y, w, h }
}

/// Dois lado a lado até quatro, três dali em diante.
pub fn columns(count: usize) -> usize {
    match count {
        0 | 1 => 1,
        2..=4 => 2,
        _ => 3,
    }
}

/// O maestro fica onde está — é a âncora: o time se arruma à direita dele,
/// alinhado pelo topo. Só sem frame ele ganha uma coluna da altura do time.
pub fn frames(nodes: &[NodeConfig], edges: &[EdgeConfig]) -> BTreeMap<String, Frame> {
    let maestros: Vec<&NodeConfig> = nodes.iter().filter(|n| n.is_maestro()).collect();
    let workers: Vec<&NodeConfig> = nodes
        .iter()
        .filter(|n| n.kind == NodeKind::Agent && !n.is_maestro())
        .collect();
    let shells = nodes.iter().filter(|n| n.kind == NodeKind::Shell);
    let others = nodes
        .iter()
        .filter(|n| matches!(n.kind, NodeKind::Web | NodeKind::Queue));

    let ids: HashSet<&str> = workers.iter().map(|n| n.id.as_str()).collect();
    let linked = edges
        .iter()
        .any(|e| ids.contains(e.from.as_str()) && ids.contains(e.to.as_str()));
    let team_gap = if linked { LINKED_GAP } else { GAP };
    let team_gap_x = if linked { LINKED_GAP_X } else { GAP };

    let mut frames: BTreeMap<String, Frame> = BTreeMap::new();
    let cols = columns(workers.len());
    let rows = if workers.is_empty() {
        1
    } else {
        workers.len().div_ceil(cols)
    };
    let team_height = rows as f64 * AGENT.1 + (rows as f64 - 1.0) * team_gap;

    let (ox, oy) = maestros
        .iter()
        .find_map(|m| m.frame())
        .map_or((MARGIN, MARGIN), |f| (f.x, f.y));
    let mut x = ox;
    for maestro in &maestros {
        let frame = maestro
            .frame()
            .unwrap_or_else(|| rect(x, oy, (AGENT.0, team_height)));
        frames.insert(maestro.id.clone(), frame);
        x = x.max(max_x(&frame) + GAP);
    }
    if linked {
        let ids: Vec<String> = workers.iter().map(|n| n.id.clone()).collect();
        frames.extend(layered(&ids, edges, (x, oy)));
    } else {
        for (i, node) in workers.iter().enumerate() {
            let fx = x + (i % cols) as f64 * (AGENT.0 + team_gap_x);
            let fy = oy + (i / cols) as f64 * (AGENT.1 + team_gap);
            frames.insert(node.id.clone(), rect(fx, fy, AGENT));
        }
    }

    // A faixa de baixo quebra na largura do que está em cima, para a bancada
    // continuar um bloco só.
    let top = frames.values().map(max_y).fold(f64::NEG_INFINITY, f64::max);
    let top = if top.is_finite() { top } else { oy };
    let widest = frames.values().map(max_x).reduce(f64::max).unwrap_or(0.0);
    let width = widest.max(ox + AGENT.0);
    let (mut cx, mut cy) = (ox, if frames.is_empty() { oy } else { top + GAP });
    let mut row_height: f64 = 0.0;
    for node in shells.chain(others) {
        let size = if node.kind == NodeKind::Shell {
            SHELL
        } else {
            node.frame().map_or(AGENT, |f| (f.w, f.h))
        };
        if cx > ox && cx + size.0 > width {
            cx = ox;
            cy += row_height + GAP;
            row_height = 0.0;
        }
        frames.insert(node.id.clone(), rect(cx, cy, size));
        cx += size.0 + GAP;
        row_height = row_height.max(size.1);
    }
    frames
}

/// Os agentes pelo fluxo das setas desenhadas, da esquerda para a direita,
/// ancorados à DIREITA no destino: quem mais recebe do que manda fica na
/// última coluna, e cada outro a tantas colunas dele quanto o caminho mais
/// curto até lá. Na coluna, cada card se centra na altura média de quem aponta
/// para ele; sobreposição empurra para baixo.
pub fn layered(
    ids: &[String],
    edges: &[EdgeConfig],
    origin: (f64, f64),
) -> BTreeMap<String, Frame> {
    let members: HashSet<&str> = ids.iter().map(String::as_str).collect();
    let links: Vec<&EdgeConfig> = edges
        .iter()
        .filter(|e| {
            members.contains(e.from.as_str()) && members.contains(e.to.as_str()) && e.from != e.to
        })
        .collect();
    let mut score: HashMap<&str, i64> = ids.iter().map(|id| (id.as_str(), 0)).collect();
    for edge in &links {
        *score.entry(edge.to.as_str()).or_default() += 1;
        *score.entry(edge.from.as_str()).or_default() -= 1;
    }
    let top = score.values().copied().max().unwrap_or(0);
    let sinks: Vec<&str> = if top > 0 {
        ids.iter()
            .map(String::as_str)
            .filter(|id| score.get(id) == Some(&top))
            .collect()
    } else {
        Vec::new()
    };

    let mut distance: HashMap<&str, usize> = HashMap::new();
    let mut frontier = sinks.clone();
    for sink in &sinks {
        distance.insert(sink, 0);
    }
    while !frontier.is_empty() {
        let mut next = Vec::new();
        for id in frontier {
            let here = distance.get(id).copied().unwrap_or(0);
            for edge in links.iter().filter(|e| e.to == id) {
                if !distance.contains_key(edge.from.as_str()) {
                    distance.insert(edge.from.as_str(), here + 1);
                    next.push(edge.from.as_str());
                }
            }
        }
        frontier = next;
    }
    let deepest = distance.values().copied().max().unwrap_or(0);
    let column: HashMap<&str, usize> = ids
        .iter()
        .map(|id| {
            let d = distance.get(id.as_str()).copied().unwrap_or(deepest);
            (id.as_str(), deepest - d)
        })
        .collect();

    let mut frames: BTreeMap<String, Frame> = BTreeMap::new();
    let step = AGENT.1 + LINKED_GAP;
    let last = column.values().copied().max().unwrap_or(0);
    for c in 0..=last {
        let here: Vec<&str> = ids
            .iter()
            .map(String::as_str)
            .filter(|id| column.get(id) == Some(&c))
            .collect();
        let wanted: HashMap<&str, f64> = here
            .iter()
            .map(|id| {
                let centers: Vec<f64> = links
                    .iter()
                    .filter(|e| e.to == *id)
                    .filter_map(|e| {
                        let from = frames.get(&e.from)?;
                        (column.get(e.from.as_str()).copied().unwrap_or(usize::MAX) < c)
                            .then(|| mid_y(from))
                    })
                    .collect();
                let y = if centers.is_empty() {
                    f64::MAX
                } else {
                    centers.iter().sum::<f64>() / centers.len() as f64 - AGENT.1 / 2.0
                };
                (*id, y)
            })
            .collect();
        let mut order: Vec<(usize, &str)> = here.iter().copied().enumerate().collect();
        order.sort_by(|a, b| {
            let wa = wanted.get(a.1).copied().unwrap_or(f64::MAX);
            let wb = wanted.get(b.1).copied().unwrap_or(f64::MAX);
            wa.total_cmp(&wb).then(a.0.cmp(&b.0))
        });
        let mut next = origin.1;
        for (rank, (_, id)) in order.into_iter().enumerate() {
            let want = wanted.get(id).copied().unwrap_or(f64::MAX);
            let desired = if want == f64::MAX {
                origin.1 + rank as f64 * step
            } else {
                want
            };
            let y = desired.max(next);
            let x = origin.0 + c as f64 * (AGENT.0 + LINKED_GAP_X);
            frames.insert(id.to_owned(), rect(x, y, AGENT));
            next = y + step;
        }
    }
    frames
}
