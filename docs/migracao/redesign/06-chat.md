# 06 · chat — conversa, passos, permissão e composer

> Módulo: `ui/lib/features/chat` (hoje `chat_thread_view`, `chat_block_view`,
> `chat_bubble`, `md_text`, `chat_composer`, `completion_menu`,
> `participants_column`, `permission_tray`, `chat_palette`, `chat_scroll`).
> Cubits de conversa, composer e fila ficam; widgets saem. Referência: v3
> **Chat · permissão acima do composer**, **Chat · passos expandidos**,
> **Canvas · composer com rascunho**
> (tela `V3-chat-permissao` do canvas da v3) e os
> componentes do DS `Message`, `Step`/`StepGroup`, `Participant`, `Composer`
> (index.d.ts e bundle.css do DS publicado).

Pré-requisitos: E1, E2 (camadas fixas: composer embaixo, permissão acima dele).

## T1 · Coluna de participantes

- **O quê:** título "Participantes"; por agente: nome na cor, endereço
  `bancada/id` em mono, estado (trabalhando / precisa de você / concluído /
  parado) com `StatusDot`; a fila de prompts como participante ("deck/fila →
  revisor · 2 de 4"). `Participant` do DS.

## T2 · Mensagens

- **O quê:** separador de dia ("Hoje"); mensagem do usuário (bolha `carbon`,
  "você · 22:40"); mensagem do agente com nome na cor, "modelo · hora · custo"
  (custo e hora no hover, DS princípio 2); citação de outro agente
  ("maestro → revisor: …"); markdown com código inline. `Message` do DS.

## T3 · Passos do agente

- **O quê:** grupo recolhido "3 passos · leu docs/redesign, criou deck/revisor,
  ligou a fila" que expande em passos: comando (`$ ls …` com contagem), criar
  nó, aresta; saída de teste com "Concluído · 23 testes ok". `Step`/`StepGroup`.

## T4 · Diff na conversa

- **O quê:** `DiffView` lado a lado com cabeçalho "arquivo +42 −18 · lado a
  lado", números de linha e realce de palavra (`diff-*`).

## T5 · Pedido de permissão acima do composer

- **O quê:** faixa "revisor quer editar lib/canvas/toolbar.dart" com
  **Permitir · Sempre · Negar** (texto fixo do DS), em `attention`, acima do
  composer; some ao responder.

## T6 · Composer (chat e canvas)

- **O quê:** campo "Peça algo ao time… / para comandos, @ para mencionar";
  anexar, comandos (/), mencionar (@); destinatário "Para <agente> · modelo ·
  esforço" (Tab troca); enviar (↵), desabilitado sem texto. O mesmo composer
  aparece embaixo do canvas (v3 "composer com rascunho"). `Composer` do DS;
  menus `/`, `@` e destinatário com `Menu`.

## T7 · Rolagem e estado vazio

- **O quê:** rolagem que segue o fim, botão de voltar ao fim; estado vazio com
  `display` (DS: só em estados vazios).

## Some daqui

Os widgets atuais de `features/chat/presentation/widgets`.
