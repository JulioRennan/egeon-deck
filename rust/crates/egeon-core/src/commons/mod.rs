//! O que as features dividem: caminhos, flavor, utilitários.

pub mod clock;
pub mod ids;
pub mod log;
pub mod paths;

/// Ler e gravar JSON como o Swift (`parse`, `write_pretty`, `read_bytes`). O
/// código mora em `features::json_file`, onde as features de organização já o
/// usam; este é o caminho que o resto do core deve citar.
pub use crate::features::json_file;
