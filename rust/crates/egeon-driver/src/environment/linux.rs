use std::path::{Path, PathBuf};

/// Diretórios que instaladores usam e que o ambiente da sessão gráfica nem
/// sempre traz: o app aberto pelo menu ou pelo gerenciador de arquivos herda o
/// `PATH` do login, sem o que o `.bashrc` ou o `.zshrc` acrescentam. A ordem
/// importa: entram na frente, então o que o usuário instalou ganha da versão
/// que vem com o sistema.
pub(super) fn candidates(home: &Path) -> Vec<PathBuf> {
    vec![
        home.join(".local/bin"),
        home.join("bin"),
        home.join(".bun/bin"),
        home.join(".cargo/bin"),
        // Flutter e Dart sob fvm, e binários instalados via `dart pub global`.
        home.join("fvm/default/bin"),
        home.join(".pub-cache/bin"),
        // O `npm i -g` sem sudo, na pasta que a documentação do npm sugere.
        home.join(".npm-global/bin"),
        // adb e companhia, onde o Android Studio do Linux põe o SDK.
        home.join("Android/Sdk/platform-tools"),
        PathBuf::from("/home/linuxbrew/.linuxbrew/bin"),
        PathBuf::from("/home/linuxbrew/.linuxbrew/sbin"),
        PathBuf::from("/usr/local/bin"),
        PathBuf::from("/snap/bin"),
    ]
}
