//! Clonar um arquivo, uma pasta ou um link para outro lugar.
//!
//! No macOS o `clonefile` do APFS clona uma árvore inteira numa chamada só — um
//! `node_modules` de 54 mil itens em 1,4 s, e sem ocupar disco até um dos lados
//! escrever, contra 7,5 s do `cp -Rc` arquivo por arquivo. Onde o sistema de
//! arquivos não clona (outro volume, outro sistema), a implementação copia.

use std::io;
use std::path::Path;

pub trait FileCloner: Send + Sync {
    /// Clona `from` para `to`. `to` ainda não existe e o pai dele existe. Link
    /// simbólico é clonado como link, nunca seguido.
    fn clone_entry(&self, from: &Path, to: &Path) -> io::Result<()>;
}
