//! Histórico, ponteiro, seleção e efeitos, com o libghostty-vt de verdade.

use egeon_core::ports::screen::{LinkHit, Screen, ScreenError, ScreenFactory};
use egeon_core::protocol::screen::{
    Effect, Frame, FrameKind, Mods, MouseButton, Pointer, PointerKind, Scroll, Size,
};
use egeon_terminal::GhosttyScreens;

type Res = Result<(), Box<dyn std::error::Error>>;

fn open(cols: u16, rows: u16) -> Result<Box<dyn Screen>, ScreenError> {
    GhosttyScreens.create(Size { cols, rows })
}

/// `n` linhas numeradas, a última sem quebra no fim.
fn numbered(s: &mut dyn Screen, n: usize) {
    let text: Vec<String> = (0..n).map(|i| format!("linha {i}")).collect();
    s.feed(text.join("\r\n").as_bytes());
}

fn trimmed(s: &mut dyn Screen) -> Vec<String> {
    s.rows_text()
        .into_iter()
        .map(|l| l.trim_end().to_owned())
        .collect()
}

fn pointer(kind: PointerKind, x: f32, y: f32, time_ms: u64) -> Pointer {
    Pointer {
        kind,
        button: Some(MouseButton::Left),
        x,
        y,
        mods: Mods::default(),
        time_ms,
        lines: 0,
    }
}

fn wheel(lines: i32) -> Pointer {
    Pointer {
        kind: PointerKind::Wheel,
        button: None,
        x: 2.5,
        y: 1.5,
        mods: Mods::default(),
        time_ms: 0,
        lines,
    }
}

fn link(text: &str) -> Option<LinkHit> {
    Some(LinkHit::Link(text.into()))
}

fn shift() -> Mods {
    Mods {
        shift: true,
        ..Mods::default()
    }
}

fn click(s: &mut dyn Screen, x: f32, y: f32, time_ms: u64) {
    s.pointer(&pointer(PointerKind::Press, x, y, time_ms));
    s.pointer(&pointer(PointerKind::Release, x, y, time_ms + 10));
}

fn selected_cols(frame: &Frame, row: u16) -> Option<[u16; 2]> {
    frame
        .lines
        .iter()
        .find(|l| l.row == row)
        .and_then(|l| l.selection)
}

#[test]
fn rolar_mostra_o_historico_e_volta_ao_fim() -> Res {
    let mut s = open(20, 5)?;
    numbered(s.as_mut(), 30);
    assert_eq!(trimmed(s.as_mut())[4], "linha 29");
    let bottom = s.full_frame().scrollbar.ok_or("full sem barra")?;
    assert_eq!(bottom.len, 5);
    assert_eq!(bottom.total, 30);
    assert_eq!(bottom.offset, 25);
    let _ = s.take_delta();

    s.scroll(Scroll::Rows(-10));
    assert_eq!(trimmed(s.as_mut())[0], "linha 15");
    let delta = s.take_delta().ok_or("rolar não gerou quadro")?;
    assert_eq!(delta.scrollbar.map(|b| b.offset), Some(15));
    assert_eq!(delta.lines.len(), 5);

    s.scroll(Scroll::Top);
    assert_eq!(trimmed(s.as_mut())[0], "linha 0");
    s.scroll(Scroll::Bottom);
    assert_eq!(trimmed(s.as_mut())[4], "linha 29");
    Ok(())
}

#[test]
fn saida_nova_nao_puxa_a_vista_rolada() -> Res {
    let mut s = open(20, 5)?;
    numbered(s.as_mut(), 30);
    s.scroll(Scroll::Rows(-10));
    let before = trimmed(s.as_mut());
    s.feed(b"\r\nmais uma");
    assert_eq!(trimmed(s.as_mut()), before);
    s.scroll(Scroll::Bottom);
    assert_eq!(trimmed(s.as_mut())[4], "mais uma");
    Ok(())
}

#[test]
fn historico_nunca_fica_abaixo_das_500_linhas_do_swiftterm() -> Res {
    // O Ghostty poda o histórico uma página inteira por vez, e a página tem
    // mais linhas quanto mais estreito o terminal.
    for cols in [20, 80, 200] {
        let mut s = open(cols, 5)?;
        let mut highest = 0;
        for chunk in 0..120 {
            let text: String = (0..50)
                .map(|i| format!("linha {}\r\n", chunk * 50 + i))
                .collect();
            s.feed(text.as_bytes());
            let bar = s.full_frame().scrollbar.ok_or("full sem barra")?;
            let history = bar.total - bar.len;
            highest = highest.max(history);
            if chunk >= 12 {
                assert!(history >= 500, "{cols} colunas: {history} linhas");
            }
        }
        // E poda: 6 mil linhas não ficam todas.
        assert!(highest < 6000, "{cols} colunas: {highest} linhas");
    }
    Ok(())
}

#[test]
fn delta_so_traz_a_barra_quando_ela_muda() -> Res {
    let mut s = open(20, 5)?;
    s.feed(b"oi");
    let first = s.take_delta().ok_or("sem quadro")?;
    assert!(first.scrollbar.is_some());
    s.feed(b"!");
    let second = s.take_delta().ok_or("sem quadro")?;
    assert_eq!(second.scrollbar, None);
    Ok(())
}

#[test]
fn roda_sem_mouse_rola_a_vista() -> Res {
    let mut s = open(20, 5)?;
    numbered(s.as_mut(), 30);
    assert!(s.pointer(&wheel(3)).is_empty());
    assert_eq!(trimmed(s.as_mut())[4], "linha 26");
    assert!(s.pointer(&wheel(-3)).is_empty());
    assert_eq!(trimmed(s.as_mut())[4], "linha 29");
    Ok(())
}

#[test]
fn roda_na_tela_alternativa_vira_setas() -> Res {
    let mut s = open(20, 5)?;
    s.feed(b"\x1b[?1049h");
    assert_eq!(s.pointer(&wheel(2)), b"\x1b[A\x1b[A");
    assert_eq!(s.pointer(&wheel(-1)), b"\x1b[B");
    // Cursor de aplicação (DECCKM), como o `sendKeyUp` do SwiftTerm.
    s.feed(b"\x1b[?1h");
    assert_eq!(s.pointer(&wheel(1)), b"\x1bOA");
    Ok(())
}

#[test]
fn com_mouse_ligado_a_roda_e_o_clique_vao_ao_programa() -> Res {
    let mut s = open(20, 5)?;
    s.feed(b"\x1b[?1000h\x1b[?1006h");
    // SGR: botão;coluna;linha a partir de 1.
    assert_eq!(s.pointer(&wheel(1)), b"\x1b[<64;3;2M");
    assert_eq!(s.pointer(&wheel(-2)), b"\x1b[<65;3;2M\x1b[<65;3;2M");
    assert_eq!(
        s.pointer(&pointer(PointerKind::Press, 4.2, 0.7, 0)),
        b"\x1b[<0;5;1M"
    );
    assert_eq!(
        s.pointer(&pointer(PointerKind::Release, 4.2, 0.7, 5)),
        b"\x1b[<0;5;1m"
    );
    // Modo 1000 não relata arrasto nem movimento.
    assert!(
        s.pointer(&pointer(PointerKind::Drag, 6.0, 0.5, 9))
            .is_empty()
    );
    s.feed(b"\x1b[?1000l\x1b[?1002h");
    assert_eq!(
        s.pointer(&pointer(PointerKind::Drag, 6.0, 0.5, 9)),
        b"\x1b[<32;7;1M"
    );
    Ok(())
}

#[test]
fn shift_seleciona_mesmo_com_mouse_ligado() -> Res {
    let mut s = open(20, 5)?;
    s.feed(b"hello world\x1b[?1000h\x1b[?1006h");
    let mut press = pointer(PointerKind::Press, 0.2, 0.5, 0);
    press.mods = shift();
    assert!(s.pointer(&press).is_empty());
    let mut drag = pointer(PointerKind::Drag, 4.8, 0.5, 20);
    drag.mods = shift();
    assert!(s.pointer(&drag).is_empty());
    assert_eq!(s.selection_text().as_deref(), Some("hello"));
    Ok(())
}

#[test]
fn arrasto_seleciona_e_o_quadro_marca_as_colunas() -> Res {
    let mut s = open(20, 5)?;
    s.feed(b"hello world");
    let _ = s.take_delta();
    s.pointer(&pointer(PointerKind::Press, 0.2, 0.5, 0));
    s.pointer(&pointer(PointerKind::Drag, 4.8, 0.5, 20));
    s.pointer(&pointer(PointerKind::Release, 4.8, 0.5, 30));
    assert_eq!(s.selection_text().as_deref(), Some("hello"));
    let delta = s.take_delta().ok_or("seleção não gerou quadro")?;
    assert_eq!(selected_cols(&delta, 0), Some([0, 4]));
    Ok(())
}

#[test]
fn clique_duplo_pega_a_palavra_e_triplo_a_linha() -> Res {
    let mut s = open(20, 5)?;
    s.feed(b"hello world");
    click(s.as_mut(), 7.5, 0.5, 1_000);
    click(s.as_mut(), 7.5, 0.5, 1_100);
    assert_eq!(s.selection_text().as_deref(), Some("world"));
    click(s.as_mut(), 7.5, 0.5, 1_200);
    assert_eq!(s.selection_text().as_deref(), Some("hello world"));
    Ok(())
}

#[test]
fn clique_simples_desfaz_a_selecao() -> Res {
    let mut s = open(20, 5)?;
    s.feed(b"hello world");
    s.select_all();
    assert!(s.selection_text().is_some());
    click(s.as_mut(), 2.5, 0.5, 5_000);
    assert_eq!(s.selection_text(), None);
    Ok(())
}

#[test]
fn shift_clique_estende_a_selecao() -> Res {
    let mut s = open(20, 5)?;
    s.feed(b"hello world");
    s.pointer(&pointer(PointerKind::Press, 0.2, 0.5, 0));
    s.pointer(&pointer(PointerKind::Drag, 1.8, 0.5, 10));
    s.pointer(&pointer(PointerKind::Release, 1.8, 0.5, 20));
    assert_eq!(s.selection_text().as_deref(), Some("he"));
    let mut press = pointer(PointerKind::Press, 7.5, 0.5, 3_000);
    press.mods = shift();
    s.pointer(&press);
    assert_eq!(s.selection_text().as_deref(), Some("hello wo"));
    Ok(())
}

#[test]
fn selecionar_tudo_junta_a_linha_que_o_terminal_quebrou() -> Res {
    let mut s = open(5, 4)?;
    s.feed(b"abcdefghij\r\nfim");
    s.select_all();
    assert_eq!(s.selection_text().as_deref(), Some("abcdefghij\nfim"));
    Ok(())
}

#[test]
fn arrastar_para_fora_rola_a_selecao_pelo_historico() -> Res {
    let mut s = open(20, 5)?;
    numbered(s.as_mut(), 30);
    let before = s.full_frame().scrollbar.ok_or("full sem barra")?;
    s.pointer(&pointer(PointerKind::Press, 3.5, 2.5, 0));
    // Três linhas acima da vista: velocidade 3 por repetição.
    s.pointer(&pointer(PointerKind::Drag, 3.5, -3.0, 50));
    s.pointer(&pointer(PointerKind::Drag, 3.5, -3.0, 100));
    let after = s.full_frame().scrollbar.ok_or("full sem barra")?;
    assert_eq!(after.offset, before.offset - 6);
    // Da linha 27 (onde o arrasto começou) até a 19, que subiu para a vista;
    // as pontas seguem a regra da metade da célula.
    let text = s.selection_text().ok_or("sem seleção")?;
    assert!(text.starts_with("ha 19\nlinha 20"), "{text:?}");
    assert!(text.ends_with("linha 26\nlin"), "{text:?}");
    Ok(())
}

#[test]
fn sino_vira_efeito() -> Res {
    let mut s = open(20, 5)?;
    s.feed(b"a\x07b\x07");
    assert_eq!(s.take_effects(), vec![Effect::Bell, Effect::Bell]);
    assert!(s.take_effects().is_empty());
    Ok(())
}

#[test]
fn osc_52_grava_na_area_de_transferencia() -> Res {
    let mut s = open(20, 5)?;
    s.feed(b"\x1b]52;c;aGVsbG8=\x07");
    assert_eq!(
        s.take_effects(),
        vec![Effect::Clipboard {
            text: "hello".into()
        }]
    );
    Ok(())
}

#[test]
fn osc_52_consulta_pede_a_area_e_responde_quando_ela_chega() -> Res {
    let mut s = open(20, 5)?;
    s.feed(b"\x1b]52;c;?\x07");
    // Nada vai ao programa antes do conteúdo: nem o envelope vazio.
    assert!(s.take_responses().is_empty());
    assert_eq!(s.take_effects(), vec![Effect::ClipboardRequest]);
    assert_eq!(s.clipboard_answer("xyz"), b"\x1b]52;c;eHl6\x07");
    // Uma resposta por consulta.
    assert!(s.clipboard_answer("xyz").is_empty());

    // O terminador e a seleção do pedido voltam na resposta.
    s.feed(b"\x1b]52;p;?\x1b\\\x1b[6n");
    assert_eq!(s.take_responses(), b"\x1b[1;1R");
    assert_eq!(s.clipboard_answer(""), b"\x1b]52;p;\x1b\\");
    Ok(())
}

#[test]
fn quadro_full_traz_a_barra() -> Res {
    let mut s = open(20, 5)?;
    let frame = s.full_frame();
    assert_eq!(frame.kind, FrameKind::Full);
    assert_eq!(frame.scrollbar.map(|b| b.len), Some(5));
    Ok(())
}

#[test]
fn link_explicito_osc_8_vence() -> Res {
    let mut s = open(40, 5)?;
    s.feed(b"veja \x1b]8;;https://egeon.dev/doc\x1b\\o manual\x1b]8;;\x1b\\ aqui");
    assert_eq!(s.link_at(7, 0), link("https://egeon.dev/doc"));
    assert_eq!(s.link_at(1, 0), None);
    Ok(())
}

#[test]
fn link_implicito_e_nome_solto() -> Res {
    let mut s = open(60, 5)?;
    s.feed(b"abra https://example.com/a e src/main.rs:42\r\nleia README.md.");
    assert_eq!(s.link_at(8, 0), link("https://example.com/a"));
    assert_eq!(s.link_at(33, 0), link("src/main.rs:42"));
    // Sem barra a regex não pega; o nome solto pega, sem o ponto da frase.
    assert_eq!(s.link_at(7, 1), Some(LinkHit::Word("README.md".into())));
    assert_eq!(s.link_at(1, 1), None);
    assert_eq!(s.link_at(59, 4), None);
    Ok(())
}

#[test]
fn link_na_linha_que_o_terminal_quebrou() -> Res {
    let mut s = open(20, 5)?;
    s.feed(b"ver /Users/eu/projeto/longo/arquivo.md fim");
    let want = link("/Users/eu/projeto/longo/arquivo.md");
    assert_eq!(s.link_at(6, 0), want);
    assert_eq!(s.link_at(3, 1), want);
    Ok(())
}
