//! Porte de `TraceTests.swift`, mais o formato conferido contra um `trace.md`
//! que o Swift gravou.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use super::model::{TEXT_LIMIT, cap, header};
use super::store::OffsetAt;
use super::*;

/// 2026-08-25 ~17:19 UTC, o mesmo instante do Swift.
fn at() -> SystemTime {
    UNIX_EPOCH + Duration::from_secs(1_787_678_363)
}

fn entry(address: &str, text: &str) -> TraceEntry {
    TraceEntry::new(address, "3f9a2c1d", at(), text)
}

// ---- TraceEntryTests

#[test]
fn markdown_carimba_quem_e_com_que() {
    let md = entry(
        "deck/revisor",
        "pedido: revisar o PR — entrega: 3 apontamentos",
    )
    .stamped(
        Some("Claude Code".into()),
        Some("claude-haiku-4-5".into()),
        Some("3C0C394C-E0A8-46FD".into()),
    )
    .markdown(0);
    assert!(md.starts_with("## "));
    // Só o id do nó: a bancada já é o arquivo.
    assert!(md.contains(" · revisor\n"));
    assert!(!md.contains("deck/"));
    assert!(md.contains("Claude Code · claude-haiku-4-5 · conversa 3C0C394C\n"));
    assert!(md.ends_with("\n\npedido: revisar o PR — entrega: 3 apontamentos\n\n"));
}

// Nó sem perfil ou antes do primeiro turno: sem carimbo, sem linha vazia sobrando.
#[test]
fn sem_identidade_nao_deixa_linha_de_carimbo() {
    let md = entry("deck/x", "fiz").markdown(0);
    assert_eq!(md.split('\n').count(), 5);
    assert!(!md.contains("conversa"));
    assert!(entry("deck/x", "  ").markdown(0).contains("\n—\n"));
}

#[test]
fn texto_e_aparado_e_cortado() {
    assert_eq!(cap("  a\nb \n", 10), "a\nb");
    let long = "x".repeat(TEXT_LIMIT + 50);
    let capped = entry("deck/x", &long);
    assert_eq!(capped.text.chars().count(), TEXT_LIMIT + 1);
    assert!(capped.text.ends_with('…'));
}

#[test]
fn separa_o_endereco() {
    let e = entry("deck/revisor", "x");
    assert_eq!(e.workbench(), "deck");
    assert_eq!(e.node(), "revisor");
    // Sem barra, os dois são o endereço; com mais de uma, o nó leva o resto.
    assert_eq!(entry("solto", "x").workbench(), "solto");
    assert_eq!(entry("solto", "x").node(), "solto");
    assert_eq!(entry("a/b/c", "x").node(), "b/c");
}

#[test]
fn carimbo_usa_o_fuso_dado() {
    assert!(
        entry("deck/x", "x")
            .markdown(0)
            .starts_with("## 2026-08-25 17:19 · x\n")
    );
    assert!(
        entry("deck/x", "x")
            .markdown(-3 * 3600)
            .starts_with("## 2026-08-25 14:19 · x\n")
    );
}

// ---- TraceLogTests

fn log() -> (tempfile::TempDir, TraceLog) {
    let dir = tempfile::tempdir().unwrap();
    let log = TraceLog::fixed(dir.path().to_owned(), 0);
    (dir, log)
}

fn entry_in(address: &str, id: &str, text: &str) -> TraceEntry {
    TraceEntry::new(address, id, at(), text)
}

// A pasta é o id, não o nome: "deck" apagada e recriada é outra trilha.
#[test]
fn a_pasta_e_o_id_da_bancada() {
    let (dir, log) = log();
    assert_eq!(
        log.file(&entry_in("deck/revisor", "aaaa1111", "x")),
        dir.path().join("aaaa1111/trace.md")
    );
    assert_eq!(
        log.file(&entry_in("deck/dev", "aaaa1111", "x")),
        log.file(&entry_in("deck/revisor", "aaaa1111", "x"))
    );
    assert_ne!(
        log.file(&entry_in("deck/dev", "bbbb2222", "x")),
        log.file(&entry_in("deck/dev", "aaaa1111", "x"))
    );
}

fn archive_name_is_valid(name: &str) -> bool {
    // trace-\d{8}-\d{6}_\d{8}-\d{6}.md
    let Some(body) = name
        .strip_prefix("trace-")
        .and_then(|n| n.strip_suffix(".md"))
    else {
        return false;
    };
    let digits = |s: &str, n: usize| s.len() == n && s.bytes().all(|b| b.is_ascii_digit());
    let Some((start, end)) = body.split_once('_') else {
        return false;
    };
    let clock = |s: &str| {
        s.split_once('-')
            .is_some_and(|(d, t)| digits(d, 8) && digits(t, 6))
    };
    clock(start) && clock(end)
}

// Limpar a bancada leva a trilha junto: vai para `trace-archive/` nomeada pelo
// período, e a próxima entrada abre um arquivo novo com cabeçalho.
#[test]
fn arquivar_move_a_trilha_e_a_proxima_entrada_abre_outra() {
    let (_dir, log) = log();
    let now = SystemTime::now();
    assert!(
        log.archive("aaaa1111", now).is_none(),
        "sem trilha não nasce arquivo"
    );
    log.record(&entry_in("deck/a", "aaaa1111", "primeiro"));
    let current = log.current("aaaa1111");
    let archived = log.archive("aaaa1111", now).unwrap();
    assert!(!current.exists());
    assert_eq!(
        archived.parent().unwrap().file_name().unwrap(),
        "trace-archive"
    );
    let name = archived.file_name().unwrap().to_string_lossy().into_owned();
    assert!(archive_name_is_valid(&name), "{name}");
    assert!(
        std::fs::read_to_string(&archived)
            .unwrap()
            .contains("primeiro")
    );
    assert_eq!(log.archived("aaaa1111"), std::slice::from_ref(&archived));

    log.record(&entry_in("deck/a", "aaaa1111", "segundo"));
    let fresh = std::fs::read_to_string(&current).unwrap();
    assert!(fresh.starts_with("# deck\n"), "cabeçalho de novo");
    assert!(!fresh.contains("primeiro"));
    assert!(fresh.contains("segundo"));

    // Mesmo período de novo (tudo no mesmo segundo): sufixo, não sobrescrita.
    let second = log.archive("aaaa1111", now).unwrap();
    assert_ne!(second, archived);
    assert_eq!(log.archived("aaaa1111").len(), 2);
}

#[test]
fn cabecalho_uma_vez_e_os_agentes_em_ordem() {
    let (_dir, log) = log();
    log.record(&entry_in("deck/a", "aaaa1111", "um"));
    log.record(&entry_in("deck/b", "aaaa1111", "dois"));
    log.record(&entry_in("deck/a", "aaaa1111", "três"));
    let text = std::fs::read_to_string(log.current("aaaa1111")).unwrap();
    assert!(text.starts_with("# deck\nbancada `aaaa1111`\n"));
    assert_eq!(text.split("# deck\n").count(), 2);
    assert_eq!(text.split("\n## ").count(), 4);
    let um = text.find("\num\n").unwrap();
    let dois = text.find("\ndois\n").unwrap();
    let tres = text.find("\ntrês\n").unwrap();
    assert!(um < dois && dois < tres);
}

// O formato é o do `trace.md` que o Swift gravou nesta bancada.
#[test]
fn cabecalho_igual_ao_gravado_pelo_swift() {
    let real = include_str!("../../../fixtures/trace/header.md");
    assert_eq!(header("migracao-flutter", "90c24837"), real);
}

#[test]
fn arquivo_completo_igual_ao_do_swift() {
    let (_dir, log) = log();
    let e = TraceEntry::new(
        "migracao-flutter/claude",
        "90c24837",
        at(),
        "pedido: x — entrega: y\n",
    )
    .stamped(
        Some("Claude Code".into()),
        Some("claude-fable-5-2".into()),
        Some("56D77AD6-1111-2222-3333-444455556666".into()),
    );
    log.record(&e);
    let expected = format!(
        "{}## 2026-08-25 17:19 · claude\nClaude Code · claude-fable-5-2 · conversa 56D77AD6\n\npedido: x — entrega: y\n\n",
        include_str!("../../../fixtures/trace/header.md")
    );
    assert_eq!(std::fs::read_to_string(log.file(&e)).unwrap(), expected);
}

// O fuso vale para CADA data, como no `DateFormatter` do Swift: o carimbo de
// agora e a data de criação do arquivo morto, meses atrás, podem ter
// deslocamentos diferentes (horário de verão).
#[test]
fn o_deslocamento_e_pedido_por_instante() {
    let dir = tempfile::tempdir().unwrap();
    let cutoff = at() - Duration::from_secs(3600);
    // Antes do corte, -3 h; do corte em diante, -2 h.
    let offset: OffsetAt =
        std::sync::Arc::new(move |t| if t < cutoff { -3 * 3600 } else { -2 * 3600 });
    let log = TraceLog::new(dir.path().to_owned(), offset);
    let e = entry_in("deck/x", "aaaa1111", "x");
    log.record(&e);
    let text = std::fs::read_to_string(log.file(&e)).unwrap();
    assert!(text.contains("## 2026-08-25 15:19 · x\n"), "{text}");
}

#[test]
fn o_corte_do_texto_e_por_grafema() {
    // Bandeira (2 escalares) e acento decomposto contam como um grafema cada.
    let flag = "\u{1F1E7}\u{1F1F7}";
    assert_eq!(cap(&flag.repeat(3), 3), flag.repeat(3));
    let cut = cap(&flag.repeat(4), 3);
    assert_eq!(cut, format!("{}…", flag.repeat(3)));
    let accents = "e\u{301}".repeat(5);
    assert_eq!(cap(&accents, 2), format!("{}…", "e\u{301}".repeat(2)));
}
