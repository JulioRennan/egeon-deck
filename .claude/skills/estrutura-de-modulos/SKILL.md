---
name: estrutura-de-modulos
description: Onde colocar código novo no Egeon Deck e em qual módulo ele vive. Use ao criar arquivo ou tipo novo, ao decidir entre Core, Runtime, Common, Nodes ou feature, ao mover código entre arquivos, ao adicionar target no Package.swift, ou quando um import parecer errado. Também traz as leis de dependência e o que NÃO fazer.
---

# Onde este código vai

## Antes de tudo: confira o estado

```bash
ls app/Sources/
```

**Se aparecer `EgeonDeck/` e mais nada, a migração NÃO começou.** Todo arquivo novo vai
em `app/Sources/EgeonDeck/`, plano, um arquivo por conceito. Não crie pasta nem target
"adiantando" — pasta sem target não é fronteira no Swift, e pasta vazia é a convenção
que este projeto não sustenta.

O que segue é o **destino**, e vale integralmente depois do passo 1 da migração. Antes
dela, use como critério de *coesão*: o arquivo novo pertence conceitualmente a qual
caixa? Nomeie e comente pensando nisso.

Razão completa em [docs/04-modulos.md](../../../docs/04-modulos.md).

## A decisão, em ordem

Responda de cima para baixo e pare na primeira que der sim.

| pergunta | vai para |
|---|---|
| lança processo, abre pty, ou serve socket? | **`EgeonRuntime`** |
| é tipo de dado, persistência, ou parsing? | **`EgeonCore`** |
| é `Log`, `Flavor` ou `Environment`? | **`EgeonKit`** |
| é cor, fonte, medida, ou peça de UI reusada por mais de uma feature? | **`EgeonCommon`** |
| é `NodeView` ou subclasse dele — terminal, editor, web? | **`EgeonNodes`** |
| compõe features, é menu, ou é a casca da janela? | **`EgeonApp`** |
| nada acima | a **feature** dona do assunto |

Features: `EgeonChat` · `EgeonCanvas` · `EgeonMosaic` · `EgeonDialogs`.

## As leis

1. **feature não conhece feature** — precisa de algo de outra? sobe para `Core` ou
   `Common`, ou o `EgeonApp` faz a ponte.
2. **`EgeonCore` não importa AppKit nem SwiftUI.** Nunca. Se um tipo de modelo precisa
   devolver cor ou rótulo, o valor cru fica no Core e a materialização vai para
   `Common`.
3. **`EgeonCore` compila para iOS.** Se o que você escreveu usa `Process`, pty ou
   socket servidor, **não é Core** — é `Runtime`.
4. **`EgeonCommon` não conhece domínio.** Ele não importa `Core`.
5. **`EgeonNodes` é camada, não feature.** Canvas, Mosaico e a casca dependem dela; ela
   não depende de nenhuma delas.

O compilador cobra 1, 2, 4 e 5. A 3 é cobrada pelo CI.

## Dentro de uma feature

`Model/` · `Data/` · `ViewModel/` · `View/` — **nenhuma é obrigatória.**

- **`Data/`** só onde há fonte de dado externa. Hoje só o `EgeonChat` tem (`ChatAdapter`).
- **`ViewModel/`** só onde há transformação entre modelo e tela. `EgeonCanvas` e
  `EgeonNodes` **não têm**, e é decisão registrada: posição, zoom e arestas são estado,
  mas esse estado **é modelo** — vive no `WorkbenchConfig` e a view o muta direto. Não
  "corrija" essa assimetria.

Pasta nasce quando o **segundo** arquivo precisa dela.

## Módulo novo

Só com **fronteira verificável**: o compilador recusa o import errado, ou o CI recusa o
build. Sem isso é pasta, e pasta vai dentro de um target existente.

Nome sempre com prefixo `Egeon`. Não é estética: módulo com o mesmo nome de um tipo
interno cria colisão de lookup qualificado em Swift — `Canvas.Canvas` é poço sem
contorno bom.

## O que não fazer

- criar pasta ou target "para o futuro"
- pôr `Process`, pty ou socket no `EgeonCore`
- fazer tipo de modelo devolver `NSColor` ou string com spinner dentro
- importar uma feature de dentro de outra
- adicionar `ViewModel/` onde não há transformação
- deixar o `Dispatcher` conhecer `MBTerminalView` — ele fala por `TerminalSurface`
