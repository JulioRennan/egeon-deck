---
name: estrutura-flutter
description: A estrutura do front Flutter do Egeon Deck (pasta ui/) — features, core, commons e theme, o papel de cubit, page, widgets, entities, repository e usecase, a lista de features e como os eventos do core Rust chegam à tela. Consultar SEMPRE antes de criar arquivo, widget, cubit ou dependência em ui/.
---

# Estrutura do front Flutter do Egeon Deck

Decidido em `docs/migracao/3-proposta.html`, seção "Estrutura da UI". Esta skill
é o resumo operacional; em caso de dúvida, a proposta manda.

"Core do front" é a pasta `ui/lib/core`. "Core Rust" é o crate `egeon-core`.
Nunca dizer só "core".

## Pastas

```
ui/lib/
├─ features/
│  └─ <feature>/
│     ├─ presentation/
│     │  ├─ cubit/        orquestra o estado da tela pelo retorno do usecase
│     │  ├─ page/         só compõe widgets; quase nada solto
│     │  └─ widgets/      os componentes da página
│     └─ domain/
│        ├─ entities/     os modelos, com fromMap e toMap
│        ├─ repository/   faz as consultas pelo socket
│        └─ usecase/      consulta os repositories para montar algo da tela
├─ core/
│  ├─ adapters/           wrap de toda lib externa — menos as de UI
│  ├─ domain/             mesma estrutura do domain, para o que é de mais de um módulo
│  └─ cubits/             cubits globais (raro — costuma bastar o AppCubit na raiz)
├─ commons/
│  ├─ widgets/            widgets compartilhados — design system e adaptação de lib de UI
│  ├─ utils/              utilitários básicos
│  └─ forms/              validators e máscaras
└─ theme/                 cores, temas, decorations, fontes
```

## Features

```
features/
├─ home/        a casca — compõe sidebar, abas e conteúdo; alterna canvas e chat
├─ sidebar/     árvore workspace → projeto → bancada, aba Ativas, arrasto, gaveta
├─ tabs/        faixa de abas
├─ workspace/   formulários de workspace, projeto e multi-projeto
├─ workbench/   formulário da bancada, worktree, cor, relógio, limpar e remover
├─ canvas/      grid, zoom e pan, cards posicionados, arestas, ferramentas
├─ chat/        thread, composer, participantes, bandeja de permissão
├─ node/        grupo
│  ├─ card/       moldura do card
│  ├─ terminal/   widget que pinta as linhas e captura teclado
│  ├─ agent/      modelo, esforço, contexto, formulário do agente
│  ├─ web/        nó web
│  └─ queue/      fila de prompts
├─ usage/       consumo e custo
├─ processes/   janela Processos
└─ update/      aviso e menu de atualização
```

- Cada coisa é um módulo. Features planas por padrão; agrupar dentro de uma
  maior só quando fizer sentido (como `node/`).
- A `home` é a feature que compõe as outras.
- As pastas internas de uma feature nascem quando ela for implementada.

## Papel de cada peça

| Peça | Faz | Não faz |
|---|---|---|
| page | Compõe os widgets da feature | Lógica; widget solto |
| widgets | Componentes daquela página | O reutilizado vai para `commons/widgets` |
| cubit | Orquestra o estado pelo retorno do usecase; é dono das assinaturas de stream | Falar com o socket |
| usecase | Consulta repositories, combina e monta o que a tela precisa | — |
| repository | Consulta o socket — `Future` para consulta e comando, `Stream` para evento | — |
| entities | Modelos com `fromMap` e `toMap` escritos à mão | — |

## Regras

1. **Sem gerador de código.** Nada de `freezed`, `json_serializable`,
   `build_runner` e afins. Estado com Cubit (`flutter_bloc`).
2. **A UI não guarda regra de negócio.** Quem decide é o core Rust; a UI
   pergunta, mostra e captura gesto. Fica na UI só estado passageiro de tela
   (passo aberto, foco, ferramenta armada, zoom e pan, geometria das arestas).
3. **Um cliente de socket só**, em `core/adapters`, criado na raiz e entregue
   aos repositories. Nenhuma feature abre conexão.
4. **Lib externa nunca é importada direto por uma feature.** As de UI ganham
   wrap em `commons/widgets`; as demais, em `core/adapters`.
5. **Parte nativa** — nó web (`WKWebView`) em `commons/widgets`; janela, menus
   e drop de arquivo em `core/adapters`.
6. **O cubit abre a assinatura ao nascer e cancela no `close()`.** O core Rust
   manda o estado inteiro do item a cada mudança; a UI não aplica diferença.
7. **Um cubit por item** (card de nó, linha da barra lateral), não um por tela.
8. **Exceções de volume** — no terminal o widget escuta o stream das linhas
   direto; no chat o core manda a diferença de blocos.
9. **Onde se clica, o ponteiro diz** — mão em tudo que responde a clique.

## Ferramentas

O projeto fixa a versão do Flutter em `ui/.fvmrc`. Usar sempre `fvm flutter` e
`fvm dart`, nunca os do PATH.

```
cd ui && fvm flutter analyze && fvm flutter test
```
