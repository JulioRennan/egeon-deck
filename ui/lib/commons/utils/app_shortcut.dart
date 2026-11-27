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
/// Shift: só um dos dois é tecla de programa.
bool isAppModifierPressed(HardwareKeyboard keyboard) => usesCommandKey
    ? keyboard.isMetaPressed
    : keyboard.isControlPressed && keyboard.isShiftPressed;

/// O atalho de [key] com o modificador do app. [shift] e [alt] valem só no
/// macOS (⇧⌘T, ⌥⌘P): fora dele o Shift já faz parte do modificador e o Alt
/// fica de fora, por causa do AltGr — quem tinha ⌥ ganha outra tecla ou fica
/// sem atalho, e o menu ☰ cobre.
SingleActivator appActivator(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool alt = false,
}) => usesCommandKey
    ? SingleActivator(key, meta: true, shift: shift, alt: alt)
    : SingleActivator(key, control: true, shift: true);

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
