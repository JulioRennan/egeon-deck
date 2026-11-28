//! Link simbólico e bit de execução: as duas chamadas de arquivo que mudam por
//! sistema (`symlink` no Unix, outro par de chamadas no Windows; `chmod 755`).
//!
//! O core usa direto todo o resto de arquivo; só estas duas entram aqui.

use std::io;
use std::path::Path;

pub trait FileLinks: Send + Sync {
    /// Cria o link simbólico `link` apontando para `target`.
    fn symlink(&self, target: &Path, link: &Path) -> io::Result<()>;

    /// Deixa o arquivo executável pelo dono (`chmod 755`).
    fn make_executable(&self, path: &Path) -> io::Result<()>;
}
