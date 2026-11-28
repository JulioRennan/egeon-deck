//! Porte do EdgeControllerTests — o controller com a bancada em memória e sem
//! canvas: a rota `/edge` vale para bancada sem tela.

use serde_json::json;

use super::edges::*;
use crate::features::edge::{EdgeConfig, EdgeLink};
use crate::features::workbench::model::WorkbenchConfig;

fn config() -> WorkbenchConfig {
    serde_json::from_str(
        r#"{"name":"ws","path":"/tmp/ws","nodes":[
            {"type":"agent","id":"a"},{"type":"agent","id":"b"},{"type":"agent","id":"c"}]}"#,
    )
    .unwrap()
}

fn edge(from: &str, to: &str) -> EdgeConfig {
    EdgeConfig::with_default_limit(from, to)
}

fn pairs(cfg: &WorkbenchConfig) -> Vec<String> {
    cfg.edge_list()
        .iter()
        .map(|e| format!("{}>{}", e.from, e.to))
        .collect()
}

fn link_of(cfg: &WorkbenchConfig) -> EdgeLink {
    EdgeLink::collapse(cfg.edge_list()).remove(0)
}

// ADR-028: ligação nova nasce nos dois sentidos.
#[test]
fn a_ligacao_nasce_nos_dois_sentidos() {
    let mut cfg = config();
    let outcome = add(&mut cfg, edge("a", "b"));
    assert_eq!(pairs(&cfg), ["a>b", "b>a"]);
    assert!(cfg.edge_list().contains(&edge("a", "b")) && cfg.edge_list().contains(&edge("b", "a")));
    assert!(outcome.changed, "tem de gravar");
    assert_eq!(outcome.notes, ["aresta[ws]: a ↔ b"]);
    assert_eq!(
        outcome.banner, None,
        "par conversando é o padrão: sem aviso"
    );
}

#[test]
fn ligacao_repetida_e_ignorada() {
    let mut cfg = config();
    add(&mut cfg, edge("a", "b"));
    assert!(!add(&mut cfg, edge("a", "b")).changed);
    assert!(!add(&mut cfg, edge("b", "a")).changed);
    assert_eq!(cfg.edge_list().len(), 2);
}

// O X da linha leva os dois sentidos: na tela o par é uma linha só.
#[test]
fn remover_leva_os_dois_sentidos() {
    let mut cfg = config();
    add(&mut cfg, edge("a", "b"));
    add(&mut cfg, edge("a", "c"));
    let link = link_of(&cfg);
    let outcome = remove(&mut cfg, &link);
    assert_eq!(pairs(&cfg), ["a>c", "c>a"]);
    assert!(outcome.changed);
    assert_eq!(outcome.notes, ["aresta[ws]: removida a ↔ b"]);
    // Tirar a última deixa a lista vazia, não ausente.
    let link = link_of(&cfg);
    remove(&mut cfg, &link);
    assert_eq!(cfg.edges, Some(vec![]));
}

// A rota /edge sem direção: cria com o padrão da casa quando não existe, e é
// CONSULTA quando existe — leitura não muda o que mede.
#[test]
fn direcao_vazia_cria_e_depois_so_consulta() {
    let mut cfg = config();
    let (created, outcome) = apply(&mut cfg, "a", "b", "");
    assert_eq!(created["direction"], "<->");
    assert!(outcome.changed);

    apply(&mut cfg, "a", "b", "->");
    let (queried, outcome) = apply(&mut cfg, "a", "b", "");
    assert_eq!(queried["direction"], "->");
    assert!(!outcome.changed, "consultar não grava");
    assert_eq!(cfg.edge_list().len(), 1);
}

#[test]
fn none_desfaz_a_ligacao() {
    let mut cfg = config();
    apply(&mut cfg, "a", "b", "");
    let (result, outcome) = apply(&mut cfg, "a", "b", "none");
    assert_eq!(
        result,
        json!({"ok": true, "a": "a", "b": "b", "direction": "none", "edges": []})
    );
    assert!(outcome.changed);
    assert!(cfg.edge_list().is_empty());
    // Sem ligação, `none` responde igual e não mexe em nada.
    let (again, outcome) = apply(&mut cfg, "a", "b", "none");
    assert_eq!(again["ok"], true);
    assert!(!outcome.changed);
}

#[test]
fn no_desconhecido_ou_igual_e_recusado() {
    let mut cfg = config();
    let (result, outcome) = apply(&mut cfg, "a", "zzz", "->");
    assert_eq!(result["ok"], false);
    assert_eq!(result["error"], "nó desconhecido ou igual: 'a' / 'zzz'");
    assert!(cfg.edge_list().is_empty() && !outcome.changed);
    assert_eq!(apply(&mut cfg, "a", "a", "->").0["ok"], false);
}

#[test]
fn as_direcoes_da_rota_e_a_resposta_com_as_chaves_de_hoje() {
    let mut cfg = config();
    let (r, _) = apply(&mut cfg, "b", "a", "->");
    assert_eq!(
        r,
        json!({"ok": true, "a": "a", "b": "b", "direction": "<-", "maxSends": 2, "edges": ["b→a"]})
    );
    assert_eq!(
        apply(&mut cfg, "a", "b", "<->").0["edges"],
        json!(["a→b", "b→a"])
    );
    assert_eq!(apply(&mut cfg, "a", "b", "both").0["direction"], "<->");
    assert_eq!(apply(&mut cfg, "a", "b", "<-").0["edges"], json!(["b→a"]));
    // `cycle` é exatamente o botão da linha: volta → ida.
    assert_eq!(apply(&mut cfg, "a", "b", "cycle").0["direction"], "->");
    assert_eq!(apply(&mut cfg, "a", "b", "cycle").0["direction"], "<->");
    let (bad, _) = apply(&mut cfg, "a", "b", "lado");
    assert_eq!(
        bad["error"],
        "direction desconhecida 'lado'; use ->, <-, <->, cycle ou none"
    );
    let (none, _) = apply(&mut config(), "a", "b", "cycle");
    assert_eq!(none["error"], "não há ligação entre 'a' e 'b' para ciclar");
}

// O limite da ligação sobrevive a trocar a direção; null vira o padrão (quirk
// do Swift: `existente?.maxSends ?? defaultSends`).
#[test]
fn o_limite_acompanha_a_ligacao() {
    let mut cfg = config();
    cfg.edges = Some(vec![
        EdgeConfig::new("a", "b", Some(7)),
        EdgeConfig::new("b", "a", Some(7)),
    ]);
    let (r, _) = apply(&mut cfg, "a", "b", "->");
    assert_eq!(r["maxSends"], 7);
    cfg.edges = Some(vec![EdgeConfig::new("a", "b", None)]);
    assert_eq!(apply(&mut cfg, "a", "b", "<->").0["maxSends"], 2);
}

// Na posição da primeira que existia, e não no fim: o arquivo é lido à mão.
#[test]
fn reescrever_mantem_a_posicao_no_arquivo() {
    let mut cfg = config();
    add(&mut cfg, edge("a", "b"));
    add(&mut cfg, edge("a", "c"));
    assert_eq!(pairs(&cfg), ["a>b", "b>a", "a>c", "c>a"]);
    let link = EdgeLink::collapse(cfg.edge_list()).remove(0);
    let outcome = cycle_direction(&mut cfg, &link);
    assert_eq!(
        pairs(&cfg),
        ["b>a", "a>c", "c>a"]
            .map(String::from)
            .to_vec()
            .into_iter()
            .collect::<Vec<_>>(),
        "ida e volta → só a volta, no lugar da primeira"
    );
    assert_eq!(outcome.notes, ["aresta[ws]: a ← b"]);
}

#[test]
fn o_limite_digitado() {
    let mut cfg = config();
    add(&mut cfg, edge("a", "b"));
    let link = link_of(&cfg);

    let outcome = edit_limit(&mut cfg, &link, " 5 ");
    assert!(outcome.changed);
    assert_eq!(outcome.notes, ["aresta[ws]: a ↔ b limite 5"]);
    assert!(
        cfg.edge_list().iter().all(|e| e.max_sends == Some(5)),
        "nos dois sentidos"
    );

    // Zero e negativo sobem para 1: travar de vez não é um limite.
    {
        let l = link_of(&cfg);
        edit_limit(&mut cfg, &l, "0")
    };
    assert!(cfg.edge_list().iter().all(|e| e.max_sends == Some(1)));

    // Vazio é sem limite — e só aperta de novo se alguém digitar.
    let outcome = {
        let l = link_of(&cfg);
        edit_limit(&mut cfg, &l, "")
    };
    assert_eq!(outcome.notes, ["aresta[ws]: a ↔ b limite nenhum"]);
    assert!(cfg.edge_list().iter().all(|e| e.max_sends.is_none()));

    // Texto que não é número não vira "sem limite": não muda nada.
    {
        let l = link_of(&cfg);
        edit_limit(&mut cfg, &l, "3")
    };
    let before = cfg.clone();
    let outcome = {
        let l = link_of(&cfg);
        edit_limit(&mut cfg, &l, "muito")
    };
    assert!(!outcome.changed);
    assert_eq!(cfg, before);
}

// O aviso de ciclo é só para o que o teto da bancada segura: três nós ou mais.
#[test]
fn o_ciclo_e_achado_em_largura() {
    let edges = [
        EdgeConfig::new("a", "b", None),
        EdgeConfig::new("b", "c", None),
        EdgeConfig::new("c", "a", None),
    ];
    let found = cycle(&EdgeConfig::new("c", "a", None), &edges);
    assert_eq!(found, Some(["a", "b", "c", "a"].map(String::from).to_vec()));
    assert_eq!(
        cycle(
            &EdgeConfig::new("a", "b", None),
            &[EdgeConfig::new("a", "b", None)]
        ),
        None
    );
}

// Defeito do Swift portado: `add` põe a ligação nos DOIS sentidos antes de
// procurar o ciclo, então o caminho mais curto de volta é sempre a própria
// ligação ao contrário (dois nós) e o aviso de ciclo de três ou mais nunca
// aparece por aqui. A busca em si acha o de três (teste acima).
#[test]
fn o_aviso_de_ciclo_de_tres_nunca_dispara_pelo_add_como_no_swift() {
    let mut cfg = config();
    cfg.edges = Some(vec![
        EdgeConfig::new("a", "b", None),
        EdgeConfig::new("b", "c", None),
    ]);
    let outcome = add(&mut cfg, edge("c", "a"));
    assert!(outcome.changed);
    assert_eq!(outcome.banner, None);
    assert_eq!(outcome.notes, ["aresta[ws]: c ↔ a"]);
}

// ── Quem liga com quem (a regra do arrasto da porta) ───────────────────────

fn mixed() -> WorkbenchConfig {
    serde_json::from_str(
        r#"{"name":"ws","path":"/tmp/ws","nodes":[
            {"type":"agent","id":"a"},{"type":"shell","id":"b"},
            {"type":"web","id":"w"},{"type":"queue","id":"q"},{"type":"agent","id":"c"}]}"#,
    )
    .unwrap()
}

#[test]
fn so_terminal_liga_com_terminal_e_o_par_ja_ligado_sai_da_lista() {
    let mut cfg = mixed();
    assert_eq!(linkable_from(&cfg, "a"), ["b", "c"]);
    assert!(linkable_from(&cfg, "w").is_empty(), "web não tem porta");
    assert_eq!(
        linkable_from(&cfg, "q"),
        ["a", "b", "c"],
        "a fila tem porta: é assim que ganha destino"
    );
    assert!(linkable_from(&cfg, "fantasma").is_empty());

    add(&mut cfg, edge("a", "b"));
    assert_eq!(linkable_from(&cfg, "a"), ["c"]);
    assert_eq!(linkable_from(&cfg, "b"), ["c"], "vale nos dois sentidos");
}

#[test]
fn ligacao_invalida_e_recusada_com_o_motivo() {
    let cfg = mixed();
    assert_eq!(check_link(&cfg, "a", "b"), Ok(()));
    assert_eq!(
        check_link(&cfg, "a", "a"),
        Err("um nó não liga a si mesmo".into())
    );
    assert_eq!(
        check_link(&cfg, "a", "zz"),
        Err("nó desconhecido 'zz'".into())
    );
    assert_eq!(
        check_link(&cfg, "a", "w"),
        Err("'w' não recebe ligação: só shell e agente".into())
    );
    assert_eq!(
        check_link(&cfg, "w", "a"),
        Err("'w' não tem porta: só shell, agente e fila ligam".into())
    );
    assert_eq!(
        check_link(&cfg, "q", "a"),
        Ok(()),
        "a fila liga a um agente"
    );
    assert_eq!(
        check_link(&cfg, "a", "q"),
        Err("'q' não recebe ligação: só shell e agente".into()),
        "ninguém solta numa fila"
    );
}
