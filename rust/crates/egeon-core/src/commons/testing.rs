//! Apoio aos testes do core.

use std::os::unix::fs::MetadataExt;

/// Root lê a pasta `0o000` e apaga dentro da `0o500`: os testes de permissão
/// não têm o que provar nele (o container de desenvolvimento roda como root).
/// O dono de um arquivo recém-criado é o uid efetivo; assim, sem `unsafe` no
/// core.
pub fn running_as_root() -> bool {
    tempfile::NamedTempFile::new()
        .ok()
        .and_then(|file| file.as_file().metadata().ok())
        .is_some_and(|meta| meta.uid() == 0)
}
