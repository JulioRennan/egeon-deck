import 'package:egeon_deck/commons/utils/app_shortcut.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_key.dart';
import 'package:egeon_deck/features/node/terminal/presentation/widgets/terminal_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final windows = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  late List<TerminalKey> keys;
  late List<String> texts;
  late List<String> pastes;

  // O teste do Windows é o do Windows de verdade: a configuração global fixa o
  // ⌘ (o `flutter test` roda como Android) e aqui ela sai.
  setUp(() {
    keys = [];
    texts = [];
    pastes = [];
    debugUsesCommandKey = null;
  });
  tearDown(() => debugUsesCommandKey = true);

  Future<void> pumpTerminal(WidgetTester tester) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 400,
        height: 300,
        child: TerminalView(
          frames: const Stream.empty(),
          onKey: keys.add,
          onText: texts.add,
          onPaste: pastes.add,
          onResize: (_, _) {},
        ),
      ),
    ),
  );

  Future<void> down(
    LogicalKeyboardKey key, {
    String? character,
    bool repeat = false,
  }) async {
    if (repeat) {
      await simulateKeyRepeatEvent(
        key,
        platform: 'windows',
        character: character,
      );
    } else {
      await simulateKeyDownEvent(
        key,
        platform: 'windows',
        character: character,
      );
    }
  }

  testWidgets('a letra chega como texto, e a repetição também', (tester) async {
    await pumpTerminal(tester);
    await down(LogicalKeyboardKey.keyH, character: 'h');
    await down(LogicalKeyboardKey.keyH, character: 'h', repeat: true);
    expect(texts, ['h', 'h']);
    expect(keys, isEmpty);
  }, variant: windows);

  testWidgets('AltGr (Ctrl+Alt) digita em vez de virar Ctrl+Alt+letra', (
    tester,
  ) async {
    await pumpTerminal(tester);
    await simulateKeyDownEvent(
      LogicalKeyboardKey.controlLeft,
      platform: 'windows',
    );
    await simulateKeyDownEvent(
      LogicalKeyboardKey.altRight,
      platform: 'windows',
    );
    await down(LogicalKeyboardKey.keyQ, character: '/');
    expect(texts, ['/']);
    expect(keys, isEmpty);
    await simulateKeyUpEvent(LogicalKeyboardKey.altRight, platform: 'windows');
    await simulateKeyUpEvent(
      LogicalKeyboardKey.controlLeft,
      platform: 'windows',
    );
  }, variant: windows);

  testWidgets('Enter, Ctrl+C e setas seguem como teclas', (tester) async {
    await pumpTerminal(tester);
    await down(LogicalKeyboardKey.enter, character: '\r');
    await down(LogicalKeyboardKey.arrowUp);
    await simulateKeyDownEvent(
      LogicalKeyboardKey.controlLeft,
      platform: 'windows',
    );
    await down(LogicalKeyboardKey.keyC, character: '\u0003');
    await simulateKeyUpEvent(
      LogicalKeyboardKey.controlLeft,
      platform: 'windows',
    );
    expect(texts, isEmpty);
    expect(keys.map((k) => k.key), ['enter', 'up', 'c']);
    expect(keys.last.ctrl, isTrue);
  }, variant: windows);

  testWidgets('Ctrl+Shift+V cola', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, Object?>{'text': 'echo oi'}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpTerminal(tester);
    await simulateKeyDownEvent(
      LogicalKeyboardKey.controlLeft,
      platform: 'windows',
    );
    await simulateKeyDownEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'windows',
    );
    await down(LogicalKeyboardKey.keyV, character: '\u0016');
    await tester.pump();
    await simulateKeyUpEvent(LogicalKeyboardKey.shiftLeft, platform: 'windows');
    await simulateKeyUpEvent(
      LogicalKeyboardKey.controlLeft,
      platform: 'windows',
    );
    expect(pastes, ['echo oi']);
    expect(texts, isEmpty);
    expect(keys, isEmpty);
  }, variant: windows);

  testWidgets('AltGr+Shift digita a maiúscula acentuada em vez de colar', (
    tester,
  ) async {
    await pumpTerminal(tester);
    await simulateKeyDownEvent(
      LogicalKeyboardKey.controlLeft,
      platform: 'windows',
    );
    await simulateKeyDownEvent(
      LogicalKeyboardKey.altRight,
      platform: 'windows',
    );
    await simulateKeyDownEvent(
      LogicalKeyboardKey.shiftLeft,
      platform: 'windows',
    );
    await down(LogicalKeyboardKey.keyV, character: 'Ŵ');
    await tester.pump();
    await simulateKeyUpEvent(LogicalKeyboardKey.shiftLeft, platform: 'windows');
    await simulateKeyUpEvent(LogicalKeyboardKey.altRight, platform: 'windows');
    await simulateKeyUpEvent(
      LogicalKeyboardKey.controlLeft,
      platform: 'windows',
    );
    expect(texts, ['Ŵ']);
    expect(pastes, isEmpty);
    expect(keys, isEmpty);
  }, variant: windows);
}
