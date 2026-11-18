import 'package:egeon_deck/features/node/terminal/presentation/widgets/terminal_key_mapper.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

KeyDownEvent down(
  LogicalKeyboardKey key,
  PhysicalKeyboardKey physical, [
  String? character,
]) => KeyDownEvent(
  physicalKey: physical,
  logicalKey: key,
  character: character,
  timeStamp: Duration.zero,
);

void main() {
  keyMonitorTests();
  TestWidgetsFlutterBinding.ensureInitialized();
  final keyboard = HardwareKeyboard.instance;

  test('letra digitada não é tecla: o texto vem do método de entrada', () {
    expect(
      mapTerminalKey(
        down(LogicalKeyboardKey.keyA, PhysicalKeyboardKey.keyA, 'A'),
        keyboard,
      ),
      isNull,
    );
  });

  test('caractere acentuado também fica com o método de entrada', () {
    expect(
      mapTerminalKey(
        down(LogicalKeyboardKey.keyC, PhysicalKeyboardKey.keyC, 'ç'),
        keyboard,
      ),
      isNull,
    );
  });

  test('tecla morta (sem caractere) não vira tecla', () {
    expect(
      mapTerminalKey(
        down(LogicalKeyboardKey.keyE, PhysicalKeyboardKey.keyE),
        keyboard,
      ),
      isNull,
    );
  });

  test('teclas nomeadas', () {
    expect(
      mapTerminalKey(
        down(LogicalKeyboardKey.pageUp, PhysicalKeyboardKey.pageUp),
        keyboard,
      )!.key,
      'pageup',
    );
    expect(
      mapTerminalKey(
        down(LogicalKeyboardKey.f5, PhysicalKeyboardKey.f5),
        keyboard,
      )!.key,
      'f5',
    );
  });

  test('modificador sozinho não é tecla', () {
    expect(
      mapTerminalKey(
        down(LogicalKeyboardKey.controlLeft, PhysicalKeyboardKey.controlLeft),
        keyboard,
      ),
      isNull,
    );
  });

  test('soltar a tecla não manda nada', () {
    final up = KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.keyA,
      logicalKey: LogicalKeyboardKey.keyA,
      timeStamp: Duration.zero,
    );
    expect(mapTerminalKey(up, keyboard), isNull);
  });
}

/// Porte de KeyMonitorTests: tecla com o terminal focado é você falando com o
/// agente — menos o atalho do app, que nunca chega ao pty (ADR-063).
void keyMonitorTests() {
  group('reachesPty', () {
    test('as teclas comuns chegam ao pty', () {
      expect(reachesPty(meta: false, character: 'a'), isTrue);
      expect(
        reachesPty(meta: false, character: 'c'),
        isTrue,
        reason: '⌃C interrompe o agente',
      );
      expect(reachesPty(meta: false, character: 'A'), isTrue);
    });

    test('os atalhos de aba não contam como digitação', () {
      expect(reachesPty(meta: true, character: '1'), isFalse);
      expect(reachesPty(meta: true, character: ']'), isFalse);
      expect(reachesPty(meta: true, character: '}'), isFalse);
      expect(reachesPty(meta: true, character: 'w'), isFalse);
    });

    test('colar continua contando', () {
      expect(reachesPty(meta: true, character: 'v'), isTrue);
    });
  });
}
