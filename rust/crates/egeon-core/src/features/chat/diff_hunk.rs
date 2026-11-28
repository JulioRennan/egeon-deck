//! Diff como dados, para a bolha desenhar lado a lado.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum DiffKind {
    Context,
    Added,
    Removed,
    Note,
}

/// Uma linha do diff unificado que o passo guarda (`ChatStep.diff`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DiffLine {
    pub kind: DiffKind,
    pub text: String,
}

/// Uma célula de um lado do diff lado a lado.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Cell {
    pub number: Option<i64>,
    pub kind: DiffKind,
    pub text: String,
}

/// Uma linha da vista lado a lado: esquerda é o antes, direita o depois. Lado
/// vazio é a linha que só existe do outro lado.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Row {
    pub left: Option<Cell>,
    pub right: Option<Cell>,
}

/// Um trecho do diff, com onde ele começa em cada versão — vem do
/// `structuredPatch` do CLI (`@@ -a,b +c,d @@`). Sem cabeçalho (o diff montado
/// ao vivo de `old_string`/`new_string`) os números ficam vazios.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DiffHunk {
    pub old_start: Option<i64>,
    pub new_start: Option<i64>,
    pub lines: Vec<DiffLine>,
}

fn line(kind: DiffKind, text: &str) -> DiffLine {
    DiffLine {
        kind,
        text: text.to_owned(),
    }
}

impl DiffHunk {
    /// As linhas do passo (` `, `-`, `+`, `@@`, `…`) em trechos.
    pub fn parse(raw: &[String]) -> Vec<DiffHunk> {
        let mut hunks = Vec::new();
        let mut current = DiffHunk::default();
        let mut started = false;
        for text in raw {
            if text.starts_with("@@") {
                if started {
                    hunks.push(std::mem::take(&mut current));
                }
                current = DiffHunk {
                    old_start: number_after('-', text),
                    new_start: number_after('+', text),
                    lines: Vec::new(),
                };
                started = true;
                continue;
            }
            started = true;
            let mut chars = text.chars();
            let parsed = match chars.next() {
                Some('+') => line(DiffKind::Added, chars.as_str()),
                Some('-') => line(DiffKind::Removed, chars.as_str()),
                Some('…') => line(DiffKind::Note, text),
                Some(' ') => line(DiffKind::Context, chars.as_str()),
                _ => line(DiffKind::Context, text),
            };
            current.lines.push(parsed);
        }
        if started {
            hunks.push(current);
        }
        hunks
    }

    /// Cabeçalho unificado, para o parser gravar o que o `structuredPatch` diz.
    pub fn header(old_start: i64, old_lines: i64, new_start: i64, new_lines: i64) -> String {
        format!("@@ -{old_start},{old_lines} +{new_start},{new_lines} @@")
    }

    /// Pareia como o GitHub: contexto ocupa os dois lados; um bloco de `-`
    /// seguido de um bloco de `+` alinha linha a linha, e o que sobra fica
    /// sozinho no seu lado. Os números seguem cada versão.
    pub fn rows(&self) -> Vec<Row> {
        let mut out = Vec::new();
        let mut old_number = self.old_start;
        let mut new_number = self.new_start;
        let mut removed: Vec<&DiffLine> = Vec::new();
        let mut added: Vec<&DiffLine> = Vec::new();

        let flush = |out: &mut Vec<Row>,
                     removed: &mut Vec<&DiffLine>,
                     added: &mut Vec<&DiffLine>,
                     old_number: &mut Option<i64>,
                     new_number: &mut Option<i64>| {
            for i in 0..removed.len().max(added.len()) {
                let mut left = None;
                let mut right = None;
                if let Some(r) = removed.get(i) {
                    left = Some(Cell {
                        number: *old_number,
                        kind: DiffKind::Removed,
                        text: r.text.clone(),
                    });
                    *old_number = old_number.map(|n| n + 1);
                }
                if let Some(a) = added.get(i) {
                    right = Some(Cell {
                        number: *new_number,
                        kind: DiffKind::Added,
                        text: a.text.clone(),
                    });
                    *new_number = new_number.map(|n| n + 1);
                }
                out.push(Row { left, right });
            }
            removed.clear();
            added.clear();
        };

        for l in &self.lines {
            match l.kind {
                DiffKind::Removed => {
                    // `+` já acumulado e chega outro `-`: é outro bloco.
                    if !added.is_empty() {
                        flush(
                            &mut out,
                            &mut removed,
                            &mut added,
                            &mut old_number,
                            &mut new_number,
                        );
                    }
                    removed.push(l);
                }
                DiffKind::Added => added.push(l),
                DiffKind::Context => {
                    flush(
                        &mut out,
                        &mut removed,
                        &mut added,
                        &mut old_number,
                        &mut new_number,
                    );
                    out.push(Row {
                        left: Some(Cell {
                            number: old_number,
                            kind: DiffKind::Context,
                            text: l.text.clone(),
                        }),
                        right: Some(Cell {
                            number: new_number,
                            kind: DiffKind::Context,
                            text: l.text.clone(),
                        }),
                    });
                    old_number = old_number.map(|n| n + 1);
                    new_number = new_number.map(|n| n + 1);
                }
                DiffKind::Note => {
                    flush(
                        &mut out,
                        &mut removed,
                        &mut added,
                        &mut old_number,
                        &mut new_number,
                    );
                    let note = Cell {
                        number: None,
                        kind: DiffKind::Note,
                        text: l.text.clone(),
                    };
                    out.push(Row {
                        left: Some(note.clone()),
                        right: Some(note),
                    });
                }
            }
        }
        flush(
            &mut out,
            &mut removed,
            &mut added,
            &mut old_number,
            &mut new_number,
        );
        out
    }
}

/// Os dígitos depois da primeira ocorrência de `sign` no cabeçalho.
fn number_after(sign: char, header: &str) -> Option<i64> {
    let at = header.find(sign)?;
    let digits: String = header[at + sign.len_utf8()..]
        .chars()
        .take_while(|c| c.is_numeric())
        .collect();
    digits.parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn raw(lines: &[&str]) -> Vec<String> {
        lines.iter().map(|l| (*l).to_owned()).collect()
    }

    #[test]
    fn le_cabecalho_e_tipos() {
        let hunks = DiffHunk::parse(&raw(&[
            "@@ -3,2 +3,3 @@",
            " ctx",
            "-old",
            "+new",
            "+more",
            "… +5 linhas",
        ]));
        assert_eq!(hunks.len(), 1);
        assert_eq!(hunks[0].old_start, Some(3));
        assert_eq!(hunks[0].new_start, Some(3));
        assert_eq!(
            hunks[0].lines.iter().map(|l| l.kind).collect::<Vec<_>>(),
            [
                DiffKind::Context,
                DiffKind::Removed,
                DiffKind::Added,
                DiffKind::Added,
                DiffKind::Note
            ]
        );
        assert_eq!(hunks[0].lines[1].text, "old");
        assert_eq!(
            hunks[0].lines[4].text, "… +5 linhas",
            "a nota guarda a linha inteira"
        );
    }

    #[test]
    fn diff_sem_cabecalho_nao_tem_numeros() {
        let hunks = DiffHunk::parse(&raw(&["-a", "+b"]));
        assert_eq!(hunks.len(), 1);
        assert_eq!(hunks[0].old_start, None);
        assert_eq!(
            hunks[0].rows(),
            [Row {
                left: Some(Cell {
                    number: None,
                    kind: DiffKind::Removed,
                    text: "a".into()
                }),
                right: Some(Cell {
                    number: None,
                    kind: DiffKind::Added,
                    text: "b".into()
                }),
            }]
        );
    }

    /// Contexto nos dois lados; `-` e `+` alinhados linha a linha; a sobra fica
    /// sozinha; os números seguem cada versão.
    #[test]
    fn linhas_pareiam_remocoes_com_adicoes_como_o_github() {
        let hunk = &DiffHunk::parse(&raw(&[
            "@@ -1,4 +1,5 @@",
            " {",
            "-  \"port\": 8391,",
            "-  \"debug\": false,",
            "+  \"port\": 8392,",
            "+  \"debug\": true,",
            "+  \"log\": \"x\",",
            " }",
        ]))[0];
        let rows = hunk.rows();
        assert_eq!(rows.len(), 5);
        let number = |cell: &Option<Cell>| cell.as_ref().and_then(|c| c.number);
        let kind = |cell: &Option<Cell>| cell.as_ref().map(|c| c.kind);
        assert_eq!(
            (number(&rows[0].left), number(&rows[0].right)),
            (Some(1), Some(1))
        );
        assert_eq!(kind(&rows[1].left), Some(DiffKind::Removed));
        assert_eq!(kind(&rows[1].right), Some(DiffKind::Added));
        assert_eq!(
            (number(&rows[1].left), number(&rows[1].right)),
            (Some(2), Some(2))
        );
        assert_eq!(
            (number(&rows[2].left), number(&rows[2].right)),
            (Some(3), Some(3))
        );
        assert!(rows[3].left.is_none());
        assert_eq!(
            rows[3].right.as_ref().map(|c| c.text.as_str()),
            Some("  \"log\": \"x\",")
        );
        assert_eq!(number(&rows[3].right), Some(4));
        assert_eq!(
            (number(&rows[4].left), number(&rows[4].right)),
            (Some(4), Some(5))
        );
        assert_eq!(kind(&rows[4].left), Some(DiffKind::Context));
    }

    #[test]
    fn cabecalho_do_structured_patch() {
        assert_eq!(DiffHunk::header(3, 2, 3, 3), "@@ -3,2 +3,3 @@");
    }

    #[test]
    fn varios_trechos_e_linha_vazia_como_contexto() {
        let hunks = DiffHunk::parse(&raw(&[
            "@@ -1,1 +1,1 @@",
            "-a",
            "@@ -9,1 +9,1 @@",
            "",
            "+b",
        ]));
        assert_eq!(hunks.len(), 2);
        assert_eq!(hunks[1].old_start, Some(9));
        assert_eq!(hunks[1].lines[0], line(DiffKind::Context, ""));
        // `+` acumulado e outro `-`: é outro bloco, sem emparelhar com o anterior.
        let rows = DiffHunk::parse(&raw(&["-a", "+b", "-c"]))[0].rows();
        assert_eq!(rows.len(), 2);
        assert!(rows[1].right.is_none());
    }
}
