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
│     │  ├─ cubit/        orquestra o estado da tela pelo retorno do usecase;
│     │  │                o estado é <x>_state.dart, part of do cubit
│     │  ├─ page/         só compõe widgets; quase nada solto
│     │  └─ widgets/      os componentes da página
│     ├─ di/
│     │  └─ <feature>_injection.dart   a DI do módulo: repositórios e domínio
│     └─ domain/
│        ├─ entities/     o que vem do core Rust, com fromMap e toMap
│        ├─ errors/       <feature>_error.dart: as falhas, sealed
│        ├─ repository/   faz as consultas pelo socket
│        └─ usecase/      consulta os repositories para montar algo da tela
├─ core/
│  ├─ adapters/           wrap de toda lib externa — menos as de UI
│  ├─ di/                 injection.dart: a DI global — o core do front e a
│  │                      chamada dos módulos
│  ├─ domain/             mesma estrutura do domain, para o que é de mais de um módulo
│  └─ cubits/             cubits globais (raro — costuma bastar o AppCubit na raiz)
├─ commons/
│  ├─ widgets/            widgets compartilhados — `eg/` são os componentes do
│  │                      design system Graphite; fora dela, formulários
│  │                      (`form_dialog`, `form_kit`), `ShellLayers` e adaptações
│  ├─ utils/              utilitários básicos
│  └─ forms/              validators e máscaras
└─ theme/                 tokens do Graphite: `EgeonColors` (`context.eg`), espaço,
                          raio, tipo, movimento, vidro e `EgeonTheme`
```

## Features

```
features/
├─ home/        a casca — compõe sidebar, abas e conteúdo; alterna canvas e chat
├─ sidebar/     árvore workspace → projeto → bancada, aba Ativas, arrasto, gaveta
├─ tabs/        o estado das bancadas abertas (selecionar, fechar, reordenar); a faixa de abas saiu da casca
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
| page | Compõe os widgets; cria o cubit com `BlocProvider(create: (_) => inject<XCubit>(…))` | Lógica; widget solto; cubit em `initState`/`dispose` |
| widgets | Componentes daquela página | O reutilizado vai para `commons/widgets` |
| cubit | Orquestra o estado pelo retorno do usecase; é dono das assinaturas de stream; captura o erro tipado da feature e o põe no estado | Falar com o socket; `catch` genérico; montar texto de erro |
| state | `<x>_state.dart`, `part of '<x>_cubit.dart'`. `sealed class`: o comum na base, uma subclasse por situação | Morar em `domain/entities`; `copyWith`; flag que descreve situação |
| usecase | Consulta repositories, combina e monta o que a tela precisa; registrado no `di/` do módulo | Engolir erro: deixa passar; ser construído fora do `di/` |
| repository | Consulta o socket — `Future` para consulta e comando, `Stream` para evento; converte a falha do socket no erro da feature (`failingAs`) | Deixar `EgeonCommandError`/`EgeonDisconnected` sair |
| entities | O que vem do core Rust, com `fromMap` e `toMap` escritos à mão | Estado de tela |
| errors | `sealed class <F>Error`, um tipo por falha que importa à tela (`<F>Refused(message)` com o texto do core, `<F>Offline`) | Mensagem inventada pela UI |
| `di/<feature>_injection.dart` | Ao lado de `domain/` e `presentation/` (`features/node/queue/di/queue_injection.dart`): tudo dela, em duas funções — `register<F>Repositories()` (os reais de socket, a parte nativa) e `register<F>Domain()` (usecases, cubits, registros dela) | Registrar o que é de outra feature |
| `core/di/injection.dart` | O global: `registerInfrastructure` (paths, transport, cliente do socket, lançador, `OrganizationFeed`, `PathPicker` e os `…Repositories()` de cada módulo) e `registerDomain` (`ConnectionCubit` e os `…Domain()`) | Ser importado por feature |

## Regras

1. **Sem gerador de código.** Nada de `freezed`, `json_serializable`,
   `build_runner` e afins. Estado com Cubit (`flutter_bloc`).
2. **A UI não guarda regra de negócio.** Quem decide é o core Rust; a UI
   pergunta, mostra e captura gesto. Fica na UI só estado passageiro de tela
   (passo aberto, foco, ferramenta armada, zoom e pan, geometria das arestas).
3. **Um cliente de socket só**, em `core/adapters`, registrado como único no
   injector e entregue aos repositories. Nenhuma feature abre conexão.
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
10. **Injeção pelo GetIt**, atrás do wrap `core/adapters/injector.dart`
    (`inject<T>()`, `Injector.factory`/`factoryParam`/`lazySingleton`/
    `singleton`/`reset`); só ele importa `get_it`. Nada de
    `RepositoryProvider` nem `context.read` de repositório, usecase ou
    registro — `context.read<XCubit>()` só para o cubit do `BlocProvider`.
    - **Fábrica é o padrão**: repositório, usecase e cubit. O que depende da
      bancada ou do item é `factoryParam` (o id; dois ids num record
      `(workbenchId:, nodeId:)`). Usecase de bancada pede o `workbenchId`,
      como o repositório dela.
    - **Todo usecase está no injector**: a fábrica do cubit os pega com
      `inject<…>()`; nenhum usecase é construído na mão fora de `di/`.
    - **Único só com motivo**: o socket e o transport, o lançador do core, o
      `OrganizationFeed`, o repositório que guarda cache (canvas), o
      `ConnectionCubit` e os registros que a casca reparte.
    - **Por módulo**: cada feature registra o que é dela no seu
      `di/<feature>_injection.dart`; o global em `core/di/` só chama.
    - **Teste** chama só `registerDomain` e registra os falsos
      (`test/support/inject_fakes.dart`), com `reset` no fim.
11. **Estado é do cubit, não do domínio, e é derivado.** Fica em
    `<x>_state.dart`, `part of` do cubit (o cubit tem
    `part '<x>_state.dart';`). Entidade é só o que vem do core Rust.
    - **Sem `copyWith`.** Cada `emit` é um estado nomeado que diz o que está
      acontecendo (`CanvasPanning`, `ProcessesSelecting`), não a cópia do
      anterior com um campo trocado.
    - O que vale em qualquer situação fica na base `sealed` (no canvas:
      cards, ligações, vista); flag e opcional que descrevem uma situação
      viram subclasse, com só os campos dela. O widget faz `switch`
      exaustivo.
    - Duas coisas que variam independentes (a ferramenta armada e o que a mão
      faz; a interação e o movimento) não viram combinações: **divida o cubit
      por assunto** (`CanvasCubit`, `CanvasToolCubit`, `CanvasMotionCubit`).
    - Comando de uma vez (rolar até o fim, rascunho vindo de fora) é stream
      de evento do cubit, não campo do estado.
12. **Erro tipado por feature.** `domain/errors/<feature>_error.dart` (sealed).
    O repositório converte a falha do socket com
    `.failingAs(refused: <F>Refused.new, offline: <F>Offline.new)`; o texto do
    core vai dentro e a UI não inventa mensagem (decisão 33.3). O usecase deixa
    passar; o cubit captura `on <F>Error` e o põe no estado (ou ignora, quando o
    próximo estado do core corrige a tela). Nada de `on Object` virando
    `String`.
13. **Visual só pelo design system.** Nenhum hex, tamanho ou fonte solto fora
    de `theme/`: tudo vem de `context.eg` e dos tokens (`EgeonSpace`,
    `EgeonRadius`, `EgeonType`). Tela nova monta com os componentes de
    `commons/widgets/eg/` (Button, Dialog, TextField, Select, Menu, Toast,
    NoticeBanner, StatusDot…); não se redesenha botão, campo, menu nem
    diálogo. Formulário em janela usa `form_dialog.dart` + `form_kit.dart`.
    O que flutua sobre a bancada (consumo, permissão, composer) entra na
    `ShellLayers`. Estado é cor **e** forma (`StatusDot`); identidade é o nome
    na cor (`AgentName`), nunca dot redondo; vidro só em peça flutuante.

## Ferramentas

O projeto fixa a versão do Flutter em `ui/.fvmrc`. Usar sempre `fvm flutter` e
`fvm dart`, nunca os do PATH.

```
cd ui && fvm flutter analyze && fvm flutter test
```
