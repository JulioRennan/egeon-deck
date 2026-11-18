//! Regras da bancada que não pedem disco: cor, achar a bancada, template.
//!
//! Nome livre para bancada nova é `WorkbenchName::available` e o endereço
//! `bancada/nó` é `Address::parse`, ambos em `commons::ids`.

use super::model::{WorkbenchColor, WorkbenchConfig, WorkbenchTemplate};
use crate::features::node::model::NodeKind;

// ── Cor ────────────────────────────────────────────────────────────────────

/// A menos usada entre as automáticas, e no empate a primeira da paleta.
///
/// Gravada, e não tirada de um hash do id: com sete cores e seis abas, o hash
/// repete cor em quase toda combinação — e duas bancadas da mesma cor são
/// justamente a confusão que a cor existe para evitar.
pub fn pick_color(used: &[Option<WorkbenchColor>]) -> WorkbenchColor {
    let count = |color: &WorkbenchColor| used.iter().flatten().filter(|c| *c == color).count();
    WorkbenchColor::AUTOMATIC
        .iter()
        .copied()
        .min_by_key(count)
        .unwrap_or(WorkbenchColor::Blue)
}

/// Bancada gravada antes da cor existir ganha uma ao carregar, na ordem da
/// lista — as primeiras sete saem todas diferentes.
pub fn assign_missing_colors(list: &mut [WorkbenchConfig]) {
    for index in 0..list.len() {
        if list[index].color.is_none() {
            let used: Vec<_> = list.iter().map(|w| w.color).collect();
            list[index].color = Some(pick_color(&used));
        }
    }
}

/// Esta bancada, com cor escolhida contra as que já estão em `others`.
pub fn colored_among(
    mut workbench: WorkbenchConfig,
    others: &[WorkbenchConfig],
) -> WorkbenchConfig {
    if workbench.color.is_none() {
        let used: Vec<_> = others.iter().map(|w| w.color).collect();
        workbench.color = Some(pick_color(&used));
    }
    workbench
}

// ── Achar a bancada ────────────────────────────────────────────────────────

/// A tradução entre os três jeitos de apontar para uma bancada: a **posição**
/// na lista (como a barra lateral pensa), o **id** (nasce com a bancada e
/// sobrevive a rename e a arrasto) e o **nome** (como o socket e os endereços
/// falam).
///
/// Posição envelhece: remover ou mover uma bancada desloca todo mundo à
/// direita, e quem guardou o número passa a apontar para outra bancada.
pub fn id_at(index: i64, configs: &[WorkbenchConfig]) -> Option<&str> {
    usize::try_from(index)
        .ok()
        .and_then(|i| configs.get(i))
        .map(|w| w.id.as_str())
}

pub fn index_of_id(id: &str, configs: &[WorkbenchConfig]) -> Option<usize> {
    configs.iter().position(|w| w.id == id)
}

pub fn index_of_name(name: &str, configs: &[WorkbenchConfig]) -> Option<usize> {
    configs.iter().position(|w| w.name == name)
}

pub fn id_of_name<'a>(name: &str, configs: &'a [WorkbenchConfig]) -> Option<&'a str> {
    configs
        .iter()
        .find(|w| w.name == name)
        .map(|w| w.id.as_str())
}

// ── Template ───────────────────────────────────────────────────────────────

/// Monta um template a partir dos nós de uma bancada.
///
/// Guarda tudo que define a montagem — tipos, layout, agente, `cwd`, pasta do
/// projeto — e descarta o que é estado da bancada que serviu de molde: a rota
/// em que o nó web estava, da qual sobra a origem, e a conversa de cada
/// agente. Um molde não carrega o que foi dito dentro dele.
pub fn capture_template(workbench: &WorkbenchConfig) -> WorkbenchTemplate {
    let nodes = workbench
        .nodes
        .iter()
        .cloned()
        .map(|mut node| {
            if node.kind == NodeKind::Web {
                node.url = node.url.map(|raw| base_url(&raw));
            }
            node.without_conversation()
        })
        .collect();
    WorkbenchTemplate {
        nodes,
        base_path: Some(workbench.path.clone()),
        view: workbench.view,
    }
}

/// `http://localhost:3000/farms/123` → `http://localhost:3000`.
///
/// Um preset que reabrisse a rota exata carregaria o estado de navegação de
/// outra bancada. Texto que não é uma URL com esquema e host volta como veio.
pub fn base_url(raw: &str) -> String {
    let invalid = raw.chars().any(|c| c.is_whitespace() || c.is_control());
    let Some((scheme, rest)) = raw.split_once("://") else {
        return raw.to_owned();
    };
    let scheme_ok = scheme
        .chars()
        .next()
        .is_some_and(|c| c.is_ascii_alphabetic())
        && scheme
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.'));
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    let host_port = authority.rsplit_once('@').map_or(authority, |(_, h)| h);
    // A porta é o que vem depois do último `:` e só tem dígitos (`[::1]` fica inteiro).
    let (host, port) = match host_port.rsplit_once(':') {
        Some((host, port)) if !port.is_empty() && port.chars().all(|c| c.is_ascii_digit()) => {
            (host, Some(port))
        }
        _ => (host_port, None),
    };
    if invalid || !scheme_ok || host.is_empty() {
        return raw.to_owned();
    }
    match port {
        Some(port) => format!("{scheme}://{host}:{port}"),
        None => format!("{scheme}://{host}"),
    }
}
