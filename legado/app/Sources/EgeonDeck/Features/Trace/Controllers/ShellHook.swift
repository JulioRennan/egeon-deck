import Foundation

/// Faz o terminal comum registrar na trilha cada comando que você roda — o
/// comando, nunca a saída (ADR-036).
///
/// Um shell não tem modelo para instruir, então o registro vem do `preexec`
/// do zsh. O gancho entra por `ZDOTDIR`: o nó `shell` sobe com a variável
/// apontando para cá, e os quatro arquivos daqui só carregam os seus de
/// `$HOME` e, no `.zshrc`, acrescentam o hook. É a técnica da integração de
/// shell do VS Code — o único jeito de enfiar um `preexec` sem editar o
/// `.zshrc` de ninguém. `ZDOTDIR` é desfeito ao fim, para um `zsh` que você
/// abra à mão dentro do terminal ler o seu `$HOME` normal.
enum ShellHook {
    static var directory: URL { Flavor.current.config("zsh") }

    static func install() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, body) in files {
            do {
                try body.write(to: directory.appendingPathComponent(name), atomically: true,
                               encoding: .utf8)
            } catch {
                Log.write("zsh: não consegui escrever \(name) — \(error)")
            }
        }
    }

    /// Só os estágios que o zsh lê de `ZDOTDIR`; cada um repassa ao seu.
    private static var files: [String: String] {
        [".zshenv": forward(".zshenv"),
         ".zprofile": forward(".zprofile"),
         ".zlogin": forward(".zlogin"),
         ".zshrc": zshrc]
    }

    private static func forward(_ name: String) -> String {
        """
        # Egeon Deck — repassa ao seu \(name). Gerado a cada arranque; não edite.
        [ -f "$HOME/\(name)" ] && source "$HOME/\(name)"

        """
    }

    private static var zshrc: String {
        """
        # Egeon Deck — repassa ao seu .zshrc e registra cada comando na trilha da
        # bancada. Gerado a cada arranque; não edite.
        [ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc"

        # O comando, não a saída: saída pode ser enorme. Em segundo plano e sem
        # esperar, para não atrasar o prompt. O próprio `egeon trace` não entra —
        # já está indo para a trilha.
        _egeon_trace_preexec() {
            case "$1" in
              egeon\\ trace*) return ;;
            esac
            command egeon trace "\\$ $1" >/dev/null 2>&1 &!
        }
        autoload -Uz add-zsh-hook
        add-zsh-hook preexec _egeon_trace_preexec

        # Daqui em diante o zsh já leu o que precisava: filhos usam o seu $HOME.
        unset ZDOTDIR

        """
    }
}
