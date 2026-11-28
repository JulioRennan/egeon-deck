# Egeon Deck — repassa ao seu .zshrc e registra cada comando na trilha da
# bancada. Gerado a cada arranque; não edite.
[ -f "$HOME/.zshrc" ] && source "$HOME/.zshrc"

# O comando, não a saída: saída pode ser enorme. Em segundo plano e sem
# esperar, para não atrasar o prompt. O próprio `egeon trace` não entra —
# já está indo para a trilha.
_egeon_trace_preexec() {
    case "$1" in
      egeon\ trace*) return ;;
    esac
    command egeon trace "\$ $1" >/dev/null 2>&1 &!
}
autoload -Uz add-zsh-hook
add-zsh-hook preexec _egeon_trace_preexec

# Daqui em diante o zsh já leu o que precisava: filhos usam o seu $HOME.
unset ZDOTDIR
