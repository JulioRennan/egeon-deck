//! Sem `clonefile`: o Linux não clona uma árvore numa chamada só, e a cópia
//! comum do `mod.rs` faz o trabalho. Ela copia cada arquivo com `io::copy`,
//! que no Linux vira `copy_file_range` — e esse já compartilha os blocos
//! (reflink) no Btrfs e no XFS, que é o que o clone do APFS dá no macOS.

use std::io;
use std::path::Path;

pub(super) fn clone(_from: &Path, _to: &Path) -> io::Result<()> {
    Err(io::Error::from(io::ErrorKind::Unsupported))
}
