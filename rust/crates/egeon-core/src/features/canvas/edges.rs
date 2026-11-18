//! As regras das ligações de uma bancada: criar, remover, ciclar, limitar e a
//! rota `/edge`. Porte do `EdgeController`.
//!
//! O controller do Swift não é dono de estado nenhum, e aqui menos ainda: cada
//! função recebe a bancada, aplica a regra e devolve o que mudou. Quem grava
//! (`persist`), loga e mostra o banner de ciclo é o ator, pelo [`EdgeOutcome`].
//! Vale para bancada que nem tem tela: a rota `/edge` não depende de canvas.

use std::collections::{HashSet, VecDeque};

use serde_json::{Value, json};

use crate::features::edge::{DEFAULT_SENDS, EdgeConfig, EdgeLink};
use crate::features::node::model::NodeKind;
use crate::features::workbench::model::WorkbenchConfig;

/// O que a regra fez, para o ator completar.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct EdgeOutcome {
    /// As arestas da bancada mudaram: gravar o `workbenches.json` e redesenhar.
    pub changed: bool,
    /// Linhas de log (`aresta[bancada]: …`).
    pub notes: Vec<String>,
    /// O aviso de ciclo que a tela mostra por uns 6 s. Só o de três nós ou mais.
    pub banner: Option<String>,
}

fn arrow(link: &EdgeLink) -> &'static str {
    if link.is_bidirectional() {
        "↔"
    } else if link.a_to_b {
        "→"
    } else {
        "←"
    }
}

fn kind_of(cfg: &WorkbenchConfig, id: &str) -> Option<NodeKind> {
    cfg.nodes.iter().find(|n| n.id == id).map(|n| n.kind)
}

/// Quem tem a porta "+" na borda: o terminal e a fila — é assim que a fila
/// ganha destino. O cartão `web` não fala com ninguém.
pub fn has_port(cfg: &WorkbenchConfig, id: &str) -> bool {
    matches!(
        kind_of(cfg, id),
        Some(NodeKind::Shell | NodeKind::Agent | NodeKind::Queue)
    )
}

/// Quem recebe a ligação: só terminal. O arrasto do Swift só solta em
/// `TerminalNode`, nunca numa fila.
fn is_target(cfg: &WorkbenchConfig, id: &str) -> bool {
    matches!(kind_of(cfg, id), Some(NodeKind::Shell | NodeKind::Agent))
}

/// Com quem `from` pode ligar agora: os terminais ainda sem ligação com ele,
/// em qualquer sentido (o par é uma linha só). Vazio para quem não tem porta.
pub fn linkable_from(cfg: &WorkbenchConfig, from: &str) -> Vec<String> {
    if !has_port(cfg, from) {
        return Vec::new();
    }
    let edges = cfg.edge_list();
    cfg.nodes
        .iter()
        .filter(|n| n.id != from && is_target(cfg, &n.id))
        .filter(|n| {
            !edges
                .iter()
                .any(|e| (e.from == from && e.to == n.id) || (e.from == n.id && e.to == from))
        })
        .map(|n| n.id.clone())
        .collect()
}

/// A regra do arrasto da porta, antes de criar: os dois nós existem e são
/// diferentes, a origem tem porta (terminal ou fila) e o alvo é um terminal.
/// Ligação que já existe não é erro — `add` a ignora.
pub fn check_link(cfg: &WorkbenchConfig, from: &str, to: &str) -> Result<(), String> {
    for id in [from, to] {
        if kind_of(cfg, id).is_none() {
            return Err(format!("nó desconhecido '{id}'"));
        }
    }
    if from == to {
        return Err("um nó não liga a si mesmo".to_owned());
    }
    if !has_port(cfg, from) {
        return Err(format!(
            "'{from}' não tem porta: só shell, agente e fila ligam"
        ));
    }
    if !is_target(cfg, to) {
        return Err(format!("'{to}' não recebe ligação: só shell e agente"));
    }
    Ok(())
}

/// Cria a ligação (ADR-028: nasce nos dois sentidos). Ligação que já existe,
/// em qualquer sentido, é ignorada.
pub fn add(cfg: &mut WorkbenchConfig, edge: EdgeConfig) -> EdgeOutcome {
    let mut edges = cfg.edge_list().to_vec();
    let reversed = EdgeConfig::with_default_limit(&edge.to, &edge.from);
    if edges.contains(&edge) || edges.contains(&reversed) {
        return EdgeOutcome::default();
    }
    edges.push(edge.clone());
    edges.push(reversed);
    cfg.edges = Some(edges.clone());

    let mut outcome = EdgeOutcome {
        changed: true,
        notes: vec![format!("aresta[{}]: {} ↔ {}", cfg.name, edge.from, edge.to)],
        banner: None,
    };
    // Ciclo é legítimo — revisor e implementador são exatamente isso — mas não
    // pode ser silencioso: é ele que faz duas máquinas conversarem sem você no
    // meio. Par conversando é o padrão, e `maxSends` é quem segura ele: avisar
    // em toda ligação criada transformaria o banner em ruído, e ruído não avisa
    // nada. O que ainda merece aviso é o ciclo de três nós ou mais, seguro só
    // pelo limite de cada seta (ADR-012, ADR-077).
    if let Some(path) = cycle(&edge, &edges)
        && path.len() > 3
    {
        let text = path.join(" → ");
        outcome.banner = Some(format!(
            "Ciclo: {text} — cada ligação dispara até o limite dela na mesma cadeia, depois recusa"
        ));
        outcome
            .notes
            .push(format!("aresta[{}]: ciclo {text}", cfg.name));
    }
    outcome
}

/// Remove a ligação inteira, os dois sentidos. Na tela é uma linha só, e tirar
/// metade do que se vê seria mais confuso que tirar tudo — para ficar com um
/// sentido só existe o botão de direção ao lado.
pub fn remove(cfg: &mut WorkbenchConfig, link: &EdgeLink) -> EdgeOutcome {
    let edges: Vec<EdgeConfig> = cfg
        .edge_list()
        .iter()
        .filter(|e| EdgeLink::pair(&e.from, &e.to) != (link.a.as_str(), link.b.as_str()))
        .cloned()
        .collect();
    cfg.edges = Some(edges);
    EdgeOutcome {
        changed: true,
        notes: vec![format!(
            "aresta[{}]: removida {} ↔ {}",
            cfg.name, link.a, link.b
        )],
        banner: None,
    }
}

/// Quantas idas e voltas esta ligação permite, como o diálogo digitou.
///
/// Vazio = sem limite próprio, sobra o teto da bancada. Texto que não é número
/// não muda nada, em vez de virar "sem limite": você digitou algo, e interpretar
/// isso como "libera" é o erro mais caro possível nesse campo. Grava nos dois
/// sentidos (na tela é uma linha, e um número que valesse só para a ida deixaria
/// a volta com o valor antigo) e nunca abaixo de 1.
pub fn edit_limit(cfg: &mut WorkbenchConfig, link: &EdgeLink, typed: &str) -> EdgeOutcome {
    let typed = typed.trim();
    let limit = if typed.is_empty() {
        None
    } else {
        typed.parse::<i64>().ok()
    };
    if !typed.is_empty() && limit.is_none() {
        return EdgeOutcome::default();
    }
    let mut updated = link.clone();
    updated.max_sends = limit.map(|n| n.max(1));
    replace(cfg, &updated);
    EdgeOutcome {
        changed: true,
        notes: vec![format!(
            "aresta[{}]: {} ↔ {} limite {}",
            cfg.name,
            link.a,
            link.b,
            limit.map_or_else(|| "nenhum".to_owned(), |n| n.to_string())
        )],
        banner: None,
    }
}

/// Troca a direção da ligação: ida → ida e volta → volta, e de volta ao começo.
pub fn cycle_direction(cfg: &mut WorkbenchConfig, link: &EdgeLink) -> EdgeOutcome {
    let next = link.cycled();
    replace(cfg, &next);
    EdgeOutcome {
        changed: true,
        notes: vec![format!(
            "aresta[{}]: {} {} {}",
            cfg.name,
            link.a,
            arrow(&next),
            link.b
        )],
        banner: None,
    }
}

/// A rota `/edge` por dentro: cria a ligação se ela não existe, e aponta,
/// inverte ou cicla a que existe. Devolve o corpo da resposta (`ok: false` é
/// 400).
///
/// Direção vazia é o caminho do arrasto: cria como o gesto cria, com o padrão da
/// casa. Existindo, vazio é CONSULTA — forçar bidirecional aqui faria uma
/// leitura mudar o que ela mede.
pub fn apply(
    cfg: &mut WorkbenchConfig,
    from: &str,
    to: &str,
    direction: &str,
) -> (Value, EdgeOutcome) {
    let none = EdgeOutcome::default;
    let known = |id: &str| cfg.nodes.iter().any(|n| n.id == id);
    if !known(from) || !known(to) || from == to {
        let error = format!("nó desconhecido ou igual: '{from}' / '{to}'");
        return (json!({"ok": false, "error": error}), none());
    }
    let (a, b) = EdgeLink::pair(from, to);
    let existing = EdgeLink::collapse(cfg.edge_list())
        .into_iter()
        .find(|l| l.a == a && l.b == b);
    let kept_limit = existing
        .as_ref()
        .and_then(|e| e.max_sends)
        .or(Some(DEFAULT_SENDS));
    let link = |a_to_b: bool, b_to_a: bool| EdgeLink {
        a: a.to_owned(),
        b: b.to_owned(),
        a_to_b,
        b_to_a,
        max_sends: kept_limit,
    };

    let target = match direction {
        "" => {
            if let Some(existing) = existing {
                return (edge_payload(Some(&existing), a, b), none());
            }
            let outcome = add(cfg, EdgeConfig::with_default_limit(from, to));
            let created = EdgeLink::collapse(cfg.edge_list())
                .into_iter()
                .find(|l| l.a == a && l.b == b);
            return (edge_payload(created.as_ref(), a, b), outcome);
        }
        "<->" | "both" => link(true, true),
        "->" => link(from == a, from != a),
        "<-" => link(from != a, from == a),
        // O que o X da linha faz. Está aqui pelo mesmo motivo que o resto da
        // rota: sem desfazer, verificar a criação de fora deixa lixo na bancada.
        "none" => {
            let gone = json!({"ok": true, "a": a, "b": b, "direction": "none", "edges": []});
            return match existing {
                None => (gone, none()),
                Some(existing) => (gone, remove(cfg, &existing)),
            };
        }
        "cycle" => match existing {
            None => {
                let error = format!("não há ligação entre '{a}' e '{b}' para ciclar");
                return (json!({"ok": false, "error": error}), none());
            }
            Some(existing) => existing.cycled(),
        },
        other => {
            let error = format!("direction desconhecida '{other}'; use ->, <-, <->, cycle ou none");
            return (json!({"ok": false, "error": error}), none());
        }
    };

    replace(cfg, &target);
    let outcome = EdgeOutcome {
        changed: true,
        notes: vec![format!(
            "aresta[{}]: {a} {} {b} (por /edge)",
            cfg.name,
            arrow(&target)
        )],
        banner: None,
    };
    (edge_payload(Some(&target), a, b), outcome)
}

fn edge_payload(link: Option<&EdgeLink>, a: &str, b: &str) -> Value {
    let Some(link) = link else {
        return json!({"ok": false, "error": format!("ligação {a}/{b} não existe")});
    };
    let direction = if link.is_bidirectional() {
        "<->"
    } else if link.a_to_b {
        "->"
    } else {
        "<-"
    };
    json!({
        "ok": true, "a": a, "b": b, "direction": direction,
        "maxSends": link.max_sends,
        "edges": link.edges().iter().map(|e| format!("{}→{}", e.from, e.to)).collect::<Vec<_>>(),
    })
}

/// Reescreve as arestas de um par com o que a ligação diz agora.
///
/// Na posição da primeira que existia, e não no fim da lista: o
/// `workbenches.json` é lido à mão, e uma ligação que salta para o fim do
/// arquivo a cada clique embaralharia o arquivo sem nada ter mudado de fato.
fn replace(cfg: &mut WorkbenchConfig, link: &EdgeLink) {
    let same_pair =
        |e: &EdgeConfig| EdgeLink::pair(&e.from, &e.to) == (link.a.as_str(), link.b.as_str());
    let current = cfg.edge_list();
    let mut edges: Vec<EdgeConfig> = current.iter().filter(|e| !same_pair(e)).cloned().collect();
    let position = current.iter().position(same_pair).unwrap_or(edges.len());
    let at = position.min(edges.len());
    edges.splice(at..at, link.edges());
    cfg.edges = Some(edges);
}

/// Caminho de volta de `edge.to` até `edge.from`, se existir — ou seja, o ciclo
/// que esta aresta acabou de fechar. Busca em largura: o ciclo mais curto é o
/// que descreve melhor o que foi criado.
pub fn cycle(edge: &EdgeConfig, edges: &[EdgeConfig]) -> Option<Vec<String>> {
    let mut queue: VecDeque<Vec<String>> = VecDeque::from([vec![edge.to.clone()]]);
    let mut seen: HashSet<&str> = HashSet::from([edge.to.as_str()]);
    while let Some(path) = queue.pop_front() {
        let last = path.last()?;
        if *last == edge.from {
            let mut out = path.clone();
            out.push(edge.to.clone());
            return Some(out);
        }
        for next in edges
            .iter()
            .filter(|e| e.from == *last)
            .map(|e| e.to.as_str())
        {
            if seen.insert(next) {
                let mut longer = path.clone();
                longer.push(next.to_owned());
                queue.push_back(longer);
            }
        }
    }
    None
}
