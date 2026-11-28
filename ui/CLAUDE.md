# Egeon Deck — lado Flutter

A interface do app novo. A visão geral da migração está no `CLAUDE.md` da raiz.

**Antes de criar arquivo, widget, cubit ou dependência aqui, consulte a skill
`estrutura-flutter`.** Ela é o padrão a seguir; este arquivo é só o mapa.

## Pastas

```
lib/
├─ main.dart
├─ features/    um módulo por coisa da tela
│  ├─ home/ · sidebar/ · tabs/ · workspace/ · workbench/ · canvas/ · chat/
│  ├─ node/     grupo: card/ · terminal/ · agent/ · web/ · queue/
│  └─ usage/ · processes/ · update/
├─ core/        adapters/ · domain/ · cubits/
├─ commons/     widgets/ · utils/ · forms/
└─ theme/
macos/          o runner nativo
windows/        o runner Win32 (decisão 54): canal egeon/window, janela única, dark
third_party/    desktop_multi_window 0.3.1 com um ajuste no Windows (EGEON.md): GPU própria no motor da janela secundária
test/
```

Hoje é só a fundação: o app abre uma janela vazia. As pastas das features
existem, vazias; as camadas internas (`presentation/`, `domain/`) nascem quando
a feature for implementada.

## O caminho de uma ação

```
page ─▶ widgets ─▶ cubit ─▶ usecase ─▶ repository ─▶ socket ─▶ core Rust
```

"Core do front" é `lib/core`; "core Rust" é o crate `egeon-core`. Nunca dizer só
"core".

## Comandos

A versão do Flutter é fixada em `.fvmrc`. Usar sempre `fvm`, nunca o `flutter`
do PATH.

```
fvm flutter pub get
fvm flutter analyze
fvm flutter test
fvm flutter build macos --debug
```

`analyze` e `test` passam antes de todo commit.

## Desenvolvimento

Como no Swift: dois apps lado a lado (decisão 41).

| | estável | dev |
|---|---|---|
| bundle | `ui/build/EgeonDeck Next.app` | `ui/build/EgeonDeck Next Dev.app` |
| config · socket · log | `~/.egeon-next/` | `~/.egeon-next-dev/` |

- `ui/scripts/dev.sh` recompila, derruba e reabre o DEV (`dev.sh release stable`
  para o outro). `ui/scripts/make.sh [debug|release] [stable|dev]` só monta.
- Conferir pelo socket: `curl --unix-socket ~/.egeon-next-dev/sock http://eg/targets`.
- `EGEON_HOME` vence o flavor (testes e o e2e usam pasta temporária).

## Regras que mais pegam

- **Sem gerador de código.** Nada de `freezed`, `json_serializable`,
  `build_runner`. Entities têm `fromMap` e `toMap` à mão; estado com Cubit.
- **A UI não guarda regra de negócio.** Quem decide é o core Rust. Fica aqui só
  estado passageiro de tela.
- **Nenhuma feature importa lib externa direto.** Lib de UI ganha wrap em
  `commons/widgets`; as demais, em `core/adapters`.
- **Um cliente de socket só**, em `core/adapters`. Nenhuma feature abre conexão.
- **Dependências pelo injector** (`core/adapters/injector.dart`, sobre o
  GetIt), por módulo: cada feature tem `di/<feature>_injection.dart`
  (repositórios reais × domínio), e `lib/core/di/injection.dart` chama
  todos e registra o do core do front. A página cria o cubit com
  `BlocProvider(create: (_) => inject<XCubit>(…))`; nada de
  `RepositoryProvider` nem `context.read` de repositório ou usecase. Fábrica
  por padrão; único só com estado repartido. Teste: `injectFakes(…)`.
- **O cubit é dono da assinatura:** abre ao nascer, cancela no `close()`.
- **Estado é do cubit e derivado:** `<x>_state.dart` como `part of` do cubit,
  nunca em `domain/entities`. Sem `copyWith`: cada `emit` é um estado nomeado
  (`sealed`, o comum na base, uma subclasse por situação) e o widget faz
  `switch` exaustivo. O que varia independente vira outro cubit.
- **Erro tipado por feature:** `domain/errors/<feature>_error.dart` (sealed). O
  repositório converte a falha do socket (`failingAs`) com o texto do core
  dentro; o cubit captura `on <F>Error`. Nada de `catch` genérico virando
  `String`.
- **Um cubit por item** (card, linha da barra lateral), não um por tela.
- **Page só compõe widgets.** Widget reutilizado por outra feature vai para
  `commons/widgets`.
- O visual é o design system Graphite (decisão 44), em `lib/theme/`:
  `EgeonColors` (`context.eg`, os tokens de cor, com `clear` e os
  `overlay2…overlay12`), `EgeonSpace/Radius/Size/Type/Motion/Shadow`, `EgeonGlass` e
  `EgeonTheme`. **Nenhum hex fora de `theme/`**: cor, espaço, raio e fonte vêm
  dos tokens. O Material vem de `material_ui` (o `flutter/material.dart` está
  descontinuado) e só o `theme/` e a `main.dart` o importam; o resto usa
  `flutter/widgets.dart`.
- **Os componentes do DS moram em `commons/widgets/eg/`** (Button, Dialog,
  TextField, Select, Checkbox, Toggle, Menu, Popover, Tooltip, Toast,
  NoticeBanner, StatusDot, Spinner, SegmentedControl, GlassSurface…), um
  arquivo por componente do DS publicado (`design/README.md`). Tela nova monta com eles; não
  se desenha de novo botão, campo, menu ou diálogo. Estado = cor **e** forma
  (`StatusDot`), identidade = nome na cor (`AgentName`), nunca dot redondo.
- Formulário em janela usa `commons/widgets/form_dialog.dart`
  (`showFormDialog`, `FormDialogBody`, `confirmDialog`…, sobre o `Dialog` do DS:
  largura 440, Cancelar ghost, destrutivo com a lixeira) e `form_kit.dart`
  (campos, rádio, caixa, lista).
- **`ShellLayers`** (`commons/widgets/shell_layers.dart`) empilha o que flutua
  sobre a área da bancada — chip de consumo, permissões e composer — com a
  margem do DS (4 no topo e nas laterais, 20 no pé) e informa ao `Toast` o quanto
  do pé já está ocupado. Camada flutuante nova entra nela, não num `Positioned`
  solto.
- Vidro (`GlassSurface`) só em peça que flutua; superfície fixa é sólida
  (`carbon`, `graphite`). Onde se clica, `Pressable`/mão (ADR-048).

## Identificador

O app usa `dev.duckcoder.egeondeck.next` e se chama "EgeonDeck Next" até o
corte, para não se confundir com o Egeon estável em uso na máquina.
