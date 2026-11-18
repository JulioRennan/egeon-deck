//! Ler e gravar os arquivos JSON de organização (`workbenches.json`,
//! `workspaces.json`, `components.json`, `templates.json`).
//!
//! Funções síncronas com o caminho como parâmetro: o core as chama de
//! `spawn_blocking`, fora do ator.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use serde::de::{DeserializeOwned, Deserializer, MapAccess, SeqAccess, Visitor};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

#[derive(Debug, thiserror::Error)]
pub enum PersistError {
    #[error("não foi possível gravar {path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("não foi possível codificar {path}: {source}")]
    Encode {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
}

/// O conteúdo do arquivo, ou `None` quando ele não existe ou não abre — o
/// `try? Data(contentsOf:)` do Swift.
pub fn read_bytes(path: &Path) -> Option<Vec<u8>> {
    std::fs::read(path).ok()
}

/// Grava como o Swift grava: chaves em ordem alfabética e indentado, para o
/// arquivo editado à mão continuar legível e o diff, pequeno.
///
/// Atômico (arquivo temporário e `rename`), ao contrário do Swift: quem lê no
/// meio da gravação, ou o app morto no meio dela, nunca vê meio arquivo.
pub fn write_pretty<T: Serialize>(path: &Path, value: &T) -> Result<(), PersistError> {
    let io = |source| PersistError::Io {
        path: path.to_owned(),
        source,
    };
    let encode = |source| PersistError::Encode {
        path: path.to_owned(),
        source,
    };
    let tree = serde_json::to_value(value).map_err(encode)?;
    let bytes = serde_json::to_vec_pretty(&canonical(tree)).map_err(encode)?;

    if let Some(dir) = path.parent().filter(|d| !d.as_os_str().is_empty()) {
        std::fs::create_dir_all(dir).map_err(io)?;
    }
    // Nome único por gravação: duas ao mesmo tempo no mesmo arquivo não
    // pisam no temporário uma da outra.
    static COUNTER: AtomicU64 = AtomicU64::new(0);
    let mut tmp = path.as_os_str().to_owned();
    tmp.push(format!(
        ".{}.{}.tmp",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    let tmp = PathBuf::from(tmp);
    let written = (|| {
        let mut file = std::fs::File::create(&tmp)?;
        file.write_all(&bytes)?;
        file.sync_all()?;
        std::fs::rename(&tmp, path)
    })();
    if written.is_err() {
        let _ = std::fs::remove_file(&tmp);
    }
    written.map_err(io)
}

/// Lê o JSON como o `JSONDecoder` do Swift lê, para os arquivos de `~/.egeon`
/// abrirem igual:
///
/// - o BOM no começo é aceito (UTF-8, e UTF-16/32 pelos quatro bytes do BOM);
/// - chave repetida não é erro e a PRIMEIRA vence — o `serde_json` ficaria com a
///   última, e um `name` duplicado derrubaria a lista inteira;
/// - número inteiro escrito como float (`5.0`) lê como inteiro.
///
/// Sem isto o arquivo que o Swift abre voltava vazio, e a gravação seguinte
/// apagava as bancadas.
pub fn parse<T: DeserializeOwned>(bytes: &[u8]) -> Result<T, serde_json::Error> {
    use serde::de::Error as _;
    let text = decode_text(bytes).ok_or_else(|| serde_json::Error::custom("texto inválido"))?;
    let mut de = serde_json::Deserializer::from_str(&text);
    let Lenient(value) = Lenient::deserialize(&mut de)?;
    de.end()?;
    serde_json::from_value(value)
}

/// O texto do arquivo: o BOM manda a codificação; sem BOM é UTF-8.
fn decode_text(bytes: &[u8]) -> Option<String> {
    let units16 = |rest: &[u8], big: bool| -> Option<String> {
        let (pairs, tail) = rest.as_chunks::<2>();
        if !tail.is_empty() {
            return None;
        }
        let units: Vec<u16> = pairs
            .iter()
            .map(|c| {
                if big {
                    u16::from_be_bytes(*c)
                } else {
                    u16::from_le_bytes(*c)
                }
            })
            .collect();
        String::from_utf16(&units).ok()
    };
    let units32 = |rest: &[u8], big: bool| -> Option<String> {
        let (quads, tail) = rest.as_chunks::<4>();
        if !tail.is_empty() {
            return None;
        }
        quads
            .iter()
            .map(|c| {
                char::from_u32(if big {
                    u32::from_be_bytes(*c)
                } else {
                    u32::from_le_bytes(*c)
                })
            })
            .collect()
    };
    match bytes {
        [0xEF, 0xBB, 0xBF, rest @ ..] => String::from_utf8(rest.to_vec()).ok(),
        [0xFF, 0xFE, 0x00, 0x00, rest @ ..] => units32(rest, false),
        [0x00, 0x00, 0xFE, 0xFF, rest @ ..] => units32(rest, true),
        [0xFF, 0xFE, rest @ ..] => units16(rest, false),
        [0xFE, 0xFF, rest @ ..] => units16(rest, true),
        _ => String::from_utf8(bytes.to_vec()).ok(),
    }
}

/// Float que é inteiro exato, dentro do que o `Int` do Swift lê.
fn integral(f: f64) -> Option<i64> {
    (f.fract() == 0.0 && f.abs() < 9.0e15).then_some(f as i64)
}

/// Um `Value` montado à mão: chave repetida fica com a primeira.
struct Lenient(Value);

impl<'de> Deserialize<'de> for Lenient {
    fn deserialize<D: Deserializer<'de>>(de: D) -> Result<Self, D::Error> {
        struct V;
        impl<'de> Visitor<'de> for V {
            type Value = Lenient;
            fn expecting(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str("JSON")
            }
            fn visit_unit<E>(self) -> Result<Lenient, E> {
                Ok(Lenient(Value::Null))
            }
            fn visit_bool<E>(self, v: bool) -> Result<Lenient, E> {
                Ok(Lenient(Value::Bool(v)))
            }
            fn visit_i64<E>(self, v: i64) -> Result<Lenient, E> {
                Ok(Lenient(Value::from(v)))
            }
            fn visit_u64<E>(self, v: u64) -> Result<Lenient, E> {
                Ok(Lenient(Value::from(v)))
            }
            fn visit_f64<E>(self, v: f64) -> Result<Lenient, E> {
                Ok(Lenient(match integral(v) {
                    Some(i) => Value::from(i),
                    None => Value::from(v),
                }))
            }
            fn visit_str<E>(self, v: &str) -> Result<Lenient, E> {
                Ok(Lenient(Value::String(v.to_owned())))
            }
            fn visit_string<E>(self, v: String) -> Result<Lenient, E> {
                Ok(Lenient(Value::String(v)))
            }
            fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Lenient, A::Error> {
                let mut out = Vec::new();
                while let Some(Lenient(item)) = seq.next_element()? {
                    out.push(item);
                }
                Ok(Lenient(Value::Array(out)))
            }
            fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Lenient, A::Error> {
                let mut out = Map::new();
                while let Some((key, Lenient(value))) = map.next_entry::<String, Lenient>()? {
                    out.entry(key).or_insert(value);
                }
                Ok(Lenient(Value::Object(out)))
            }
        }
        de.deserialize_any(V)
    }
}

/// Chaves ordenadas e número inteiro sem `.0` (o `JSONEncoder` do Swift grava
/// `120`, não `120.0`). Reconstruído em ordem para não depender de a
/// `serde_json` ter ou não `preserve_order` ligado por outro crate.
pub(crate) fn canonical(value: Value) -> Value {
    match value {
        Value::Object(map) => {
            let mut entries: Vec<(String, Value)> = map.into_iter().collect();
            entries.sort_by(|a, b| a.0.cmp(&b.0));
            Value::Object(
                entries
                    .into_iter()
                    .map(|(k, v)| (k, canonical(v)))
                    .collect(),
            )
        }
        Value::Array(items) => Value::Array(items.into_iter().map(canonical).collect()),
        Value::Number(n) => match n.as_f64().filter(|_| n.is_f64()).and_then(integral) {
            Some(i) => Value::from(i),
            None => Value::Number(n),
        },
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn grava_ordenado_inteiro_sem_ponto_zero_e_sem_sobra() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("a/b.json");
        write_pretty(&file, &json!({"z": 1, "a": {"y": 120.0, "x": 0.5}})).unwrap();
        let text = std::fs::read_to_string(&file).unwrap();
        assert_eq!(
            text,
            "{\n  \"a\": {\n    \"x\": 0.5,\n    \"y\": 120\n  },\n  \"z\": 1\n}"
        );
        let left: Vec<_> = std::fs::read_dir(dir.path().join("a"))
            .unwrap()
            .map(|e| e.unwrap().file_name())
            .collect();
        assert_eq!(left, ["b.json"], "nenhum temporário sobra");
    }

    #[derive(Debug, PartialEq, serde::Deserialize)]
    struct Sample {
        name: String,
        n: Option<i64>,
    }

    fn utf16(text: &str, big: bool, bom: bool) -> Vec<u8> {
        let mut out = Vec::new();
        if bom {
            out.extend(if big { [0xFE, 0xFF] } else { [0xFF, 0xFE] });
        }
        for unit in text.encode_utf16() {
            out.extend(if big {
                unit.to_be_bytes()
            } else {
                unit.to_le_bytes()
            });
        }
        out
    }

    #[test]
    fn le_como_o_jsondecoder_do_swift() {
        let want = Sample {
            name: "ação".into(),
            n: Some(5),
        };
        let json = r#"{"name":"ação","n":5}"#;
        assert_eq!(parse::<Sample>(json.as_bytes()).unwrap(), want);
        // BOM UTF-8, UTF-16 e UTF-32 (os dois sentidos).
        let mut bom = vec![0xEF, 0xBB, 0xBF];
        bom.extend(json.as_bytes());
        assert_eq!(parse::<Sample>(&bom).unwrap(), want);
        assert_eq!(parse::<Sample>(&utf16(json, false, true)).unwrap(), want);
        assert_eq!(parse::<Sample>(&utf16(json, true, true)).unwrap(), want);
        let mut utf32 = vec![0xFF, 0xFE, 0x00, 0x00];
        utf32.extend(json.chars().flat_map(|c| (c as u32).to_le_bytes()));
        assert_eq!(parse::<Sample>(&utf32).unwrap(), want);
        // Sem BOM, UTF-16 não é texto.
        assert!(parse::<Sample>(&utf16(json, false, false)).is_err());
        assert!(parse::<Sample>(&[0xFF, 0xFF, 0x7B]).is_err());
    }

    #[test]
    fn chave_repetida_fica_com_a_primeira_e_nao_e_erro() {
        let got: Sample = parse(br#"{"name":"a","n":1,"name":"b","n":2}"#).unwrap();
        assert_eq!(
            got,
            Sample {
                name: "a".into(),
                n: Some(1)
            }
        );
        let nested: Value = parse(br#"{"x":{"k":1,"k":2},"x":3}"#).unwrap();
        assert_eq!(nested, serde_json::json!({"x": {"k": 1}}));
    }

    #[test]
    fn inteiro_escrito_como_float_le_como_inteiro_e_fracao_continua_erro() {
        assert_eq!(
            parse::<Sample>(br#"{"name":"a","n":5.0}"#).unwrap().n,
            Some(5)
        );
        assert_eq!(
            parse::<Sample>(br#"{"name":"a","n":1e2}"#).unwrap().n,
            Some(100)
        );
        assert!(parse::<Sample>(br#"{"name":"a","n":1.5}"#).is_err());
        // Lixo depois do JSON e JSON quebrado continuam erro.
        assert!(parse::<Sample>(br#"{"name":"a"} x"#).is_err());
        assert!(parse::<Sample>(b"{quebrado").is_err());
    }

    #[test]
    fn leitura_de_arquivo_ausente_ou_pasta_e_none() {
        let dir = tempfile::tempdir().unwrap();
        assert!(read_bytes(&dir.path().join("nada.json")).is_none());
        assert!(read_bytes(dir.path()).is_none());
    }
}

#[cfg(test)]
#[path = "json_file/fixtures.rs"]
mod fixtures;
