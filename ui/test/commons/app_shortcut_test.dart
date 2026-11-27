import 'package:egeon_deck/commons/utils/app_shortcut.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// `SingleActivator` não compara por valor: descreve as teclas.
String keys(SingleActivator a) =>
    '${a.trigger.keyLabel}'
    '${a.control ? '+ctrl' : ''}${a.meta ? '+meta' : ''}'
    '${a.shift ? '+shift' : ''}${a.alt ? '+alt' : ''}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugUsesCommandKey = true);

  test('no macOS o atalho é ⌘, com ⇧ e ⌥ onde havia', () {
    debugUsesCommandKey = true;
    expect(keys(appActivator(LogicalKeyboardKey.keyK)), 'K+meta');
    expect(
      keys(appActivator(LogicalKeyboardKey.keyP, alt: true)),
      'P+meta+alt',
    );
    expect(appShortcutLabel('K'), '⌘K');
    expect(appShortcutLabel('T', shift: true), '⇧⌘T');
    expect(appShortcutLabel('1', alt: true, macOnly: true), '⌥⌘1');
  });

  test('fora do macOS é Ctrl+Shift, sem Alt (o AltGr) e sem ⌘', () {
    debugUsesCommandKey = false;
    expect(keys(appActivator(LogicalKeyboardKey.keyK)), 'K+ctrl+shift');
    expect(
      keys(appActivator(LogicalKeyboardKey.keyK, shift: true)),
      'K+ctrl+shift',
    );
    expect(
      keys(appActivator(LogicalKeyboardKey.keyP, alt: true)),
      'P+ctrl+shift',
    );
    expect(appShortcutLabel('K'), 'Ctrl+Shift+K');
    expect(appShortcutLabel('T', shift: true), 'Ctrl+Shift+T');
    expect(
      appShortcutLabel('1', alt: true, macOnly: true),
      isNull,
      reason: 'o ⌥⌘1 do canvas não existe fora do macOS',
    );
  });
}
