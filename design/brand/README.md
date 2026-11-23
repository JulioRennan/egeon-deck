# Marca

## Hoje

| | |
|---|---|
| Nome | **Egeon** (o app: "Egeon Deck"), em Noto Sans 600 |
| Ícone | a mão do maestro segurando a cruzeta de marionete; dos fios pendem terminais `>_`, os agentes. Flat, monocromático, cinza-claro sobre grafite, os detalhes em espaço negativo |
| Variante dev | o mesmo desenho em branco sobre azul-aço (`#3F6D98`): distingue o app de desenvolvimento do estável no Dock |

A paleta do app vem dos tokens (`../system/tokens.json`), não do ícone: refazer o
logo não muda nenhuma cor da interface.

## Arquivos

```
logo/
├─ app-icon.png       mestre do ícone, PNG 1024 × 1024
└─ app-icon-dev.png   mestre da variante dev, PNG 1024 × 1024
export.sh             leva o mestre a todo lugar que o usa
```

O mestre é o único lugar para editar. Ao refazer o logo, guarde aqui também as
fontes vetoriais (`logo/*.svg`, o arquivo do editor) junto dos PNG.

## Onde cada arquivo é usado

| Destino | Vem de | Como |
|---|---|---|
| App novo, estável (`ui/macos/Runner/Assets.xcassets/AppIcon.appiconset`, 16 a 1024) | `app-icon.png` | `export.sh` |
| Site (`site/assets/icon.png` 1024 e `icon-256.png`) | `app-icon.png` | `export.sh` |
| App novo, dev (`AppIconDev.icns` dentro do bundle) | `app-icon-dev.png` | o `ui/scripts/make.sh` gera a cada montagem |
| App Swift (`legado/app/Resources/icon*.png`) | — | não muda: o legado fica como está até o corte |

## Trocar o logo

1. Salve os novos mestres em `logo/` (mesmos nomes, PNG 1024 × 1024). Para o
   ícone do macOS, a grade do sistema põe o quadrado arredondado em 824 × 824
   no centro, com margem transparente em volta. O ícone de hoje segue essa grade.
2. Rode `design/brand/export.sh`. `export.sh --check` só diz se algum destino
   ficou para trás.
3. `ui/scripts/dev.sh` remonta o app dev com a variante nova.
4. Entra no `CHANGELOG.md` em `[Unreleased]` (é mudança que o usuário vê).
