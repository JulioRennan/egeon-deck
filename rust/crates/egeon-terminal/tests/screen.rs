//! A tela de verdade, com o libghostty-vt ligado: o que o core recebe pela
//! interface `Screen`.

use egeon_core::ports::screen::{Screen, ScreenError, ScreenFactory};
use egeon_core::protocol::screen::{
    Color, CursorShape, Frame, FrameKind, Key, KeyPress, Mods, MouseButton, NamedKey, Pointer,
    PointerKind, RgbHex, Size,
};
use egeon_terminal::GhosttyScreens;

type Res = Result<(), Box<dyn std::error::Error>>;

fn open(cols: u16, rows: u16) -> Result<Box<dyn Screen>, ScreenError> {
    GhosttyScreens.create(Size { cols, rows })
}

fn row_text(frame: &Frame, row: u16) -> String {
    frame
        .lines
        .iter()
        .find(|l| l.row == row)
        .map(|l| l.spans.iter().map(|s| s.text.as_str()).collect())
        .unwrap_or_default()
}

fn named(key: NamedKey) -> KeyPress {
    KeyPress {
        key: Key::Named(key),
        mods: Mods::default(),
        text: None,
    }
}

#[test]
fn hello_aparece_na_linha_0() -> Res {
    let mut s = open(80, 24)?;
    s.feed(b"hello\r\n");
    let frame = s.full_frame();
    assert_eq!(frame.kind, FrameKind::Full);
    assert_eq!((frame.cols, frame.rows), (80, 24));
    assert_eq!(frame.lines.len(), 24);
    assert_eq!(row_text(&frame, 0), "hello");
    assert_eq!(row_text(&frame, 1), "");
    assert_eq!((frame.cursor.row, frame.cursor.col), (1, 0));

    let text = s.rows_text();
    assert_eq!(text.len(), 24);
    assert_eq!(text[0], format!("hello{}", " ".repeat(75)));
    assert!(
        text[1..]
            .iter()
            .all(|l| l.len() == 80 && l.trim().is_empty())
    );
    Ok(())
}

#[test]
fn cor_sgr_muda_o_estilo_das_celulas() -> Res {
    let mut s = open(40, 5)?;
    s.feed(b"a\x1b[1;31mbc\x1b[0m\x1b[38;2;255;128;0md\x1b[44m e\x1b[0m");
    let frame = s.full_frame();
    let spans = &frame.lines[0].spans;
    assert_eq!(spans.len(), 4, "{spans:?}");

    assert_eq!((spans[0].col, spans[0].text.as_str()), (0, "a"));
    assert_eq!(spans[0].style, Default::default());

    assert_eq!((spans[1].col, spans[1].text.as_str()), (1, "bc"));
    assert_eq!(spans[1].style.fg, Some(Color::Palette(1)));
    assert!(spans[1].style.bold);

    assert_eq!((spans[2].col, spans[2].text.as_str()), (3, "d"));
    assert_eq!(spans[2].style.fg, Some(Color::Rgb(RgbHex([255, 128, 0]))));

    assert_eq!((spans[3].col, spans[3].text.as_str()), (4, " e"));
    assert_eq!(spans[3].style.bg, Some(Color::Palette(4)));
    Ok(())
}

#[test]
fn csi_de_cursor_posiciona_o_texto() -> Res {
    let mut s = open(20, 5)?;
    // CUP para linha 3, coluna 5 (base 1).
    s.feed(b"\x1b[3;5HX");
    let frame = s.full_frame();
    let line = frame.lines.iter().find(|l| l.row == 2).ok_or("linha 2")?;
    assert_eq!(line.spans.len(), 1);
    assert_eq!(
        (line.spans[0].col, line.spans[0].text.as_str()),
        (0, "    X")
    );
    assert_eq!((frame.cursor.row, frame.cursor.col), (2, 5));
    assert!(frame.cursor.visible);
    assert_eq!(frame.cursor.shape, CursorShape::Block);

    // Esconder o cursor (DECTCEM) chega ao quadro.
    s.feed(b"\x1b[?25l");
    assert!(!s.full_frame().cursor.visible);
    Ok(())
}

#[test]
fn delta_traz_so_as_linhas_alteradas() -> Res {
    let mut s = open(20, 5)?;
    s.feed(b"um\r\ndois");
    // O primeiro quadro depois de abrir é inteiro.
    let first = s.take_delta().ok_or("primeiro delta")?;
    assert_eq!(first.kind, FrameKind::Full);
    assert!(s.take_delta().is_none(), "nada mudou");

    s.feed(b"\x1b[4;1Hquatro");
    let delta = s.take_delta().ok_or("delta")?;
    assert_eq!(delta.kind, FrameKind::Delta);
    let rows: Vec<u16> = delta.lines.iter().map(|l| l.row).collect();
    assert!(rows.contains(&3), "{rows:?}");
    assert!(!rows.contains(&0), "{rows:?}");
    assert_eq!(row_text(&delta, 3), "quatro");
    Ok(())
}

#[test]
fn cursor_que_so_andou_gera_delta() -> Res {
    let mut s = open(20, 5)?;
    s.feed(b"abc");
    s.take_delta();
    assert!(s.take_delta().is_none());
    s.feed(b"\x1b[3;7H");
    let delta = s.take_delta().ok_or("cursor andou")?;
    assert_eq!((delta.cursor.row, delta.cursor.col), (2, 6));
    // O Ghostty marca a linha de onde o cursor saiu e a para onde foi; nenhuma
    // outra vem.
    let rows: Vec<u16> = delta.lines.iter().map(|l| l.row).collect();
    assert!(rows.iter().all(|r| [0, 2].contains(r)), "{rows:?}");
    assert!(s.take_delta().is_none());
    Ok(())
}

#[test]
fn full_nao_rouba_o_delta_pendente() -> Res {
    let mut s = open(20, 5)?;
    s.feed(b"x");
    s.take_delta();
    s.feed(b"\x1b[3;1Htres");
    // Um assinante novo pede o quadro inteiro no meio.
    assert_eq!(row_text(&s.full_frame(), 2), "tres");
    let delta = s.take_delta().ok_or("delta pendente")?;
    assert_eq!(row_text(&delta, 2), "tres");
    Ok(())
}

#[test]
fn resize_muda_colunas_e_linhas() -> Res {
    let mut s = open(80, 24)?;
    s.feed(b"abc");
    s.resize(Size {
        cols: 100,
        rows: 30,
    })?;
    assert_eq!(
        s.size(),
        Size {
            cols: 100,
            rows: 30
        }
    );
    let frame = s.take_delta().ok_or("resize redesenha")?;
    assert_eq!(frame.kind, FrameKind::Full);
    assert_eq!((frame.cols, frame.rows), (100, 30));
    assert_eq!(frame.lines.len(), 30);
    assert_eq!(s.rows_text().len(), 30);
    assert_eq!(row_text(&frame, 0), "abc");

    assert_eq!(
        s.resize(Size { cols: 0, rows: 10 }),
        Err(ScreenError::InvalidSize { cols: 0, rows: 10 })
    );
    assert!(open(0, 0).is_err());
    Ok(())
}

#[test]
fn enter_e_setas_codificam_os_bytes_esperados() -> Res {
    let mut s = open(80, 24)?;
    assert_eq!(s.encode_key(&named(NamedKey::Enter)), b"\r");
    assert_eq!(s.encode_key(&named(NamedKey::Up)), b"\x1b[A");
    assert_eq!(s.encode_key(&named(NamedKey::Down)), b"\x1b[B");
    assert_eq!(s.encode_key(&named(NamedKey::Right)), b"\x1b[C");
    assert_eq!(s.encode_key(&named(NamedKey::Left)), b"\x1b[D");
    assert_eq!(s.encode_key(&named(NamedKey::Backspace)), b"\x7f");
    assert_eq!(s.encode_key(&named(NamedKey::Tab)), b"\t");
    assert_eq!(s.encode_key(&named(NamedKey::Space)), b" ");

    // Com o cursor em modo de aplicação (DECCKM, o que vim e less ligam), as
    // setas mudam: a codificação segue o modo da tela.
    s.feed(b"\x1b[?1h");
    assert_eq!(s.encode_key(&named(NamedKey::Up)), b"\x1bOA");
    assert_eq!(s.encode_key(&named(NamedKey::Left)), b"\x1bOD");
    Ok(())
}

#[test]
fn caracteres_e_modificadores() -> Res {
    let mut s = open(80, 24)?;
    let ch = |c: &str, mods: Mods, text: Option<&str>| KeyPress {
        key: Key::Char(c.into()),
        mods,
        text: text.map(str::to_owned),
    };
    assert_eq!(s.encode_key(&ch("a", Mods::default(), None)), b"a");
    let shift = Mods {
        shift: true,
        ..Mods::default()
    };
    assert_eq!(s.encode_key(&ch("a", shift, Some("A"))), b"A");
    let ctrl = Mods {
        ctrl: true,
        ..Mods::default()
    };
    assert_eq!(s.encode_key(&ch("c", ctrl, None)), b"\x03");
    let alt = Mods {
        alt: true,
        ..Mods::default()
    };
    assert_eq!(s.encode_key(&ch("b", alt, Some("∫"))), b"\x1bb");
    assert_eq!(
        s.encode_key(&ch("ç", Mods::default(), None)),
        "ç".as_bytes()
    );
    Ok(())
}

#[test]
fn feed_devolve_a_resposta_ao_programa() -> Res {
    let mut s = open(80, 24)?;
    // DSR 6: o programa pergunta onde está o cursor.
    s.feed(b"\x1b[2;3H\x1b[6n");
    assert_eq!(s.take_responses(), b"\x1b[2;3R");
    assert!(s.take_responses().is_empty(), "já entregue");
    s.feed(b"sem pergunta");
    assert!(s.take_responses().is_empty());
    Ok(())
}

#[test]
fn caractere_largo_conta_duas_celulas() -> Res {
    let mut s = open(20, 3)?;
    s.feed("日本x".as_bytes());
    let frame = s.full_frame();
    let span = &frame.lines[0].spans[0];
    assert_eq!(span.text, "日本x");
    assert_eq!(span.cells, 5);
    assert_eq!((frame.cursor.row, frame.cursor.col), (0, 5));
    assert_eq!(s.rows_text()[0].trim_end(), "日本x");
    Ok(())
}

#[test]
fn tela_vai_para_outra_thread() -> Res {
    // O ator do core pode rodar em qualquer thread do tokio.
    let mut s = open(10, 2)?;
    s.feed(b"ok");
    let text = std::thread::spawn(move || s.rows_text())
        .join()
        .map_err(|_| "thread")?;
    assert_eq!(text[0], "ok        ");
    Ok(())
}

/// O quadro do Ghostty, serializado, é o mesmo que as fixtures do core (que a
/// UI lê no teste de contrato dela).
#[test]
fn quadro_serializado_bate_com_a_fixture_do_core() -> Res {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../egeon-core/fixtures/protocol/events.json"
    );
    let fixtures: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(path)?)?;
    let want = &fixtures["screen_full"];

    let mut s = open(80, 24)?;
    s.feed(
        "hello \x1b[1;32mworld\x1b[0m\x1b[3;4;38;2;255;136;0;48;5;236m日本\x1b[0m\r\n\
         \x1b[2;7;9m$ \x1b[0m"
            .as_bytes(),
    );
    // "world" selecionado por arrasto, como na fixture.
    for (kind, x) in [(PointerKind::Press, 6.2), (PointerKind::Drag, 10.8)] {
        s.pointer(&Pointer {
            kind,
            button: Some(MouseButton::Left),
            x,
            y: 0.5,
            mods: Mods::default(),
            time_ms: 0,
            lines: 0,
        });
    }
    let got = serde_json::to_value(s.full_frame())?;

    for field in ["kind", "cols", "rows", "cursor", "scrollbar"] {
        assert_eq!(got[field], want[field], "{field}");
    }
    for row in 0..3 {
        assert_eq!(got["lines"][row], want["lines"][row], "linha {row}");
    }
    Ok(())
}

#[test]
fn bracketed_paste_segue_o_decset_2004() -> Res {
    let mut s = egeon_terminal::GhosttyScreen::new(Size { cols: 80, rows: 24 })?;
    assert!(!s.bracketed_paste(), "começa desligado");
    s.feed(b"\x1b[?2004h");
    assert!(s.bracketed_paste());
    // Outro modo no meio não mexe nele.
    s.feed(b"\x1b[?1h\x1b[?25l");
    assert!(s.bracketed_paste());
    s.feed(b"\x1b[?2004l");
    assert!(!s.bracketed_paste());
    // O modo ANSI 2004 (sem `?`) não é o bracketed paste.
    s.feed(b"\x1b[2004h");
    assert!(!s.bracketed_paste());
    // Reset total (RIS) desliga.
    s.feed(b"\x1b[?2004h\x1bc");
    assert!(!s.bracketed_paste());
    Ok(())
}
