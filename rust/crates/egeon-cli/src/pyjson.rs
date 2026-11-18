//! JSON com a ordem das chaves preservada e a saída do `json.dumps` do python.
//!
//! O gancho de permissão devolvia ao CLI o `output` do app passando por
//! `json.dumps`; o `serde_json::Value` reordena as chaves, e a saída tem de
//! sair igual. Número é o `serde_json::Number`: inteiros até `u64` idênticos;
//! maior que isso sai em notação científica (o python imprime o inteiro
//! inteiro) e float pode divergir do `repr` do python em expoentes. O app não
//! manda nenhum dos dois.

use std::fmt::{self, Write};

use serde::de::{Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};
use serde_json::Number;

#[derive(Debug, Clone, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Number(Number),
    Str(String),
    Array(Vec<Json>),
    Object(Vec<(String, Json)>),
}

impl Json {
    pub fn parse(bytes: &[u8]) -> Result<Json, serde_json::Error> {
        serde_json::from_slice(bytes)
    }

    /// Primeira chave com esse nome, se isto for um objeto.
    pub fn get(&self, key: &str) -> Option<&Json> {
        match self {
            Json::Object(pairs) => pairs.iter().find(|(k, _)| k == key).map(|(_, v)| v),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Json::Str(s) => Some(s),
            _ => None,
        }
    }

    /// A verdade do python: `x or padrão` cai no padrão para estes valores.
    pub fn is_truthy(&self) -> bool {
        match self {
            Json::Null => false,
            Json::Bool(b) => *b,
            Json::Number(n) => n.as_f64() != Some(0.0),
            Json::Str(s) => !s.is_empty(),
            Json::Array(a) => !a.is_empty(),
            Json::Object(o) => !o.is_empty(),
        }
    }

    /// `json.dumps(valor)`: `", "` e `": "` como separadores, e tudo fora do
    /// ASCII em `\uXXXX`.
    pub fn dumps(&self) -> String {
        let mut out = String::new();
        self.write(&mut out);
        out
    }

    fn write(&self, out: &mut String) {
        match self {
            Json::Null => out.push_str("null"),
            Json::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
            Json::Number(n) => {
                let _ = write!(out, "{n}");
            }
            Json::Str(s) => write_string(s, out),
            Json::Array(items) => {
                out.push('[');
                for (i, item) in items.iter().enumerate() {
                    if i > 0 {
                        out.push_str(", ");
                    }
                    item.write(out);
                }
                out.push(']');
            }
            Json::Object(pairs) => {
                out.push('{');
                for (i, (key, value)) in pairs.iter().enumerate() {
                    if i > 0 {
                        out.push_str(", ");
                    }
                    write_string(key, out);
                    out.push_str(": ");
                    value.write(out);
                }
                out.push('}');
            }
        }
    }
}

fn write_string(s: &str, out: &mut String) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{8}' => out.push_str("\\b"),
            '\u{c}' => out.push_str("\\f"),
            c if (' '..='~').contains(&c) => out.push(c),
            c => {
                let mut units = [0u16; 2];
                for unit in c.encode_utf16(&mut units) {
                    let _ = write!(out, "\\u{unit:04x}");
                }
            }
        }
    }
    out.push('"');
}

impl<'de> Deserialize<'de> for Json {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Json, D::Error> {
        struct JsonVisitor;

        impl<'de> Visitor<'de> for JsonVisitor {
            type Value = Json;

            fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
                f.write_str("um valor JSON")
            }

            fn visit_unit<E>(self) -> Result<Json, E> {
                Ok(Json::Null)
            }

            fn visit_bool<E>(self, v: bool) -> Result<Json, E> {
                Ok(Json::Bool(v))
            }

            fn visit_i64<E>(self, v: i64) -> Result<Json, E> {
                Ok(Json::Number(v.into()))
            }

            fn visit_u64<E>(self, v: u64) -> Result<Json, E> {
                Ok(Json::Number(v.into()))
            }

            fn visit_f64<E>(self, v: f64) -> Result<Json, E> {
                Ok(Number::from_f64(v).map_or(Json::Null, Json::Number))
            }

            fn visit_str<E>(self, v: &str) -> Result<Json, E> {
                Ok(Json::Str(v.to_owned()))
            }

            fn visit_string<E>(self, v: String) -> Result<Json, E> {
                Ok(Json::Str(v))
            }

            fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Json, A::Error> {
                let mut items = Vec::new();
                while let Some(item) = seq.next_element()? {
                    items.push(item);
                }
                Ok(Json::Array(items))
            }

            fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Json, A::Error> {
                let mut pairs: Vec<(String, Json)> = Vec::new();
                while let Some((key, value)) = map.next_entry::<String, Json>()? {
                    // Chave repetida: o dict do python fica com o último valor
                    // na posição do primeiro.
                    match pairs.iter_mut().find(|(k, _)| *k == key) {
                        Some(slot) => slot.1 = value,
                        None => pairs.push((key, value)),
                    }
                }
                Ok(Json::Object(pairs))
            }
        }

        deserializer.deserialize_any(JsonVisitor)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn roundtrip(raw: &str) -> String {
        Json::parse(raw.as_bytes()).unwrap().dumps()
    }

    #[test]
    fn separadores_e_ordem_do_python() {
        // `json.dumps(json.loads(...))` — a ordem de entrada, não a alfabética.
        assert_eq!(
            roundtrip(r#"{"z":1,"a":{"y":[1,2,{"k":null}],"b":true},"m":false}"#),
            r#"{"z": 1, "a": {"y": [1, 2, {"k": null}], "b": true}, "m": false}"#
        );
        assert_eq!(roundtrip("{}"), "{}");
        assert_eq!(roundtrip("[]"), "[]");
    }

    #[test]
    fn ascii_garantido_como_no_ensure_ascii() {
        assert_eq!(roundtrip(r#""ação""#), "\"a\\u00e7\\u00e3o\"");
        // Fora do plano básico: par substituto, como o python.
        assert_eq!(roundtrip(r#""😀""#), "\"\\ud83d\\ude00\"");
        assert_eq!(
            roundtrip(r#""a\"b\\c\n\t\u0001\u007f""#),
            "\"a\\\"b\\\\c\\n\\t\\u0001\\u007f\""
        );
    }

    #[test]
    fn chave_repetida_fica_na_primeira_posicao_com_o_ultimo_valor() {
        assert_eq!(roundtrip(r#"{"a":1,"b":2,"a":3}"#), r#"{"a": 3, "b": 2}"#);
    }

    #[test]
    fn verdade_do_python() {
        for falso in ["null", "false", "0", "0.0", r#""""#, "[]", "{}"] {
            assert!(
                !Json::parse(falso.as_bytes()).unwrap().is_truthy(),
                "{falso}"
            );
        }
        for verdadeiro in ["true", "1", r#""x""#, "[0]", r#"{"a":0}"#] {
            assert!(
                Json::parse(verdadeiro.as_bytes()).unwrap().is_truthy(),
                "{verdadeiro}"
            );
        }
    }

    #[test]
    fn json_invalido_e_erro() {
        assert!(Json::parse(b"{").is_err());
        assert!(Json::parse(b"{} x").is_err());
    }
}
