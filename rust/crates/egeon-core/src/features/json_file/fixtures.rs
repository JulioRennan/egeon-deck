//! Os arquivos de `~/.egeon` abrem aqui como no Swift, e o que o Rust grava o
//! Swift relê sem perda.
//!
//! `fixtures/org/entrada/` tem arquivos de cada época do formato;
//! `fixtures/org/esperado/` é o que o código REAL do Swift grava depois de
//! lê-los (`fixtures/org/oraculo/gerar.sh` os regenera). Cada caso aqui lê a
//! entrada com o Rust, grava, e compara com o esperado.
//!
//! Com `EGEON_ORG_DUMP=<pasta>` o teste também deixa lá o que o Rust gravou,
//! para `fixtures/org/oraculo/conferir.sh` pedir ao Swift que releia.

use std::path::{Path, PathBuf};

use serde::Serialize;
use serde_json::Value;

use super::{canonical, write_pretty};
use crate::features::node::store as components;
use crate::features::workbench::clock::WorkbenchClock;
use crate::features::workbench::service::assign_missing_colors;
use crate::features::workbench::store as workbenches;
use crate::features::workspace::store as workspaces;

const GENERATED: &str = "<gerado>";

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("fixtures/org")
}

fn cases(sub: &str) -> Vec<(String, PathBuf)> {
    let dir = root().join("entrada").join(sub);
    let mut found: Vec<_> = std::fs::read_dir(&dir)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().is_some_and(|e| e == "json"))
        .map(|p| (p.file_name().unwrap().to_string_lossy().into_owned(), p))
        .collect();
    found.sort();
    assert!(!found.is_empty(), "sem fixtures em {}", dir.display());
    found
}

fn read(path: &Path) -> Value {
    super::parse(&std::fs::read(path).unwrap()).unwrap_or(Value::Null)
}

/// Grava como o app grava e devolve o arquivo relido como valor.
fn written<T: Serialize>(sub: &str, name: &str, value: &T) -> Value {
    let dump = std::env::var_os("EGEON_ORG_DUMP").map(PathBuf::from);
    let dir = tempfile::tempdir().unwrap();
    let file = dir.path().join(name);
    write_pretty(&file, value).unwrap();
    if let Some(dump) = dump {
        let target = dump.join(sub);
        std::fs::create_dir_all(&target).unwrap();
        std::fs::copy(&file, target.join(name)).unwrap();
    }
    read(&file)
}

/// O id que faltava no arquivo é gerado ao acaso dos dois lados; só o fato de
/// ter sido gerado é comparável.
fn mask_generated_ids(input: &Value, output: &mut Value) {
    let (Value::Array(items), Value::Array(out)) = (input, &mut *output) else {
        return;
    };
    for (item, out) in items.iter().zip(out.iter_mut()) {
        let lacks = |v: &Value| !v.get("id").is_some_and(Value::is_string);
        if lacks(item) {
            out["id"] = GENERATED.into();
        }
        if let (Some(Value::Array(projects)), Some(Value::Array(out_projects))) =
            (item.get("projects"), out.get_mut("projects"))
        {
            for (project, out_project) in projects.iter().zip(out_projects.iter_mut()) {
                if lacks(project) {
                    out_project["id"] = GENERATED.into();
                }
            }
        }
    }
}

fn check(sub: &str, name: &str, input: &Value, actual: Value) {
    let mut actual = actual;
    let mut expected = read(&root().join("esperado").join(sub).join(name));
    mask_generated_ids(input, &mut actual);
    mask_generated_ids(input, &mut expected);
    assert_eq!(
        canonical(actual),
        canonical(expected),
        "{sub}/{name}: o Rust não gravou o que o Swift grava"
    );
}

#[test]
fn bancadas_do_arquivo_atual_e_dos_antigos() {
    let missing = Path::new("/nao-existe/workbenches.json");
    for (name, file) in cases("workbenches") {
        let mut list = workbenches::load(&file, missing).workbenches;
        assign_missing_colors(&mut list);
        let actual = written("workbenches", &name, &list);
        check("workbenches", &name, &read(&file), actual);
    }
}

#[test]
fn sessions_json_antigo_so_quando_o_novo_nunca_existiu() {
    let missing = Path::new("/nao-existe/workbenches.json");
    for (name, file) in cases("sessions") {
        let mut list = workbenches::load(missing, &file).workbenches;
        assign_missing_colors(&mut list);
        let actual = written("workbenches", &format!("sessions-{name}"), &list);
        check("sessions", &name, &read(&file), actual);
    }
}

#[test]
fn workspaces_e_projetos() {
    for (name, file) in cases("workspaces") {
        let list = workspaces::load(&file)
            .map(|l| l.workspaces)
            .unwrap_or_default();
        let actual = written("workspaces", &name, &list);
        check("workspaces", &name, &read(&file), actual);
    }
}

#[test]
fn componentes_de_antes_e_depois_da_adr_057() {
    for (name, file) in cases("components") {
        let actual = written("components", &name, &components::load(&file));
        check("components", &name, &read(&file), actual);
    }
}

#[test]
fn templates_de_bancada() {
    for (name, file) in cases("templates") {
        let actual = written("templates", &name, &workbenches::load_templates(&file));
        check("templates", &name, &read(&file), actual);
    }
}

/// `clock.json`: a data é o `Date` do Swift (segundos desde 2001), e arquivo
/// sem as três fases, ou com data de outro tipo, vira cronômetro zerado.
#[test]
fn cronometros_com_a_data_do_swift() {
    for (name, file) in cases("clocks") {
        let bytes = std::fs::read(&file).unwrap();
        let clock: WorkbenchClock = super::parse(&bytes).unwrap_or_default();
        let actual = written("clocks", &name, &clock);
        check("clocks", &name, &Value::Null, actual);
    }
}

/// Gravar o que se leu e ler de novo não muda nada: a segunda gravação sai
/// igual à primeira, sem perda a cada ida e volta.
#[test]
fn gravar_e_reler_e_estavel() {
    let missing = Path::new("/nao-existe/workbenches.json");
    for (name, file) in cases("workbenches") {
        let first = workbenches::load(&file, missing).workbenches;
        let dir = tempfile::tempdir().unwrap();
        let again = dir.path().join("workbenches.json");
        workbenches::save(&again, &first).unwrap();
        let second = workbenches::load(&again, missing);
        assert_eq!(second.workbenches, first, "{name}");
        assert!(
            !second.needs_save,
            "{name}: tudo o que precisava foi gravado"
        );
    }
    for (name, file) in cases("workspaces") {
        let first = workspaces::load(&file)
            .map(|l| l.workspaces)
            .unwrap_or_default();
        let dir = tempfile::tempdir().unwrap();
        let again = dir.path().join("workspaces.json");
        workspaces::save(&again, &first).unwrap();
        let second = workspaces::load(&again).unwrap();
        assert_eq!(second.workspaces, first, "{name}");
        assert!(!second.needs_save, "{name}");
    }
}
