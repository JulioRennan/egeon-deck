use std::ffi::OsStr;
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

/// O shell do usuário: o `$SHELL`, se existe e é executável; na falta, o
/// `/bin/bash`, depois o `/bin/sh`. O `$SHELL` vem do login da sessão gráfica.
pub(super) fn shell() -> PathBuf {
    resolve(std::env::var_os("SHELL").as_deref(), |path| {
        crate::is_executable(path)
    })
}

fn resolve(shell: Option<&OsStr>, executable: impl Fn(&Path) -> bool) -> PathBuf {
    let from_env = shell
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        // Relativo dependeria da pasta em que o app abriu.
        .filter(|p| p.is_absolute());
    from_env
        .into_iter()
        .chain([PathBuf::from("/bin/bash"), PathBuf::from("/bin/sh")])
        .find(|p| executable(p))
        .unwrap_or_else(|| PathBuf::from("/bin/sh"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shell_do_usuario_quando_existe_senao_bash_senao_sh() {
        let all = |_: &Path| true;
        let only = |wanted: &'static [&'static str]| {
            move |p: &Path| wanted.iter().any(|w| p == Path::new(w))
        };
        let fish = Some(OsStr::new("/usr/bin/fish"));
        assert_eq!(resolve(fish, all), PathBuf::from("/usr/bin/fish"));
        // $SHELL que não existe ou não executa: o bash.
        assert_eq!(
            resolve(fish, only(&["/bin/bash", "/bin/sh"])),
            PathBuf::from("/bin/bash")
        );
        assert_eq!(resolve(None, all), PathBuf::from("/bin/bash"));
        assert_eq!(
            resolve(Some(OsStr::new("")), all),
            PathBuf::from("/bin/bash")
        );
        assert_eq!(
            resolve(Some(OsStr::new("zsh")), all),
            PathBuf::from("/bin/bash")
        );
        // Sem bash: o sh.
        assert_eq!(resolve(None, only(&["/bin/sh"])), PathBuf::from("/bin/sh"));
        assert_eq!(resolve(None, |_: &Path| false), PathBuf::from("/bin/sh"));
    }
}
