//! O consumo de uma bancada, em `workbenches/<id>/usage.json`: o que cada nó
//! gastou, por tarifa, e até onde cada transcript já foi lido.
//!
//! Soma incremental, e não recontagem: o transcript muda de arquivo a cada
//! `/clear` e a limpeza da bancada, e o que já foi contado não pode sumir nem
//! entrar de novo. O cursor guarda o byte e o último id lido.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

use super::model::{UsageByPrice, UsageEntry, add_entry, merge_usage, settled};
use super::prices::PriceTable;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct Cursor {
    pub offset: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_id: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct UsageLedger {
    pub by_node: BTreeMap<String, UsageByPrice>,
    pub cursors: BTreeMap<String, Cursor>,
}

impl UsageLedger {
    pub fn total(&self) -> UsageByPrice {
        self.by_node
            .values()
            .fold(UsageByPrice::new(), |acc, usage| merge_usage(&acc, usage))
    }

    pub fn absorb(&mut self, entries: &[UsageEntry], node: &str, prices: &PriceTable) {
        for entry in entries {
            add_entry(
                self.by_node.entry(node.to_owned()).or_default(),
                entry,
                prices,
            );
        }
    }

    /// Lê o que o arquivo ganhou desde a última vez. `data` é o arquivo a partir
    /// do cursor; só entra até a última quebra de linha — a linha que o CLI
    /// ainda está escrevendo fica para a próxima. `parse` é o leitor do formato
    /// do CLI (hoje, `claude::usage::entries`): o registro não sabe de CLI.
    pub fn absorb_chunk(
        &mut self,
        data: &[u8],
        path: &str,
        node: &str,
        prices: &PriceTable,
        parse: impl Fn(&[u8], Option<&str>) -> Vec<UsageEntry>,
    ) {
        let mut cursor = self.cursors.get(path).cloned().unwrap_or_default();
        let Some(end) = data.iter().rposition(|b| *b == b'\n') else {
            return;
        };
        let complete = &data[..=end];
        let entries = parse(complete, cursor.last_id.as_deref());
        self.absorb(&entries, node, prices);
        cursor.offset += complete.len() as u64;
        if let Some(last) = entries.last() {
            cursor.last_id = Some(last.id.clone());
        }
        self.cursors.insert(path.to_owned(), cursor);
    }

    /// Congela o que entrou sem preço, se a tabela já o tiver.
    pub fn settle(&mut self, prices: &PriceTable) {
        for usage in self.by_node.values_mut() {
            *usage = settled(usage, prices);
        }
    }
}
