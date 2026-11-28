import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// O modificador dos atalhos do app (decisão 55): ⌘ no macOS e Ctrl+Shift no
/// Windows e no Linux. Lá ⌘ é a tecla Win/Super, que o sistema toma; Ctrl puro
/// é do programa no terminal (Ctrl+C, Ctrl+K, Ctrl+W do shell e do agente) e
/// Ctrl+Alt é o AltGr de muitos teclados. Quem escreve atalho usa isto, nunca
/// `meta: true` direto.
bool get usesCommandKey =>
    debugUsesCommandKey ?? defaultTargetPlatform == TargetPlatform.macOS;

/// O teste fixa a plataforma dos atalhos: o `flutter test` roda como Android, e
/// os testes de atalho do app descrevem o macOS (a configuração em
/// `test/flutter_test_config.dart`); os de Windows e Linux a desligam.
@visibleForTesting
bool? debugUsesCommandKey;

/// O modificador do atalho do app está apertado? Fora do macOS, Ctrl **e**
/// Shift: só um dos dois é tecla de programa. Sem Alt: Ctrl+Alt é o AltGr, e
/// AltGr+Shift digita maiúscula acentuada (o Ŵ do galês, o Ć do polonês).
bool isAppModifierPressed(HardwareKeyboard keyboard) => usesCommandKey
    ? keyboard.isMetaPressed
    : keyboard.isControlPressed &&
          keyboard.isShiftPressed &&
          !keyboard.isAltPressed;

/// O atalho de [key] com o modificador do app. [shift] e [alt] valem só no
/// macOS (⇧⌘T, ⌥⌘P): fora dele o Shift já faz parte do modificador e o Alt
/// fica de fora, por causa do AltGr — quem tinha ⌥ ganha outra tecla ou fica
/// sem atalho, e o menu ☰ cobre.
///
/// [repeats] falso ignora a tecla segurada: o atalho que abre janela dispara
/// uma vez só.
SingleActivator appActivator(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool alt = false,
  bool repeats = true,
}) => usesCommandKey
    ? SingleActivator(
        key,
        meta: true,
        shift: shift,
        alt: alt,
        includeRepeats: repeats,
      )
    : SingleActivator(key, control: true, shift: true, includeRepeats: repeats);

/// O texto do atalho como a UI o mostra (`⌘K`, `⇧⌘T`; `Ctrl+Shift+K`). [key] é
/// o rótulo da tecla, como aparece. Nulo quando a plataforma não tem o atalho
/// ([macOnly]: o ⌥⌘1 do canvas, que fora do macOS não existe).
String? appShortcutLabel(
  String key, {
  bool shift = false,
  bool alt = false,
  bool macOnly = false,
}) {
  if (usesCommandKey) return '${alt ? '⌥' : ''}${shift ? '⇧' : ''}⌘$key';
  return macOnly ? null : 'Ctrl+Shift+$key';
}

/// A tecla de [key] é parte do modificador do app? Serve para o evento do
/// próprio modificador (apertar ou soltar), que não é atalho.
bool isAppModifierKey(LogicalKeyboardKey key) => usesCommandKey
    ? key == LogicalKeyboardKey.metaLeft || key == LogicalKeyboardKey.metaRight
    : key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight ||
          key == LogicalKeyboardKey.shiftLeft ||
          key == LogicalKeyboardKey.shiftRight;

/// O modificador dos gestos do mouse e do colar na fila (decisão 55): ⌘ no
/// macOS e **Ctrl** sozinho nos outros. É o modificador simples, que o Windows
/// e o Linux usam para abrir link, dar zoom na roda e colar; o do atalho do
/// app ([isAppModifierPressed]) é Ctrl+Shift e não serve a gesto. Sem Alt:
/// Ctrl+Alt é o AltGr, que digita (o `@` do húngaro é AltGr+V).
bool isPrimaryModifierPressed(HardwareKeyboard keyboard) => usesCommandKey
    ? keyboard.isMetaPressed
    : keyboard.isControlPressed && !keyboard.isAltPressed;

/// A tecla de [key] é o modificador de [isPrimaryModifierPressed]?
bool isPrimaryModifierKey(LogicalKeyboardKey key) => usesCommandKey
    ? key == LogicalKeyboardKey.metaLeft || key == LogicalKeyboardKey.metaRight
    : key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight;

/// Como o modificador simples se escreve numa dica (`⌘`, `Ctrl`).
String get primaryModifierName => usesCommandKey ? '⌘' : 'Ctrl';

/// As teclas que o app liga com Ctrl+Shift fora do macOS (as do `ShellShortcuts`).
/// Só elas ficam com o app: as demais combinações com Ctrl+Shift chegam ao
/// terminal (Ctrl+Shift+←/→ são seleção de palavra no PSReadLine; Ctrl+Shift+-
/// vira ^_). O conjunto repete as teclas do `ShellShortcuts` (o `commons` não
/// pode importar a feature): um teste confere que os dois andam juntos.
@visibleForTesting
final appCtrlShiftKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.slash,
  LogicalKeyboardKey.keyK,
  LogicalKeyboardKey.bracketLeft,
  LogicalKeyboardKey.bracketRight,
  LogicalKeyboardKey.keyW,
  LogicalKeyboardKey.keyT,
  LogicalKeyboardKey.keyP,
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
};

/// Troca de aba fora do macOS (decisão 55): Ctrl+Tab, Ctrl+Shift+Tab,
/// Ctrl+PgUp e Ctrl+PgDn. No macOS são ⌘← e ⌘→ (tratados à parte).
bool isTabSwitchKey(LogicalKeyboardKey key, HardwareKeyboard keyboard) =>
    !usesCommandKey &&
    keyboard.isControlPressed &&
    !keyboard.isAltPressed &&
    (key == LogicalKeyboardKey.tab ||
        (!keyboard.isShiftPressed &&
            (key == LogicalKeyboardKey.pageUp ||
                key == LogicalKeyboardKey.pageDown)));

/// A tecla apertada é um atalho do app e não vai ao programa do terminal? No
/// macOS qualquer ⌘+tecla; fora dele, só o que o app liga de fato.
bool isAppShortcutPressed(HardwareKeyboard keyboard, LogicalKeyboardKey key) =>
    usesCommandKey
    ? keyboard.isMetaPressed
    : (isAppModifierPressed(keyboard) && appCtrlShiftKeys.contains(key)) ||
          isTabSwitchKey(key, keyboard);

/// O texto do atalho de trocar de aba (`⌘→`, `Ctrl+Tab`), para a dica e o menu.
String get nextTabShortcutLabel => usesCommandKey ? '⌘→' : 'Ctrl+Tab';
String get previousTabShortcutLabel => usesCommandKey ? '⌘←' : 'Ctrl+Shift+Tab';
