# Design system no Flutter — plano

> Rascunho para planejar. Nada aqui está decidido até passar pelo Julio e entrar
> em `3-proposta.html`.

## Contexto

A UI de `ui/` é provisória e será apagada. O rebranding parte do zero: nenhum
componente nem tema atual é reaproveitado. Esta etapa cobre **só a fundação** —
tokens, cores e tipografia. Componentes e telas vêm depois, a partir do canvas.

| Fonte | Link |
|---|---|
| Design system "Egeon" (Graphite) | https://claude.ai/artifact/VmvSv7Rk96jTJJEFMiijH2 |
| Canvas de implementação | https://claude.ai/artifact/Q5FupA96prhWvMX4LQmSc7 |

O canvas usa o mesmo design system: o `tokens.json` instalado nele é idêntico
ao publicado (mesmo sha256 `67d99f33…`).

## O que o design system entrega

| Família | Qtd | Conteúdo |
|---|---|---|
| Cores | 88 | superfícies (`obsidian` `graphite` `carbon` `steel` `steel-active`), fios, texto, acento e primário, estados do agente, 12 identidades, diff, sintaxe, terminal ANSI, `scrim`, `edge` |
| Tipografia | 10 | interface: `display` `title` `heading` `body` `label` `small` `caption` · código: `terminal` `code` `mono-meta` |
| Espaço | 11 | grade de 4px, `space-0.5` a `space-16` |
| Raio | 6 | 4 · 6 · 8 · 12 · 14 · redondo |
| Sombra | 5 | `none` `raised` `float` `modal` `drag` |
| Borda | 3 | `hairline` 1 · `state` 1.5 · `focus` 2 |
| Tamanho | 10 | controles 30/36/42, linha 32, aba 40, barra de título 44, ícone 16/14, dot 8, barra lateral 264 |
| Opacidade | 3 | `disabled` `hover-reveal` `muted` |
| Movimento | 5 + 3 | 80 · 140 · 200 · 1600 (atenção) · 900 (spin) ms; curvas `standard` `exit` `pulse` |

Além dos tokens: `flutter/egeon_theme.dart` (tema pronto, `context.eg`),
`flutter/egeon_terminal_theme.dart` (paleta para o pacote `xterm`) e
`flutter/README.md` (como cada estado vira widget, janela, atalhos).

## Material em mãos

| Item | Onde | Situação |
|---|---|---|
| Tema Dart gerado | scratchpad da sessão | usável; será dividido por arquivo |
| Paleta do terminal | scratchpad | só as cores — o arquivo importa `xterm`, mas o terminal é libghostty no Rust |
| `tokens.json` | scratchpad | fonte de verdade; vira fixture do teste de paridade |
| Noto Sans (variável `wght`+`wdth`, normal e itálico) | `~/Downloads/egeon-fonts/noto/` | ok — 3.094 caracteres, OFL |
| JetBrains Mono (variável `wght`, normal e itálico) | `~/Downloads/egeon-fonts/jetbrains/` | ok — 976 caracteres, OFL |
| Ícone do app 256×256 | scratchpad | serve na barra lateral e no "Sobre"; pequeno para `.icns` |
| Fontes `.woff2` do design system | — | descartadas: subconjunto web (~230 caracteres) e o Flutter não lê woff2 |

### Lacunas de glifo

- **JetBrains Mono** não tem braille (`⠋`) — spinner do Claude Code e de outros CLIs.
- **Noto Sans** não tem setas nem `⌘⌥` — dicas de atalho. No macOS cai na fonte
  do sistema; no Linux e no Windows não é garantido.
- Segue o fallback do DS (fontes do sistema); ver lacuna 6 abaixo.

## Regra: segue o design system

O que o DS define é seguido como está. Ícones: `lucide_icons` com traço 1.5
(como manda o README de `Icon`). Fallback de fonte: o do `tokens.json`
(`-apple-system`, `SF Pro Text`, `system-ui` / `SF Mono`, `Menlo`).

Conferência `tokens.json` × `egeon_theme.dart`: as 88 cores batem uma a uma;
espaço, raio, tamanho, borda, opacidade, duração e curva também.

## Lacunas do próprio design system

> Corrigidas no DS em 2026-11-19 (versão 19): 1 a 7. A 8 depende do ícone em
> 1024. O DS agora traz as `.ttf` completas e os itálicos em `fonts/`.

| # | Lacuna | Encaminhamento |
|---|---|---|
| 1 | Nome "Egeon": o README diz Noto Sans 600, o README de Logos diz Geist 600 | corrigir no DS; até lá, Noto Sans 600 (o README principal e o `tokens.json` só trazem Noto) |
| 2 | Fontes do DS são `.woff2` cortadas (~230 caracteres); Flutter não lê woff2 | usar as `.ttf` completas do Google Fonts, mesma família e eixos; atualizar o DS |
| 3 | O DS só declara estilo normal, mas `syn-comment` é itálico | embutir os itálicos baixados (sem eles o Flutter inclina a normal) |
| 4 | `shadow-float` e `shadow-modal` têm um anel `0 0 0 1px #2A3036` no `tokens.json`; o Dart gerado não tem | acrescentar o segundo `BoxShadow` (spread 1) |
| 5 | `shadow-drag` existe no `tokens.json`, falta no Dart gerado | acrescentar em `EgeonShadow` |
| 6 | O fallback do `tokens.json` não chega ao Dart (`fontFamilyFallback` ausente) e só nomeia fontes Apple | aplicar o fallback do DS; Linux/Windows e braille/`⌘⌥` ficam sem fonte garantida — decidir no porte para Linux |
| 7 | `egeon_terminal_theme.dart` é para o pacote `xterm`; o terminal do app é libghostty no Rust | usar só as cores |
| 8 | Ícone do app só em 256×256 | o Julio fornece 1024×1024 para `.icns` e Linux/Windows |

Como manter o Dart igual ao `tokens.json` sem gerador de código: Dart escrito à
mão + teste de paridade (abaixo).

## Plano

1. **Proposta.** Registrar em `3-proposta.html`: `ui/lib/theme/` atual sai
   inteiro e entra o tema Graphite; fontes embutidas; ícones; fallback.
2. **Fontes.** `.ttf` + `OFL.txt` em `ui/assets/fonts/`; declarar `Noto Sans` e
   `JetBrains Mono` (e o fallback) no `pubspec.yaml`. Sem `google_fonts`: o app
   abre offline.
3. **Tema** em `ui/lib/theme/`, dividido do arquivo gerado:
   - `egeon_colors.dart` — `ThemeExtension` + `context.eg`
   - `egeon_tokens.dart` — espaço, raio, tamanho, borda, opacidade, movimento, sombra
   - `egeon_type.dart` — os 10 estilos; mono com algarismos tabulares
   - `egeon_theme.dart` — `ThemeData` escuro, sem ripple, densidade de desktop
   - `terminal_palette.dart` — só as cores ANSI, no formato que o terminal Rust consome
4. **Teste de paridade.** `tokens.json` como fixture; o teste confere cada cor,
   medida, duração e estilo de texto contra as constantes. Mudou o design
   system, o teste aponta a diferença.
5. **Amostra em modo dev.** Uma página com as superfícies, textos, estados,
   identidades, escala tipográfica e glifos de risco (braille, caixa, `⌘⌥`),
   para conferir lado a lado com o design system.
6. **Limpeza.** Apagar `app_colors`, `app_theme`, `code_palette`,
   `workbench_palette` e os usos (73 arquivos importam `theme/`). As telas
   antigas podem ficar sem cor até a etapa de componentes.
7. **Verificação.** `fvm flutter analyze && fvm flutter test`, e a página de
   amostra aberta no app em modo dev.

## Vidro (decidido em 2026-11-19)

O vidro do canvas entrou no DS (versão 21): `glass` (obsidian 62%),
`glass-border`, `glass-highlight`, `shadow-glass` e `blur-glass` (20px,
saturação 130%). No Flutter, `EgeonGlass` + `EgeonShadow.glass`. Só no que
flutua (barra de ações, painel de consumo, menus, popovers); o resto é sólido.

## Aviso do Flutter 3.50

`package:flutter/material.dart` está descontinuado desde a 3.47 em favor de
`package:material_ui/material_ui.dart`. O tema do DS ainda importa o antigo
(compila, com aviso). Decidir na fase 0 qual importar.

## Regras que viram skill

Do `flutter/README.md` do design system, para entrar em `estrutura-flutter`:

- Sem ripple; controles são widgets próprios, não `ElevatedButton` estilizado.
- Uma borda por elemento: estado recolore a borda existente, nunca empilha outra.
- Hover: `MouseRegion` + `AnimatedContainer` (80 ms). Foco: `FocusableActionDetector`, borda 2px `accent` colada.
- Pulso de atenção: `BoxShadow` de 0 a 8px, `attentionSoft` → transparente, 1600 ms.
- Movimento reduzido: `MediaQuery.disableAnimationsOf` corta transições.
- Vidro (`EgeonGlass`, `BackdropFilter`) só no que flutua: barra de ações, painel de consumo, menus, popovers.
- `graphite` sem sombra; `raised` em `carbon` fixo, `float` no que flutua, `modal` em diálogo.

## Fora desta etapa

Componentes (botão, campo, item da barra lateral, StatusDot…), telas do canvas,
janela sem barra de título, atalhos, ícone do app.
