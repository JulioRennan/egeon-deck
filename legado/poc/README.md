# mega-brain — PoC 01: workspace com VSCode real + N terminais

Prova de que dá pra ter, num comando só, o **VSCode.app de verdade** (com todas as
suas extensões, Copilot, debugger, marketplace da Microsoft — nada de code-server)
lado a lado com vários terminais tilados na tela.

## Uso

```bash
./mb ls              # lista workspaces
./mb up deck        # sobe tmux + VSCode + Terminals e posiciona tudo
./mb layout deck    # só reposiciona (útil ao trocar de monitor)
./mb down deck      # mata sessões tmux e fecha as janelas de terminal
```

## Como funciona

```
workspaces/deck.json     config: path, display, frações de tela por janela
mb                        CLI
lib/screen.js             visibleFrame do display (JXA/NSScreen)
lib/place.js              posiciona janela via Accessibility API (usado no VSCode)
.state/deck.json         window ids do Terminal.app (gerado, não versionar)
```

Três decisões que fazem isso funcionar:

1. **tmux com sessões agrupadas.** A sessão base `mb-deck` guarda as janelas.
   Cada Terminal na tela attacha numa sessão agrupada (`mb-deck__back`), que
   compartilha as janelas mas tem janela ativa própria. Sem isso os dois Terminals
   ficariam espelhados mostrando o mesmo conteúdo.

2. **Terminal.app é posicionado por `window id`, não por título.** `do script`
   sobrescreve o `custom title` com o texto do próprio comando, então título é
   âncora instável. O id volta na criação e é guardado em `.state/`.

3. **VSCode não tem AppleScript**, então vai pela Accessibility API (System Events),
   casando pelo título da janela (contém o nome da pasta).

Coordenadas: `NSScreen.visibleFrame` já desconta barra de menu e Dock. Convertemos
de origem inferior-esquerda (AppKit) para superior-esquerda, que é o espaço usado
tanto pela AX API quanto pelo `bounds` do Terminal.

## Permissões macOS

Na primeira execução o macOS pede — precisa conceder ao app que roda o `mb`
(Terminal.app, iTerm, Claude Code…):

- **Privacidade e Segurança → Acessibilidade** (mover a janela do VSCode)
- **Privacidade e Segurança → Automação** → permitir controlar `Terminal` e `System Events`

## Limitações conhecidas

- Se houver duas janelas do VSCode com o nome da pasta no título, ele pega a primeira.
  Ajuste `editor.titleMatch` no JSON.
- Janela do VSCode é top-level de verdade: não fica "dentro" de nada, só é posicionada.
  Reparenting não existe no macOS.
- `mb down` não fecha o VSCode de propósito (evita perder trabalho não salvo).
- Mudou de monitor ou de resolução: rode `mb layout <ws>` de novo.
- Terminal.app é o emulador usado. Trocar por iTerm/Ghostty exige adaptar
  `terminal_open` / `terminal_place`.

## Próximo passo

O dispatcher de spec: renderizar um `.md`, e clique numa linha dispara
`tmux send-keys -t mb-deck:claude` com o prompt. As sessões já estão nomeadas
e endereçáveis — a peça que falta é só a UI.
