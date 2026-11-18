//! A rota `/usage`. Casamento no Swift: `ControlSocket.swift:874`
//! (`case ("GET", _, _) where bare.hasSuffix("/usage")`).

use std::time::SystemTime;

use std::collections::BTreeMap;

use serde_json::{Map, Value, json};

use super::ledger::UsageLedger;
use super::model::{TokenUsage, UsageByPrice};
use super::prices::PriceTable;
use crate::protocol::handler::{RouteReply, RouteRequest};

/// O que a rota lê: o registro de cada bancada (a cópia que o `UsageStore`
/// publicou na última leitura — o store em si anda num job fora do ator), a
/// tabela de preços em vigor e as bancadas do app (`(id, nome)`, na ordem da
/// barra lateral).
pub struct UsageRoutes {
    pub ledgers: BTreeMap<String, UsageLedger>,
    pub prices: PriceTable,
    pub workbenches: Vec<(String, String)>,
}

/// Um efeito que a rota pede ao core: abrir o painel de consumo (`show=1`),
/// já com a tabela de preços à mostra (`prices=1`). A janela é da UI.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UsageEffect {
    ShowPanel { prices: bool },
}

fn tokens(usage: &TokenUsage) -> Value {
    json!({
        "input": usage.input, "output": usage.output,
        "cacheWrite5m": usage.cache_write5m, "cacheWrite1h": usage.cache_write1h,
        "cacheRead": usage.cache_read,
    })
}

fn node(prices: &PriceTable, by_price: &UsageByPrice) -> Value {
    let models: Map<String, Value> = by_price
        .iter()
        .map(|(key, spend)| (key.clone(), tokens(&spend.tokens)))
        .collect();
    json!({"cost": prices.cost(by_price).0, "models": models})
}

/// `/usage[?workbench=<nome>][&show=1[&prices=1]]` — o consumo das bancadas
/// (ADR-085): tokens por nó e por tarifa, e o custo pela tabela de preços.
pub fn usage(
    state: &mut UsageRoutes,
    req: &RouteRequest,
    _now: SystemTime,
) -> (RouteReply, Vec<UsageEffect>) {
    let wanted = req.param("workbench");
    let mut effects = Vec::new();
    if req.param("show") == Some("1") {
        effects.push(UsageEffect::ShowPanel {
            prices: req.param("prices") == Some("1"),
        });
    }
    let benches: Vec<Value> = state
        .workbenches
        .iter()
        .filter(|(_, name)| wanted.is_none_or(|w| w == name))
        .map(|(id, name)| {
            let ledger = state.ledgers.get(id).cloned().unwrap_or_default();
            let nodes: Map<String, Value> = ledger
                .by_node
                .iter()
                .map(|(n, by_price)| (n.clone(), node(&state.prices, by_price)))
                .collect();
            json!({
                "workbench": name, "id": id,
                "cost": state.prices.cost(&ledger.total()).0,
                "files": ledger.cursors.len(), "nodes": nodes,
            })
        })
        .collect();
    (
        RouteReply::ok(json!({"ok": true, "workbenches": benches})),
        effects,
    )
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::time::UNIX_EPOCH;

    use super::*;
    use crate::features::usage::store::{Source, UsageStore};

    fn request(target: &str) -> RouteRequest {
        let (path, query) = target.split_once('?').unwrap_or((target, ""));
        RouteRequest {
            method: "GET".into(),
            target: target.into(),
            path: path.into(),
            query: query
                .split('&')
                .filter_map(|p| p.split_once('='))
                .map(|(k, v)| (k.to_owned(), v.to_owned()))
                .collect(),
            body: Vec::new(),
            origin: None,
        }
    }

    fn line(id: &str, output: u64) -> String {
        format!(
            r#"{{"type":"assistant","message":{{"id":"{id}","model":"claude-opus-5-5","usage":{{"input_tokens":10,"output_tokens":{output},"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}}}}"#
        )
    }

    fn state() -> (UsageRoutes, tempfile::TempDir, tempfile::TempDir) {
        let home = tempfile::tempdir().expect("pasta");
        let user = tempfile::tempdir().expect("pasta");
        let transcript = user.path().join("t.jsonl");
        fs::write(
            &transcript,
            format!("{}\n{}\n", line("a", 1_000_000), line("b", 0)),
        )
        .expect("grava");
        let mut store = UsageStore::new(home.path().to_path_buf(), user.path().to_path_buf());
        let prices = PriceTable::from_built_in();
        let sources = BTreeMap::from([(
            "id1".to_owned(),
            vec![Source {
                node: "dev".into(),
                transcript,
            }],
        )]);
        store.refresh(&sources, &prices);
        let routes = UsageRoutes {
            ledgers: BTreeMap::from([("id1".to_owned(), store.ledger("id1"))]),
            prices,
            workbenches: vec![
                ("id1".into(), "deck".into()),
                ("id2".into(), "outra".into()),
            ],
        };
        (routes, home, user)
    }

    #[test]
    fn resposta_tem_as_chaves_do_swift() {
        let (mut routes, _h, _u) = state();
        let (reply, effects) = usage(&mut routes, &request("/usage"), UNIX_EPOCH);
        assert_eq!(reply.status, 200);
        assert!(effects.is_empty());
        assert_eq!(reply.json["ok"], true);
        let benches = reply.json["workbenches"].as_array().expect("lista");
        assert_eq!(benches.len(), 2);
        let deck = &benches[0];
        assert_eq!(deck["workbench"], "deck");
        assert_eq!(deck["id"], "id1");
        assert_eq!(deck["files"], 1);
        // 1 milhão de saída do Opus 5.5 a US$ 20/Mtok + 20 de entrada a US$ 4/Mtok.
        let cost = deck["cost"].as_f64().expect("custo");
        assert!((cost - 20.00008).abs() < 1e-6, "{cost}");
        let dev = &deck["nodes"]["dev"];
        assert_eq!(dev["cost"], deck["cost"]);
        assert_eq!(
            dev["models"]["claude-opus-5-5"],
            json!({"input": 20, "output": 1_000_000, "cacheWrite5m": 0, "cacheWrite1h": 0, "cacheRead": 0})
        );
        // Bancada sem consumo: custo zero, sem nós.
        assert_eq!(benches[1]["cost"], 0.0);
        assert_eq!(benches[1]["nodes"], json!({}));
    }

    #[test]
    fn filtra_pelo_nome_da_bancada() {
        let (mut routes, _h, _u) = state();
        let (reply, _) = usage(&mut routes, &request("/usage?workbench=outra"), UNIX_EPOCH);
        let benches = reply.json["workbenches"].as_array().expect("lista");
        assert_eq!(benches.len(), 1);
        assert_eq!(benches[0]["id"], "id2");
        let (none, _) = usage(&mut routes, &request("/usage?workbench=x"), UNIX_EPOCH);
        assert_eq!(none.json["workbenches"], json!([]));
    }

    #[test]
    fn show_pede_o_painel_ao_core() {
        let (mut routes, _h, _u) = state();
        let (_, effects) = usage(&mut routes, &request("/usage?show=1&prices=1"), UNIX_EPOCH);
        assert_eq!(effects, [UsageEffect::ShowPanel { prices: true }]);
        let (_, effects) = usage(&mut routes, &request("/usage?show=1"), UNIX_EPOCH);
        assert_eq!(effects, [UsageEffect::ShowPanel { prices: false }]);
    }
}
