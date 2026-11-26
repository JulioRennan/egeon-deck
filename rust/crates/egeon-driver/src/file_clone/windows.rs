//! Sem clone de árvore numa chamada só: a cópia comum do `mod.rs` faz o
//! trabalho (o block clone do ReFS não vale a complexidade aqui).

use std::io;
use std::path::Path;

pub(super) fn clone(_from: &Path, _to: &Path) -> io::Result<()> {
    Err(io::Error::from(io::ErrorKind::Unsupported))
}
