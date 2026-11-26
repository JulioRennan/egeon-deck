//! Testes portados de `UsageTests`.

use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use serde_json::json;

use super::prices::{self, PriceTable, canonical};
use super::store::{self, Source, UsageStore};
use super::*;
use crate::features::agent::claude::usage as claude_usage;

#[allow(clippy::too_many_arguments)]
fn line(
    id: &str,
    model: &str,
    input: u64,
    output: u64,
    write5m: u64,
    write1h: u64,
    read: u64,
    speed: &str,
    text: &str,
) -> String {
    format!(
        r#"{{"type":"assistant","message":{{"id":"{id}","model":"{model}","content":[{{"type":"text","text":"{text}"}}],"usage":{{"input_tokens":{input},"output_tokens":{output},"cache_creation_input_tokens":{},"cache_read_input_tokens":{read},"cache_creation":{{"ephemeral_5m_input_tokens":{write5m},"ephemeral_1h_input_tokens":{write1h}}},"speed":"{speed}"}}}}}}"#,
        write5m + write1h
    )
}

fn simple(id: &str) -> String {
    line(id, "claude-opus-5-5", 10, 100, 0, 0, 0, "standard", "oi")
}

fn unpriced(tokens: TokenUsage) -> Spend {
    Spend {
        tokens,
        pending: tokens,
        ..Spend::default()
    }
}

fn near(a: f64, b: f64) {
    assert!((a - b).abs() < 0.0001, "{a} != {b}");
}

fn table() -> PriceTable {
    PriceTable::from_built_in()
}

#[test]
fn entradas_contam_cada_mensagem_uma_vez() {
    let jsonl = [
        line("a", "claude-opus-5-5", 10, 100, 0, 30, 0, "standard", "oi"),
        line("a", "claude-opus-5-5", 10, 100, 0, 30, 0, "standard", "oi"),
        line("b", "claude-opus-5-5", 10, 100, 0, 0, 500, "standard", "oi"),
        r#"{"type":"user","message":{"content":"x"}}"#.to_owned(),
        line("c", "<synthetic>", 10, 100, 0, 0, 0, "standard", "oi"),
    ]
    .join("\n")
        + "\n";
    let entries = claude_usage::entries(jsonl.as_bytes(), None);
    assert_eq!(
        entries.iter().map(|e| e.id.as_str()).collect::<Vec<_>>(),
        ["a", "b"]
    );
    assert_eq!(
        entries[0].usage,
        TokenUsage {
            input: 10,
            output: 100,
            cache_write1h: 30,
            ..TokenUsage::default()
        }
    );
    // A leitura que parte no meio das linhas de "a" não a conta de novo.
    let after = claude_usage::entries(jsonl.as_bytes(), Some("a"));
    assert_eq!(
        after.iter().map(|e| e.id.as_str()).collect::<Vec<_>>(),
        ["b"]
    );
}

#[test]
fn escrita_de_cache_sem_divisao_e_de_cinco_minutos() {
    let raw = br#"{"type":"assistant","message":{"id":"x","model":"claude-sonnet-5-5","usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":40,"cache_read_input_tokens":0}}}"#;
    assert_eq!(
        claude_usage::entry_from_line(raw).map(|e| e.usage.cache_write5m),
        Some(40)
    );
}

#[test]
fn chaves_de_preco_e_custo() {
    let prices = table();
    let opus = prices::entry(
        "1",
        "claude-opus-5-5",
        TokenUsage {
            input: 1_000_000,
            output: 1_000_000,
            cache_write5m: 1_000_000,
            cache_write1h: 1_000_000,
            cache_read: 1_000_000,
        },
    );
    assert_eq!(prices.key(&opus), "claude-opus-5-5");
    // 4 + 20 + 5 (1,25×) + 8 (2×) + 0,20
    let usage = BTreeMap::from([(prices.key(&opus), unpriced(opus.usage))]);
    near(prices.cost(&usage).0, 37.2);

    let mut fast = opus.clone();
    fast.fast = true;
    assert_eq!(prices.key(&fast), "claude-opus-5-5#fast");
    let usage = BTreeMap::from([("claude-opus-5-5#fast".to_owned(), unpriced(opus.usage))]);
    near(prices.cost(&usage).0, 74.4);

    let short = prices::entry(
        "2",
        "claude-haiku-5-5",
        TokenUsage {
            input: 90_000,
            ..TokenUsage::default()
        },
    );
    let long = prices::entry(
        "3",
        "claude-haiku-5-5",
        TokenUsage {
            input: 1_000,
            cache_read: 150_000,
            ..TokenUsage::default()
        },
    );
    assert_eq!(prices.key(&short), "claude-haiku-5-5");
    assert_eq!(prices.key(&long), "claude-haiku-5-5#long");

    assert_eq!(canonical("claude-haiku-4-5-20251001"), "claude-haiku-4-5");
    let usage = BTreeMap::from([(
        "claude-futuro-9".to_owned(),
        unpriced(TokenUsage {
            input: 5,
            ..TokenUsage::default()
        }),
    )]);
    let (dollars, unknown) = prices.cost(&usage);
    assert!(unknown);
    assert_eq!(dollars, 0.0);
}

#[test]
fn registro_le_so_linhas_completas_e_guarda_o_cursor() {
    let prices = table();
    let mut ledger = UsageLedger::default();
    let first = format!("{}\n{}\n", simple("a"), simple("a"));
    let partial: String = simple("b").chars().take(30).collect();
    ledger.absorb_chunk(
        format!("{first}{partial}").as_bytes(),
        "/t.jsonl",
        "dev",
        &prices,
        claude_usage::entries,
    );
    assert_eq!(
        ledger.cursors["/t.jsonl"],
        Cursor {
            offset: first.len() as u64,
            last_id: Some("a".into())
        }
    );
    assert_eq!(total_usage(&ledger.by_node["dev"]).output, 100);

    // O resto do arquivo: a mensagem "a" que continua não conta de novo.
    let rest = format!(
        "{}\n{}\n",
        simple("a"),
        line("b", "claude-opus-5-5", 10, 7, 0, 0, 0, "standard", "oi")
    );
    ledger.absorb_chunk(
        rest.as_bytes(),
        "/t.jsonl",
        "dev",
        &prices,
        claude_usage::entries,
    );
    assert_eq!(total_usage(&ledger.by_node["dev"]).output, 107);
    assert_eq!(total_usage(&ledger.total()).output, 107);
}

#[test]
fn conversas_da_trilha() {
    let trace = "# bancada\n\n## 2026-09-03 17:03 · claude\nClaude Code · claude-opus-5 · conversa fc431fec\n\npedido: x\n## 2026-09-03 18:00 · terminal\n$ ls\n## 2026-09-04 09:00 · revisor\nClaude Code · claude-opus-5-5 · conversa 1B1FCD63\n## 2026-09-04 10:00 · claude\nClaude Code · claude-opus-5 · conversa fc431fec";
    let found = trace::parse_conversations(trace);
    assert_eq!(
        found,
        [
            ("claude".to_owned(), "fc431fec".to_owned()),
            ("revisor".to_owned(), "1B1FCD63".to_owned())
        ]
    );
}

#[test]
fn texto_do_dinheiro() {
    assert_eq!(text::dollars(10.4), "US$ 10,40");
    assert_eq!(text::dollars(0.6007), "US$ 0,60");
    assert_eq!(text::dollars(0.004), "< US$ 0,01");
    assert_eq!(text::dollars(1234.5), "US$ 1.234,50");
    assert_eq!(text::dollars(0.0), "US$ 0,00");
    assert_eq!(text::dollars(1_234_567.891), "US$ 1.234.567,89");
    assert_eq!(text::tokens(17_080_000), "17,08M");
    assert_eq!(text::tokens(999), "999");
    assert_eq!(text::tokens(12_345), "12,3K");
}

#[test]
fn preco_novo_so_conta_dali_para_frente() {
    let before = table();
    let mut after = before.clone();
    after
        .models
        .get_mut("claude-opus-5-5")
        .expect("preço")
        .output = 40.0;
    let mut usage = UsageByPrice::new();
    let entry = prices::entry(
        "1",
        "claude-opus-5-5",
        TokenUsage {
            output: 1_000_000,
            ..TokenUsage::default()
        },
    );
    add_entry(&mut usage, &entry, &before);
    near(after.cost(&usage).0, 20.0);
    add_entry(&mut usage, &entry, &after);
    near(after.cost(&usage).0, 60.0);
    assert_eq!(settled(&usage, &after), usage);
}

#[test]
fn tokens_sem_preco_congelam_quando_o_preco_chega() {
    let mut usage = UsageByPrice::new();
    add_entry(
        &mut usage,
        &prices::entry(
            "1",
            "claude-futuro-9",
            TokenUsage {
                output: 1_000_000,
                ..TokenUsage::default()
            },
        ),
        &table(),
    );
    assert!(table().cost(&usage).1);

    let mut known = table();
    known.models.insert(
        "claude-futuro-9".into(),
        ModelPrice::new("Futuro", 1.0, 3.0, 0.1),
    );
    let frozen = settled(&usage, &known);
    assert_eq!(frozen["claude-futuro-9"].pending, TokenUsage::default());
    known
        .models
        .get_mut("claude-futuro-9")
        .expect("preço")
        .output = 99.0;
    near(known.cost(&frozen).0, 3.0);
}

#[test]
fn registro_antigo_le_tokens_como_pendentes() {
    let old = r#"{"byNode":{"dev":{"claude-opus-5-5":{"output":1000000}}},"cursors":{}}"#;
    let mut ledger: UsageLedger = serde_json::from_str(old).expect("lê");
    assert_eq!(
        ledger.by_node["dev"]["claude-opus-5-5"].pending.output,
        1_000_000
    );
    ledger.settle(&table());
    let spend = ledger.by_node["dev"]["claude-opus-5-5"];
    near(spend.cost.output, 20.0);
    assert!(spend.pending.is_empty());
    let again: UsageLedger =
        serde_json::from_str(&serde_json::to_string(&ledger).expect("grava")).expect("relê");
    assert_eq!(again, ledger);
}

/// O que o Swift grava abre: chaves, `pending` só quando há, cursor sem `lastId`
/// quando nulo.
#[test]
fn formato_do_usage_json() {
    let mut ledger = UsageLedger::default();
    ledger.absorb(
        &[prices::entry(
            "1",
            "claude-opus-5-5",
            TokenUsage {
                output: 5,
                ..TokenUsage::default()
            },
        )],
        "dev",
        &table(),
    );
    ledger.cursors.insert(
        "/t".into(),
        Cursor {
            offset: 7,
            last_id: None,
        },
    );
    let value = serde_json::to_value(&ledger).expect("valor");
    assert_eq!(value["cursors"]["/t"], json!({"offset": 7}));
    let spend = &value["byNode"]["dev"]["claude-opus-5-5"];
    assert!(spend.get("pending").is_none());
    assert_eq!(spend["tokens"]["output"], 5);
    assert!(spend["cost"].get("cacheWrite").is_some());
    assert!(spend["tokens"].get("cacheWrite5m").is_some());
}

#[test]
fn precos_em_camadas() {
    let catalog = BTreeMap::from([(
        "claude-sonnet-5-5".to_owned(),
        ModelPrice::new("Sonnet 5.5", 2.0, 10.0, 0.1),
    )]);
    let table = PriceTable::layered(&catalog, &BTreeMap::new());
    assert_eq!(table.models["claude-sonnet-5-5"].cache_read, 0.1);
    assert_eq!(table.origin["claude-sonnet-5-5"], Origin::ClaudeCode);
    assert_eq!(table.origin["claude-opus-4-6"], Origin::BuiltIn);

    let custom = BTreeMap::from([(
        "claude-sonnet-5-5".to_owned(),
        ModelPrice::new("Meu", 1.0, 1.0, 1.0),
    )]);
    let table = PriceTable::layered(&catalog, &custom);
    assert_eq!(table.origin["claude-sonnet-5-5"], Origin::File);
    assert_eq!(table.name("claude-sonnet-5-5"), "Meu");
}

#[test]
fn modo_rapido_dobra_o_preco_da_base() {
    let table = table();
    let price = table.price("claude-opus-5-5#fast").expect("preço");
    assert_eq!(price.name, "Opus 5.5 (rápido)");
    near(price.output, 40.0);
    assert!(table.price("claude-futuro#fast").is_none());
}

#[test]
fn copia_semeada_da_tabela_nao_vale_como_excecao() {
    let seeded = prices::built_in();
    assert!(prices::is_seed_copy(&seeded));
    assert!(prices::file_overrides(seeded.clone()).is_empty());
    let mut edited = seeded;
    edited.get_mut("claude-opus-5-5").expect("preço").output = 1.0;
    assert!(!prices::is_seed_copy(&edited));
    assert_eq!(prices::file_overrides(edited.clone()), edited);
}

#[test]
fn arquivo_de_precos_nasce_vazio_e_preserva_a_edicao() {
    let home = tempfile::tempdir().expect("pasta");
    store::seed_pricing_file_if_missing(home.path());
    assert_eq!(
        fs::read_to_string(store::pricing_file(home.path())).expect("lê"),
        "{}\n"
    );

    fs::write(
        store::pricing_file(home.path()),
        r#"{"claude-opus-5-5":{"name":"Meu Opus","input":1,"output":2,"cacheRead":0.5}}"#,
    )
    .expect("grava");
    store::seed_pricing_file_if_missing(home.path());
    let table = store::load_prices(home.path(), &BTreeMap::new());
    assert_eq!(table.name("claude-opus-5-5"), "Meu Opus");
    assert_eq!(table.origin["claude-opus-5-5"], Origin::File);

    // A cópia que a versão anterior semeou é trocada pelo vazio.
    fs::write(
        store::pricing_file(home.path()),
        serde_json::to_string(&prices::built_in()).expect("json"),
    )
    .expect("grava");
    store::seed_pricing_file_if_missing(home.path());
    assert_eq!(
        fs::read_to_string(store::pricing_file(home.path())).expect("lê"),
        "{}\n"
    );
}

#[test]
fn modelo_principal_e_o_que_mais_gastou() {
    let table = table();
    let mut usage = UsageByPrice::new();
    for (model, output) in [
        ("claude-haiku-4-5", 1_000_000),
        ("claude-opus-5-5", 1_000_000),
    ] {
        add_entry(
            &mut usage,
            &prices::entry(
                "x",
                model,
                TokenUsage {
                    output,
                    ..TokenUsage::default()
                },
            ),
            &table,
        );
    }
    assert_eq!(table.main_model(&usage).as_deref(), Some("Opus 5.5"));
    assert_eq!(table.main_model(&UsageByPrice::new()), None);
    assert_eq!(text::cost(&usage, &table), "US$ 25,00");
}

// ---- o store, com transcripts de verdade em pasta de teste ------------------

fn append(path: &Path, text: &str) {
    use std::io::Write;
    fs::create_dir_all(path.parent().expect("pai")).expect("pasta");
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .expect("abre");
    file.write_all(text.as_bytes()).expect("grava");
}

#[test]
fn store_soma_incremental_grava_e_nao_conta_de_novo() {
    let home = tempfile::tempdir().expect("pasta");
    let user = tempfile::tempdir().expect("pasta");
    let transcript = user.path().join("t.jsonl");
    append(&transcript, &format!("{}\n{}\n", simple("a"), simple("a")));
    // Subagente: também é pago.
    append(
        &user.path().join("t/subagents/s1.jsonl"),
        &format!(
            "{}\n",
            line("s", "claude-haiku-4-5", 0, 50, 0, 0, 0, "standard", "x")
        ),
    );

    let sources = BTreeMap::from([(
        "bancada".to_owned(),
        vec![Source {
            node: "dev".into(),
            transcript: transcript.clone(),
        }],
    )]);
    let prices = table();
    let mut store = UsageStore::new(home.path().to_path_buf(), user.path().to_path_buf());

    let changed = store.refresh(&sources, &prices);
    assert_eq!(changed.len(), 1);
    assert_eq!(
        total_usage(&store.ledger("bancada").by_node["dev"]).output,
        150
    );
    let saved = home.path().join("workbenches/bancada/usage.json");
    assert!(saved.exists());
    let on_disk: UsageLedger =
        serde_json::from_slice(&fs::read(&saved).expect("lê")).expect("json");
    assert_eq!(on_disk, store.ledger("bancada"));

    // Nada novo: nada muda, nada é regravado.
    assert!(store.refresh(&sources, &prices).is_empty());

    // O arquivo cresce com uma linha pela metade: só a completa entra.
    append(&transcript, &format!("{}\n", simple("b")));
    append(
        &transcript,
        &simple("c").chars().take(20).collect::<String>(),
    );
    let changed = store.refresh(&sources, &prices);
    assert_eq!(changed.len(), 1);
    assert_eq!(
        total_usage(&store.ledger("bancada").by_node["dev"]).output,
        250
    );

    // Um app novo reabre do disco e continua de onde parou.
    let mut reopened = UsageStore::new(home.path().to_path_buf(), user.path().to_path_buf());
    assert!(
        reopened.refresh(&sources, &prices).len() == 1,
        "primeira vez nesta execução publica"
    );
    assert_eq!(
        total_usage(&reopened.ledger("bancada").by_node["dev"]).output,
        250
    );
}

#[test]
fn store_arquivo_que_encolheu_nao_conta_de_novo() {
    let home = tempfile::tempdir().expect("pasta");
    let user = tempfile::tempdir().expect("pasta");
    let transcript = user.path().join("t.jsonl");
    append(&transcript, &format!("{}\n{}\n", simple("a"), simple("b")));
    let sources = BTreeMap::from([(
        "b".to_owned(),
        vec![Source {
            node: "n".into(),
            transcript: transcript.clone(),
        }],
    )]);
    let prices = table();
    let mut store = UsageStore::new(home.path().to_path_buf(), user.path().to_path_buf());
    store.refresh(&sources, &prices);
    assert_eq!(total_usage(&store.ledger("b").by_node["n"]).output, 200);

    fs::write(&transcript, format!("{}\n", simple("z"))).expect("reescreve menor");
    store.refresh(&sources, &prices);
    assert_eq!(
        total_usage(&store.ledger("b").by_node["n"]).output,
        200,
        "reescrito: não recontar"
    );
}

#[test]
fn store_na_primeira_vez_acha_o_passado_pela_trilha() {
    let home = tempfile::tempdir().expect("pasta");
    let user = tempfile::tempdir().expect("pasta");
    // O transcript de antes de um `/clear`, achado pelo prefixo de 8 da trilha.
    let past = user
        .path()
        .join(".claude/projects/-x/fc431fec-1111-2222-3333-444444444444.jsonl");
    append(&past, &format!("{}\n", simple("old")));
    let current = user
        .path()
        .join(".claude/projects/-x/aaaaaaaa-1111-2222-3333-444444444444.jsonl");
    append(&current, &format!("{}\n", simple("new")));
    append(
        &home.path().join("workbenches/b/trace.md"),
        "## 2026-09-03 17:03 · claude\nClaude Code · m · conversa fc431fec\n",
    );

    let sources = BTreeMap::from([(
        "b".to_owned(),
        vec![Source {
            node: "claude".into(),
            transcript: current,
        }],
    )]);
    let mut store = UsageStore::new(home.path().to_path_buf(), user.path().to_path_buf());
    store.refresh(&sources, &table());
    assert_eq!(
        total_usage(&store.ledger("b").by_node["claude"]).output,
        200
    );
}

#[test]
fn store_congela_o_pendente_quando_o_preco_chega() {
    let home = tempfile::tempdir().expect("pasta");
    let user = tempfile::tempdir().expect("pasta");
    let transcript = user.path().join("t.jsonl");
    append(
        &transcript,
        &format!(
            "{}\n",
            line(
                "a",
                "claude-futuro-9",
                0,
                1_000_000,
                0,
                0,
                0,
                "standard",
                "x"
            )
        ),
    );
    let sources = BTreeMap::from([(
        "b".to_owned(),
        vec![Source {
            node: "n".into(),
            transcript,
        }],
    )]);
    let mut store = UsageStore::new(home.path().to_path_buf(), user.path().to_path_buf());
    store.refresh(&sources, &table());
    assert!(
        table().cost(&store.ledger("b").by_node["n"]).1,
        "sem preço: pendente"
    );

    let mut known = table();
    known.models.insert(
        "claude-futuro-9".into(),
        ModelPrice::new("Futuro", 1.0, 3.0, 0.1),
    );
    let changed = store.refresh(&sources, &known);
    assert_eq!(changed.len(), 1, "congelar muda o registro");
    let spend = store.ledger("b").by_node["n"]["claude-futuro-9"];
    assert!(spend.pending.is_empty());
    near(spend.cost.output, 3.0);
}

/// O `Int` do Swift aceita um negativo editado à mão; o registro inteiro não pode
/// ser recusado (e recontado) por causa dele.
#[test]
fn registro_com_inteiro_negativo_abre() {
    let text = r#"{"byNode":{"dev":{"claude-opus-5-5":{"tokens":{"output":-3},"cost":{}}}},"cursors":{"/t":{"offset":4}}}"#;
    let ledger: UsageLedger = serde_json::from_str(text).expect("abre");
    assert_eq!(ledger.by_node["dev"]["claude-opus-5-5"].tokens.output, -3);
    let price: ModelPrice =
        serde_json::from_str(r#"{"name":"X","input":1,"output":2,"cacheRead":0.1,"longAbove":-1}"#)
            .expect("abre");
    assert_eq!(price.long_above, Some(-1));
}

#[test]
fn uso_com_booleano_conta_como_no_nsnumber() {
    let raw = br#"{"type":"assistant","message":{"id":"x","model":"claude-sonnet-5-5","usage":{"input_tokens":true,"output_tokens":-2,"cache_read_input_tokens":false}}}"#;
    let usage = claude_usage::entry_from_line(raw).expect("entrada").usage;
    assert_eq!((usage.input, usage.output, usage.cache_read), (1, -2, 0));
}

/// A divisão 5m+1h que passa do total de `cache_creation_input_tokens` não pode
/// encolher o 5m (o Swift faz `max(0, written - cacheWrite)`).
#[test]
fn divisao_de_cache_maior_que_o_total_nao_fica_negativa() {
    let raw = br#"{"type":"assistant","message":{"id":"x","model":"claude-sonnet-5-5","usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":10,"cache_creation":{"ephemeral_5m_input_tokens":8,"ephemeral_1h_input_tokens":9}}}}"#;
    let usage = claude_usage::entry_from_line(raw).expect("entrada").usage;
    assert_eq!((usage.cache_write5m, usage.cache_write1h), (8, 9));
    // E quando sobra: o resto vai para o 5m.
    let raw = br#"{"type":"assistant","message":{"id":"y","model":"claude-sonnet-5-5","usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":30,"cache_creation":{"ephemeral_5m_input_tokens":8,"ephemeral_1h_input_tokens":9}}}}"#;
    let usage = claude_usage::entry_from_line(raw).expect("entrada").usage;
    assert_eq!((usage.cache_write5m, usage.cache_write1h), (21, 9));
}

#[test]
fn arquivos_com_bom_e_chave_repetida_abrem_pelo_json_file() {
    let home = tempfile::tempdir().expect("pasta");
    fs::write(
        store::pricing_file(home.path()),
        b"\xef\xbb\xbf{\"claude-opus-5-5\":{\"name\":\"Meu\",\"input\":1.0,\"output\":2,\"cacheRead\":0.5,\"name\":\"outro\"}}",
    )
    .expect("grava");
    let table = store::load_prices(home.path(), &BTreeMap::new());
    assert_eq!(
        table.name("claude-opus-5-5"),
        "Meu",
        "a primeira chave vence"
    );
}

#[test]
fn modelo_que_so_o_catalogo_conhece_tem_preco_e_a_tabela_acompanha_as_mudancas() {
    let home = tempfile::tempdir().expect("pasta");
    let mut memo = store::PriceMemo::default();
    let fable = "claude-fable-5-2";
    assert!(PriceTable::from_built_in().price(fable).is_none());

    let catalog = BTreeMap::from([(
        fable.to_owned(),
        ModelPrice::new("Fable 5.2", 8.0, 40.0, 0.2),
    )]);
    let table = memo.table(home.path(), &catalog);
    assert_eq!(table.name(fable), "Fable 5.2");
    assert_eq!(table.origin[fable], Origin::ClaudeCode);

    fs::write(
        store::pricing_file(home.path()),
        r#"{"claude-fable-5-2":{"name":"Meu Fable","input":1,"output":2,"cacheRead":0.5}}"#,
    )
    .expect("grava");
    assert_eq!(memo.table(home.path(), &catalog).name(fable), "Meu Fable");

    fs::remove_file(store::pricing_file(home.path())).expect("apaga");
    assert!(
        memo.table(home.path(), &BTreeMap::new())
            .price(fable)
            .is_none()
    );
}
