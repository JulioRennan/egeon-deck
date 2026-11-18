use std::path::{Path, PathBuf};

/// Diretórios que instaladores usam e que o launchd não conhece. A ordem
/// importa: entram na frente, então o que o usuário instalou ganha da versão que
/// vem com o sistema.
pub(super) fn candidates(home: &Path) -> Vec<PathBuf> {
    vec![
        home.join(".local/bin"),
        home.join("bin"),
        home.join(".bun/bin"),
        home.join(".cargo/bin"),
        // Flutter e Dart sob fvm, e binários instalados via `dart pub global`.
        home.join("fvm/default/bin"),
        home.join(".pub-cache/bin"),
        // adb e companhia: a extensão Flutter lista dispositivos Android por aqui.
        home.join("Library/Android/sdk/platform-tools"),
        PathBuf::from("/opt/homebrew/bin"),
        PathBuf::from("/opt/homebrew/sbin"),
        PathBuf::from("/usr/local/bin"),
    ]
}
