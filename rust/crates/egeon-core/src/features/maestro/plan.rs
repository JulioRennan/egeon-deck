//! O desenho de uma bancada que o maestro manda aplicar (ADR-066). Porte de
//! `MaestroPlan.swift`.
//!
//! Lido à mão sobre o `Value`, e não por `derive`: chave desconhecida é erro
//! com o lugar dito, ausente e `null` são coisas diferentes, e a mensagem volta
//! direto para o agente corrigir. A ordem das conferências é a do `init(from:)`
//! do Swift. Os textos de `JSON inválido` e `tipo errado` que lá vinham do
//! Foundation aqui são do serde ou nossos.

use serde_json::{Map, Value};

use crate::features::node::model::NodeKind;

/// Um campo em três estados, porque o JSON tem três: ausente mantém, `null`
/// volta ao padrão do CLI, valor troca.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub enum PlanField<T> {
    #[default]
    Keep,
    Clear,
    Set(T),
}

impl<T: Clone> PlanField<T> {
    pub fn applied(&self, current: Option<T>) -> Option<T> {
        match self {
            PlanField::Keep => current,
            PlanField::Clear => None,
            PlanField::Set(value) => Some(value.clone()),
        }
    }

    pub fn is_keep(&self) -> bool {
        matches!(self, PlanField::Keep)
    }
}

/// Posição e tamanho de um card, no documento do canvas (y cresce para
/// baixo). Só `x`/`y` move, só `w`/`h` redimensiona.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct PlanFrame {
    pub x: Option<f64>,
    pub y: Option<f64>,
    pub w: Option<f64>,
    pub h: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct PlanNode {
    pub id: String,
    pub kind: Option<NodeKind>,
    pub cli: PlanField<String>,
    pub model: PlanField<String>,
    pub effort: PlanField<String>,
    pub ultracode: PlanField<bool>,
    pub role: PlanField<String>,
    pub rules: PlanField<String>,
    pub cwd: PlanField<String>,
    pub config: PlanField<String>,
    /// O comando que um terminal `shell` roda ao subir.
    pub cmd: PlanField<String>,
    /// Vence o arranjo automático.
    pub frame: Option<PlanFrame>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct PlanEdge {
    pub from: String,
    pub to: String,
    /// Ida e volta: cria (ou ajusta) as duas setas.
    pub both: bool,
    pub max_sends: PlanField<i64>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct PlanUnlink {
    pub from: String,
    pub to: String,
    pub both: bool,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct MaestroPlan {
    pub rules: PlanField<String>,
    pub nodes: Vec<PlanNode>,
    pub remove: Vec<String>,
    pub edges: Vec<PlanEdge>,
    pub unlink: Vec<PlanUnlink>,
    /// Pode reiniciar ou remover terminal em segundo plano.
    pub force: bool,
    /// Rearrumar o canvas. Ausente = só quando o plano cria ou remove.
    pub layout: Option<bool>,
}

impl MaestroPlan {
    pub fn is_empty(&self) -> bool {
        self.rules.is_keep()
            && self.nodes.is_empty()
            && self.remove.is_empty()
            && self.edges.is_empty()
            && self.unlink.is_empty()
            && self.layout != Some(true)
    }

    /// Lê o corpo do `egeon plan`/`egeon apply`. O erro vem em português e
    /// apontando o lugar.
    pub fn parse(data: &[u8]) -> Result<Self, String> {
        if data.is_empty() {
            return Err("plano vazio — mande o JSON no stdin".to_owned());
        }
        let value: Value =
            serde_json::from_slice(data).map_err(|e| format!("JSON inválido: {e}"))?;
        plan(&value).map_err(|e| e.message())
    }
}

#[derive(Debug, Clone, PartialEq)]
enum Step {
    Key(String),
    Index(usize),
}

enum Failure {
    Unknown {
        path: String,
        keys: Vec<String>,
        expected: Vec<String>,
    },
    Missing(String, Vec<Step>),
    Mismatch(&'static str, Vec<Step>),
    Null(Vec<Step>),
    Corrupted(String, Vec<Step>),
}

impl Failure {
    fn message(&self) -> String {
        match self {
            Failure::Unknown {
                path,
                keys,
                expected,
            } => format!(
                "{path}: campo(s) desconhecido(s) {} — aceitos: {}",
                keys.iter()
                    .map(|k| format!("'{k}'"))
                    .collect::<Vec<_>>()
                    .join(", "),
                expected.join(", ")
            ),
            Failure::Missing(key, path) => format!("falta '{key}'{}", place(path)),
            Failure::Mismatch(expected, path) => {
                format!("tipo errado{}: esperava {expected}", place(path))
            }
            Failure::Null(path) => format!("valor nulo onde não pode{}", place(path)),
            Failure::Corrupted(detail, path) => format!("JSON inválido{}: {detail}", place(path)),
        }
    }
}

/// ` em nodes[0].model`, como o `codingPath` do Swift.
fn place(path: &[Step]) -> String {
    if path.is_empty() {
        return String::new();
    }
    let text: String = path
        .iter()
        .map(|s| match s {
            Step::Key(k) => format!(".{k}"),
            Step::Index(i) => format!("[{i}]"),
        })
        .collect();
    format!(" em {}", text.strip_prefix('.').unwrap_or(&text))
}

fn at(path: &[Step], step: Step) -> Vec<Step> {
    let mut out = path.to_vec();
    out.push(step);
    out
}

fn object<'a>(value: &'a Value, path: &[Step]) -> Result<&'a Map<String, Value>, Failure> {
    // `null` onde se espera objeto é `valueNotFound` no Swift, não tipo errado.
    if value.is_null() {
        return Err(Failure::Null(path.to_vec()));
    }
    value
        .as_object()
        .ok_or_else(|| Failure::Mismatch("um objeto", path.to_vec()))
}

fn check(
    map: &Map<String, Value>,
    known: &[&str],
    path: &str,
    ignoring: &[&str],
) -> Result<(), Failure> {
    let mut unknown: Vec<String> = map
        .keys()
        .filter(|k| !ignoring.contains(&k.as_str()) && !known.contains(&k.as_str()))
        .cloned()
        .collect();
    unknown.sort();
    if unknown.is_empty() {
        return Ok(());
    }
    Err(Failure::Unknown {
        path: path.to_owned(),
        keys: unknown,
        expected: known.iter().map(|k| (*k).to_owned()).collect(),
    })
}

trait Read: Sized {
    const NAME: &'static str;
    fn read(value: &Value) -> Option<Self>;
}

impl Read for String {
    const NAME: &'static str = "texto";
    fn read(value: &Value) -> Option<Self> {
        value.as_str().map(str::to_owned)
    }
}

impl Read for bool {
    const NAME: &'static str = "verdadeiro ou falso";
    fn read(value: &Value) -> Option<Self> {
        value.as_bool()
    }
}

impl Read for i64 {
    const NAME: &'static str = "número inteiro";
    fn read(value: &Value) -> Option<Self> {
        value.as_i64().or_else(|| {
            value
                .as_f64()
                .filter(|f| f.fract() == 0.0 && f.abs() < 9e15)
                .map(|f| f as i64)
        })
    }
}

impl Read for f64 {
    const NAME: &'static str = "número";
    fn read(value: &Value) -> Option<Self> {
        value.as_f64()
    }
}

/// `decode`: obrigatório, sem `null`.
fn required<T: Read>(map: &Map<String, Value>, key: &str, path: &[Step]) -> Result<T, Failure> {
    match map.get(key) {
        None => Err(Failure::Missing(key.to_owned(), path.to_vec())),
        Some(Value::Null) => Err(Failure::Null(at(path, Step::Key(key.to_owned())))),
        Some(v) => T::read(v)
            .ok_or_else(|| Failure::Mismatch(T::NAME, at(path, Step::Key(key.to_owned())))),
    }
}

/// `decodeIfPresent`: ausente e `null` são `None`.
fn optional<T: Read>(
    map: &Map<String, Value>,
    key: &str,
    path: &[Step],
) -> Result<Option<T>, Failure> {
    match map.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(v) => T::read(v)
            .map(Some)
            .ok_or_else(|| Failure::Mismatch(T::NAME, at(path, Step::Key(key.to_owned())))),
    }
}

fn field<T: Read>(
    map: &Map<String, Value>,
    key: &str,
    path: &[Step],
) -> Result<PlanField<T>, Failure> {
    match map.get(key) {
        None => Ok(PlanField::Keep),
        Some(Value::Null) => Ok(PlanField::Clear),
        Some(v) => T::read(v)
            .map(PlanField::Set)
            .ok_or_else(|| Failure::Mismatch(T::NAME, at(path, Step::Key(key.to_owned())))),
    }
}

fn list<T>(
    map: &Map<String, Value>,
    key: &str,
    path: &[Step],
    each: impl Fn(&Value, &[Step]) -> Result<T, Failure>,
) -> Result<Vec<T>, Failure> {
    let here = at(path, Step::Key(key.to_owned()));
    match map.get(key) {
        None | Some(Value::Null) => Ok(Vec::new()),
        Some(Value::Array(items)) => items
            .iter()
            .enumerate()
            .map(|(i, item)| each(item, &at(&here, Step::Index(i))))
            .collect(),
        Some(_) => Err(Failure::Mismatch("uma lista", here)),
    }
}

const PLAN_KEYS: [&str; 7] = [
    "rules", "nodes", "remove", "edges", "unlink", "force", "layout",
];
const NODE_KEYS: [&str; 12] = [
    "id",
    "kind",
    "cli",
    "model",
    "effort",
    "ultracode",
    "role",
    "rules",
    "cwd",
    "config",
    "cmd",
    "frame",
];
/// O que o `egeon bench` mostra e não se escreve: copiar um nó de lá para o
/// plano não pode falhar por causa deles.
const READ_ONLY: [&str; 4] = ["state", "you", "maestro", "approvesPermissions"];
const FRAME_KEYS: [&str; 4] = ["x", "y", "w", "h"];
const EDGE_KEYS: [&str; 4] = ["from", "to", "both", "maxSends"];
const UNLINK_KEYS: [&str; 3] = ["from", "to", "both"];

fn plan(value: &Value) -> Result<MaestroPlan, Failure> {
    let map = object(value, &[])?;
    check(map, &PLAN_KEYS, "plano", &[])?;
    Ok(MaestroPlan {
        rules: field(map, "rules", &[])?,
        nodes: list(map, "nodes", &[], node)?,
        remove: list(map, "remove", &[], |v, p| {
            String::read(v).ok_or_else(|| {
                if v.is_null() {
                    Failure::Null(p.to_vec())
                } else {
                    Failure::Mismatch(String::NAME, p.to_vec())
                }
            })
        })?,
        edges: list(map, "edges", &[], edge)?,
        unlink: list(map, "unlink", &[], unlink)?,
        force: optional(map, "force", &[])?.unwrap_or(false),
        layout: optional(map, "layout", &[])?,
    })
}

fn node(value: &Value, path: &[Step]) -> Result<PlanNode, Failure> {
    let map = object(value, path)?;
    let id: String = required(map, "id", path)?;
    let label = format!("nó '{id}'");
    // Só o usuário faz um maestro, e a aprovação vem com ele: `true` aqui é
    // pedido de poder, `false` é cópia do `egeon bench`.
    if map.get("maestro").and_then(Value::as_bool) == Some(true) {
        return Err(Failure::Unknown {
            path: label,
            keys: vec!["maestro".to_owned()],
            expected: vec!["— só o usuário faz um maestro, no formulário".to_owned()],
        });
    }
    if map.get("approvesPermissions").and_then(Value::as_bool) == Some(true) {
        return Err(Failure::Unknown {
            path: label,
            keys: vec!["approvesPermissions".to_owned()],
            expected: vec!["— vem com o maestro, que só o usuário liga no formulário".to_owned()],
        });
    }
    check(map, &NODE_KEYS, &label, &READ_ONLY)?;
    let kind = match map.get("kind") {
        None | Some(Value::Null) => None,
        Some(Value::String(raw)) => Some(
            serde_json::from_value::<NodeKind>(Value::String(raw.clone())).map_err(|_| {
                Failure::Corrupted(
                    format!("tipo de nó '{raw}' não existe — use agent, shell, web ou queue"),
                    at(path, Step::Key("kind".to_owned())),
                )
            })?,
        ),
        Some(_) => {
            return Err(Failure::Mismatch(
                String::NAME,
                at(path, Step::Key("kind".to_owned())),
            ));
        }
    };
    let cli = field(map, "cli", path)?;
    let model = field(map, "model", path)?;
    let effort = field(map, "effort", path)?;
    let ultracode = field(map, "ultracode", path)?;
    let role = field(map, "role", path)?;
    let rules = field(map, "rules", path)?;
    let cwd = field(map, "cwd", path)?;
    let config = field(map, "config", path)?;
    let cmd = field(map, "cmd", path)?;
    let frame = match map.get("frame") {
        None | Some(Value::Null) => None,
        Some(v) => {
            let here = at(path, Step::Key("frame".to_owned()));
            let f = object(v, &here)?;
            check(f, &FRAME_KEYS, "frame", &[])?;
            Some(PlanFrame {
                x: optional(f, "x", &here)?,
                y: optional(f, "y", &here)?,
                w: optional(f, "w", &here)?,
                h: optional(f, "h", &here)?,
            })
        }
    };
    Ok(PlanNode {
        id,
        kind,
        cli,
        model,
        effort,
        ultracode,
        role,
        rules,
        cwd,
        config,
        cmd,
        frame,
    })
}

fn edge(value: &Value, path: &[Step]) -> Result<PlanEdge, Failure> {
    let map = object(value, path)?;
    let from: String = required(map, "from", path)?;
    let to: String = required(map, "to", path)?;
    check(map, &EDGE_KEYS, &format!("aresta {from}→{to}"), &[])?;
    Ok(PlanEdge {
        both: optional(map, "both", path)?.unwrap_or(false),
        max_sends: field(map, "maxSends", path)?,
        from,
        to,
    })
}

fn unlink(value: &Value, path: &[Step]) -> Result<PlanUnlink, Failure> {
    let map = object(value, path)?;
    let from: String = required(map, "from", path)?;
    let to: String = required(map, "to", path)?;
    check(map, &UNLINK_KEYS, &format!("unlink {from}→{to}"), &[])?;
    Ok(PlanUnlink {
        both: optional(map, "both", path)?.unwrap_or(false),
        from,
        to,
    })
}
