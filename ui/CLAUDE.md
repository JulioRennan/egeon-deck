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

## Regras que mais pegam

- **Sem gerador de código.** Nada de `freezed`, `json_serializable`,
  `build_runner`. Entities têm `fromMap` e `toMap` à mão; estado com Cubit.
- **A UI não guarda regra de negócio.** Quem decide é o core Rust. Fica aqui só
  estado passageiro de tela.
- **Nenhuma feature importa lib externa direto.** Lib de UI ganha wrap em
  `commons/widgets`; as demais, em `core/adapters`.
- **Um cliente de socket só**, em `core/adapters`. Nenhuma feature abre conexão.
- **O cubit é dono da assinatura:** abre ao nascer, cancela no `close()`.
- **Um cubit por item** (card, linha da barra lateral), não um por tela.
- **Page só compõe widgets.** Widget reutilizado por outra feature vai para
  `commons/widgets`.
- O visual (tema, design system) ainda não foi discutido; o pacote de Material
  não está no `pubspec.yaml`.

## Identificador

O app usa `dev.duckcoder.egeondeck.next` e se chama "EgeonDeck Next" até o
corte, para não se confundir com o Egeon estável em uso na máquina.
