//! A faixa de abas: o que ela mostra, em que ordem reabre, quem vira a ativa ao
//! fechar uma e a conta do arrasto para reordenar. Porte do `WorkbenchTab`, do
//! `WorkbenchTabs` e do `TabDragLayout`.
//!
//! Existe porque a barra lateral é o catálogo — tudo que existe, na árvore de
//! workspaces — e com dezenas de bancadas ela não responde à pergunta do dia a
//! dia: *o que está aberto agora, e qual delas quer alguma coisa de mim?* As
//! abas respondem só isso, na ordem em que você abriu.

use std::collections::HashMap;

use super::model::WorkbenchConfig;
use crate::features::activity::model::ActivitySummary;

/// O que uma aba mostra, derivado de quem está aberto e do estado dos
/// terminais. Dado puro: a tela só desenha.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkbenchTab {
    pub id: String,
    pub name: String,
    /// A que está na tela.
    pub is_active: bool,
    /// Os mesmos avisos da barra lateral, na mesma ordem fixa: trabalhando,
    /// precisa de você, terminou (ADR-024). Ordenar por urgência faria a
    /// bolinha trocar de lugar conforme a bancada anda.
    pub summary: ActivitySummary,
}

impl WorkbenchTab {
    pub fn is_working(&self) -> bool {
        self.summary.working > 0 || self.summary.starting > 0
    }

    pub fn wants_attention(&self) -> bool {
        self.summary.attention > 0
    }

    pub fn is_done(&self) -> bool {
        self.summary.done > 0
    }

    /// A aba inteira como texto — é o que o socket devolve.
    pub fn line(&self) -> String {
        let mut out = String::from(if self.is_active { "▸ " } else { "  " });
        out.push_str(&self.name);
        if self.is_working() {
            out.push_str(" ⠿");
        }
        if self.summary.background > 0 {
            out.push_str(" ⏳");
        }
        if self.wants_attention() {
            out.push_str(" ●!");
        }
        if self.is_done() {
            out.push_str(" ●");
        }
        out
    }
}

/// As abas, na ordem de `open`. Bancada que saiu da lista de configs (foi
/// removida) não vira aba órfã — some sozinha. O estado vem por NOME de
/// bancada (é como o Dispatcher agrega) e a aba é por id: a ponte é a lista de
/// configs, e renomear não apaga o badge.
pub fn build_tabs(
    open: &[String],
    configs: &[WorkbenchConfig],
    active: Option<&str>,
    activity: &HashMap<String, ActivitySummary>,
) -> Vec<WorkbenchTab> {
    open.iter()
        .filter_map(|id| {
            let config = configs.iter().find(|c| c.id == *id)?;
            Some(WorkbenchTab {
                id: id.clone(),
                name: config.name.clone(),
                is_active: active == Some(id.as_str()),
                summary: activity.get(&config.name).copied().unwrap_or_default(),
            })
        })
        .collect()
}

/// Fechar uma aba: quem entra no lugar é a vizinha da direita, e na falta dela
/// a da esquerda — como em qualquer editor. `None` quando não sobra nenhuma.
pub fn neighbour<'a>(id: &str, open: &'a [String]) -> Option<&'a str> {
    let i = open.iter().position(|o| o == id)?;
    open.get(i + 1)
        .or_else(|| i.checked_sub(1).and_then(|p| open.get(p)))
        .map(String::as_str)
}

/// As bancadas que estavam abertas na faixa quando o app fechou, na ordem em
/// que estavam (a da faixa, não a da barra lateral). Sem `tabOrder` = fechada.
pub fn tabs_to_reopen(configs: &[WorkbenchConfig]) -> Vec<&WorkbenchConfig> {
    let mut open: Vec<&WorkbenchConfig> =
        configs.iter().filter(|c| c.tab_order.is_some()).collect();
    open.sort_by_key(|c| c.tab_order.unwrap_or(0));
    open
}

// ── Arrastar aba para reordenar ────────────────────────────────────────────

/// O x de cada pastilha, na ordem, começando em `start` com `gap` entre elas.
pub fn tab_offsets(widths: &[f64], start: f64, gap: f64) -> Vec<f64> {
    let mut x = start;
    widths
        .iter()
        .map(|width| {
            let at = x;
            x += width + gap;
            at
        })
        .collect()
}

/// Para qual índice vai a pastilha arrastada, dado o CENTRO dela.
///
/// A pastilha acompanha o cursor e as vizinhas deslizam para abrir espaço, como
/// no VS Code; isso só funciona se a ordem for recalculada a cada passo do
/// mouse. A troca acontece quando o centro da arrastada passa o centro da
/// vizinha — e não quando as bordas se tocam: com bordas, abas de larguras
/// diferentes trocavam de lugar duas vezes no mesmo movimento, e a faixa
/// tremia.
pub fn tab_destination(
    center: f64,
    dragging: usize,
    widths: &[f64],
    start: f64,
    gap: f64,
) -> usize {
    if dragging >= widths.len() {
        return dragging;
    }
    let xs = tab_offsets(widths, start, gap);
    let mid = |i: usize| xs[i] + widths[i] / 2.0;
    let mut target = dragging;
    // Para a direita: passar o centro de quem está à frente.
    for i in (dragging + 1)..widths.len() {
        if center > mid(i) {
            target = i;
        }
    }
    // Para a esquerda: passar o centro de quem está atrás.
    if target == dragging {
        for i in (0..dragging).rev() {
            if center < mid(i) {
                target = i;
            }
        }
    }
    target
}

/// Reordena tirando de `from` e enfiando em `to`; índice fora da lista não
/// mexe em nada (o arrasto fica nesse estado se a bancada sair da faixa no meio
/// dele).
pub fn moved<T: Clone>(list: &[T], from: usize, to: usize) -> Vec<T> {
    if from >= list.len() || to >= list.len() || from == to {
        return list.to_vec();
    }
    let mut out = list.to_vec();
    let item = out.remove(from);
    out.insert(to, item);
    out
}
