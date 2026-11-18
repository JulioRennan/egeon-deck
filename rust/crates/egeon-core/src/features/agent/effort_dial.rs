//! A regra do seletor de esforço do cabeçalho: uma marca por nível mais o
//! interruptor "auto". O desenho (slider, pílula, rolagem) é da UI; aqui só o
//! que ela mostra e escolhe.
//!
//! Auto é interruptor, não marca da trilha: como primeira marca, ele deixava a
//! barra vazia enquanto o modelo rodava em `high`, e não dava para saber de olhar
//! se o nó estava em auto ou num nível (ADR-090). Em auto a barra mostra,
//! apagada, o nível que o modelo usa; mexer nela escolhe um nível e desliga o
//! auto.
//!
//! A escolha só vale quando a mão para (a UI espera 1 s, e nunca com o botão
//! ainda apertado): cada troca reinicia o processo, e passar de `low` a `max`
//! nível a nível mataria o CLI quatro vezes no caminho. Enquanto não assenta, o
//! nome aparece com `…` ([`EffortDialState::is_pending`]).

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EffortDialState {
    levels: Vec<String>,
    /// Índice em `levels`; `None` é o auto.
    selection: Option<usize>,
    committed: Option<String>,
    /// O nível que "auto" dá neste modelo — `medium` no Opus 5.5. `None` quando
    /// não se sabe qual é o modelo.
    auto_level: Option<String>,
}

impl EffortDialState {
    /// `levels` vazio é modelo sem esforço: o slider fica desligado e diz isso.
    /// Nível escrito à mão no JSON e fora da lista continua valendo.
    pub fn new(levels: &[String], current: Option<&str>, auto_level: Option<&str>) -> Self {
        let mut levels = levels.to_vec();
        if let Some(current) = current.filter(|c| !c.is_empty())
            && !levels.is_empty()
            && !levels.iter().any(|l| l == current)
        {
            levels.push(current.to_owned());
        }
        let selection = current.and_then(|c| levels.iter().position(|l| l == c));
        let committed = selection.map(|i| levels[i].clone());
        EffortDialState {
            levels,
            selection,
            committed,
            auto_level: auto_level.map(str::to_owned),
        }
    }

    pub fn levels(&self) -> &[String] {
        &self.levels
    }

    pub fn value(&self) -> Option<&str> {
        self.selection.map(|i| self.levels[i].as_str())
    }

    pub fn is_auto(&self) -> bool {
        self.selection.is_none()
    }

    pub fn is_usable(&self) -> bool {
        !self.levels.is_empty()
    }

    /// A escolha ainda não assentou.
    pub fn is_pending(&self) -> bool {
        self.value() != self.committed.as_deref()
    }

    fn auto_index(&self) -> Option<usize> {
        let level = self.auto_level.as_deref()?;
        self.levels.iter().position(|l| l == level)
    }

    /// A posição da barra: a escolha, senão o nível do auto, senão a primeira
    /// marca.
    pub fn slider_index(&self) -> usize {
        self.selection.or(self.auto_index()).unwrap_or(0)
    }

    pub fn label(&self) -> String {
        if !self.is_usable() {
            return "sem esforço".to_owned();
        }
        let name = self.value().or(self.auto_level.as_deref()).unwrap_or("");
        format!("{name}{}", if self.is_pending() { "…" } else { "" })
    }

    /// Desligar parte do nível que o auto já usava: nada muda de fato até mexer.
    /// Sem saber qual é, o do meio, longe dos dois extremos caros.
    pub fn toggle_auto(&mut self) {
        let next = if self.is_auto() {
            Some(
                self.auto_index()
                    .unwrap_or(self.levels.len().saturating_sub(1) / 2),
            )
        } else {
            None
        };
        self.selection = next.filter(|_| self.is_usable());
    }

    /// A barra foi para `target` (arrasto, clique ou rolagem); fora da lista,
    /// fica na ponta. Escolher o que já está escolhido não faz nada.
    pub fn move_to(&mut self, target: i64) {
        if !self.is_usable() {
            return;
        }
        let top = self.levels.len() as i64 - 1;
        let clamped = target.clamp(0, top) as usize;
        if self.selection != Some(clamped) {
            self.selection = Some(clamped);
        }
    }

    /// A escolha assentou: o que valia passa a ser o que está no processo.
    /// Devolve o valor a aplicar (`None` é o padrão do CLI) quando mudou.
    pub fn settle(&mut self) -> Option<Option<String>> {
        if !self.is_pending() {
            return None;
        }
        let value = self.value().map(str::to_owned);
        self.committed.clone_from(&value);
        Some(value)
    }
}
