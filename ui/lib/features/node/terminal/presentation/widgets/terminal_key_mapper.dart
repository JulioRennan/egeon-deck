import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../../../commons/utils/app_shortcut.dart';
import '../../domain/entities/terminal_key.dart';

/// A tecla vai para o programa do terminal, ou é atalho do app?
///
/// [meta] é o modificador do app apertado (`isAppModifierPressed`): ⌘ no macOS,
/// Ctrl+Shift fora dele (decisão 55).
///
/// O atalho de trocar de aba (⌘1…⌘9, ⌘], ⌘→) chega com o terminal ainda
/// focado e não pode contar como você digitando nele — sair da bancada apagava
/// a ampulheta de quem estava na frente (ADR-063). Com ⌘ só o colar chega ao
/// pty; sem ⌘, tudo é você falando com o agente (⌃C interrompe).
bool reachesPty({required bool meta, String? character}) =>
    !meta || character?.toLowerCase() == 'v';

/// Traduz o evento de teclado do Flutter para o que a UI manda ao core.
///
/// Só as teclas especiais e as combinações com Ctrl ou Alt passam por aqui.
/// O texto digitado (letras, acentos, teclas mortas, ç) devolve `null` de
/// propósito: quem o entrega é o método de entrada do sistema, que sabe
/// compor `´` + `a` em `á`. Também devolve `null` para atalhos com ⌘ e para
/// modificador sozinho.
TerminalKey? mapTerminalKey(KeyEvent event, HardwareKeyboard keyboard) {
  if (event is KeyUpEvent) return null;
  if (!reachesPty(
    meta: isAppModifierPressed(keyboard),
    character: event.logicalKey.keyLabel,
  )) {
    return null;
  }
  if (_modifiers.contains(event.logicalKey)) return null;

  final ctrl = keyboard.isControlPressed;
  final alt = keyboard.isAltPressed;
  final shift = keyboard.isShiftPressed;

  if (event.logicalKey == LogicalKeyboardKey.space) {
    if (!ctrl && !alt) return null;
    return TerminalKey(
      key: 'space',
      text: ctrl ? null : ' ',
      ctrl: ctrl,
      alt: alt,
      shift: shift,
    );
  }

  final named = _named[event.logicalKey];
  if (named != null) {
    return TerminalKey(key: named, ctrl: ctrl, alt: alt, shift: shift);
  }

  if (!ctrl && !alt) return null;

  final label = event.logicalKey.keyLabel.toLowerCase();
  final character = event.character;
  final hasText =
      character != null && character.isNotEmpty && !_isControl(character);

  // Ctrl+letra chega sem texto imprimível: o core codifica pela tecla.
  if (hasText && !ctrl) {
    return TerminalKey(
      key: label.isEmpty ? character : label,
      text: character,
      alt: alt,
      shift: shift,
    );
  }
  if (label.isNotEmpty) {
    return TerminalKey(key: label, ctrl: ctrl, alt: alt, shift: shift);
  }
  return null;
}

/// O texto que a tecla digita, para entregar sem passar pelo método de entrada.
///
/// No Windows o texto do terminal não chegava pelo `TextInputClient` (a caixa
/// de chat, um `TextField`, recebia; o terminal só via Enter e Backspace). Lá a
/// tecla já traz o caractere do layout, então a UI o manda direto e devolve
/// "tratada", o que também impede o motor de entregar o mesmo texto de novo.
/// Sem caractere (tecla morta, modificador) ou com Ctrl/Alt sozinhos (que são
/// atalho, não texto) devolve `null` e a tecla segue o caminho de sempre. Ctrl
/// e Alt juntos são o AltGr do Windows, que digita (`@`, `/`, `€`).
String? typedTextOnWindows(
  KeyEvent event, {
  required bool ctrl,
  required bool alt,
  required bool meta,
  TargetPlatform? platform,
}) {
  if ((platform ?? defaultTargetPlatform) != TargetPlatform.windows) {
    return null;
  }
  if (event is KeyUpEvent || meta || ctrl != alt) return null;
  final character = event.character;
  if (character == null || character.isEmpty) return null;
  final printable = character.runes.every((r) => r >= 0x20 && r != 0x7f);
  return printable ? character : null;
}

bool _isControl(String s) => s.runes.length == 1 && s.runes.first < 0x20;

final _named = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.enter: 'enter',
  LogicalKeyboardKey.numpadEnter: 'enter',
  LogicalKeyboardKey.tab: 'tab',
  LogicalKeyboardKey.backspace: 'backspace',
  LogicalKeyboardKey.escape: 'escape',
  LogicalKeyboardKey.arrowUp: 'up',
  LogicalKeyboardKey.arrowDown: 'down',
  LogicalKeyboardKey.arrowLeft: 'left',
  LogicalKeyboardKey.arrowRight: 'right',
  LogicalKeyboardKey.home: 'home',
  LogicalKeyboardKey.end: 'end',
  LogicalKeyboardKey.pageUp: 'pageup',
  LogicalKeyboardKey.pageDown: 'pagedown',
  LogicalKeyboardKey.delete: 'delete',
  LogicalKeyboardKey.insert: 'insert',
  LogicalKeyboardKey.f1: 'f1',
  LogicalKeyboardKey.f2: 'f2',
  LogicalKeyboardKey.f3: 'f3',
  LogicalKeyboardKey.f4: 'f4',
  LogicalKeyboardKey.f5: 'f5',
  LogicalKeyboardKey.f6: 'f6',
  LogicalKeyboardKey.f7: 'f7',
  LogicalKeyboardKey.f8: 'f8',
  LogicalKeyboardKey.f9: 'f9',
  LogicalKeyboardKey.f10: 'f10',
  LogicalKeyboardKey.f11: 'f11',
  LogicalKeyboardKey.f12: 'f12',
};

/// Modificador sozinho não é tecla: ele só vale junto com a próxima.
final _modifiers = <LogicalKeyboardKey>{
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.fn,
};
