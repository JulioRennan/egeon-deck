# design

A marca e o design system do Egeon. Aqui fica o **descritivo**: o que é, como se
usa e o porquê. A implementação mora no app (`ui/lib/theme`,
`ui/lib/commons/widgets/eg`), que segue o que está aqui.

```
design/
├─ brand/      a marca: logo, ícone do app e onde cada arquivo é usado
└─ system/     o design system Graphite
   ├─ README.md     princípios, cores, tipografia, forma, movimento, escrita
   ├─ tokens.json   os valores (cores, espaço, raio, sombra, tipo…)
   └─ demo.html     a demo do DS inteiro: fundamentos e cada componente vivo
```

`system/demo.html` abre direto no navegador a partir do repositório (as fontes
vêm de `ui/assets/fonts`; o React, do cdnjs). Os fundamentos saem do
`tokens.json` daqui; os componentes são os do DS publicado em 2026-11-23.

## Fontes

| O quê | Onde |
|---|---|
| Design system publicado | https://claude.ai/artifact/VmvSv7Rk96jTJJEFMiijH2 |
| Canvas da v3 (as telas de referência) | https://claude.ai/artifact/Q5FupA96prhWvMX4LQmSc7 |
| Fontes (Noto Sans e JetBrains Mono, OFL) | `ui/assets/fonts` |

## Mudar alguma coisa

- **Marca e ícone:** `brand/README.md`.
- **Token (cor, espaço, raio…):** muda em `system/tokens.json` e no
  `ui/lib/theme` no mesmo commit; os nomes são os mesmos, em camelCase
  (`accent-soft` → `context.eg.accentSoft`).
- **Regra do DS:** muda em `system/README.md`. Decisão nova passa pelo Julio em
  `docs/migracao/3-proposta.html` antes.
