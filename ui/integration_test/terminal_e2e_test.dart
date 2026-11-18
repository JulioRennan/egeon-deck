// ATENÇÃO: este teste ABRE A JANELA do app na tela de quem roda. Não faz parte
// de `fvm flutter test`; só rode de propósito, com o usuário ciente.
import 'dart:io';

import 'package:egeon_deck/features/node/terminal/presentation/widgets/terminal_line_painter.dart';
import 'package:egeon_deck/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Ponta a ponta com o egeon-app de verdade: precisa de EGEON_APP_BIN (e de
// EGEON_HOME numa pasta curta e temporária) no ambiente.
//   EGEON_HOME=/tmp/egeon-e2e EGEON_APP_BIN=… fvm flutter test \
//     integration_test/terminal_e2e_test.dart -d macos

String screenText(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((p) => p.painter)
    .whereType<TerminalLinePainter>()
    .map((p) => p.line.runs.map((r) => r.text).join())
    .join('\n');

Future<void> until(
  WidgetTester tester,
  bool Function() condition, {
  String? reason,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      final lines = screenText(tester).split('\n');
      fail(
        '${reason ?? 'condição'} não ocorreu. Fim da tela:\n'
        '${lines.skip(lines.length > 8 ? lines.length - 8 : 0).join('\n')}',
      );
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

/// O texto digitado entra pelo método de entrada do sistema, como na
/// composição de acentos.
Future<void> type(WidgetTester tester, String text) async {
  tester.testTextInput.enterText(text);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('zsh aparece, aceita "echo oi" e mostra a saída', (tester) async {
    final app = createEgeonDeckApp(Platform.environment);
    // O harness não passa pelo onExitRequested: encerra o core filho aqui.
    addTearDown(() => tester.runAsync(app.connection.close));
    await tester.pumpWidget(app);

    await until(
      tester,
      () => screenText(tester).trim().isNotEmpty,
      reason: 'prompt do shell',
    );

    await type(tester, 'echo oi');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    await until(
      tester,
      () => screenText(tester).split('\n').any((l) => l.trim() == 'oi'),
      reason: 'saída "oi"',
    );

    await type(tester, 'echo "ação é ü ~a"');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    await until(
      tester,
      () =>
          screenText(tester).split('\n').any((l) => l.trim() == 'ação é ü ~a'),
      reason: 'saída acentuada',
    );

    // ⌘V vai pelo comando paste; com o modo 2004 do zsh a colagem não executa
    // sozinha, só com o Enter.
    await Clipboard.setData(const ClipboardData(text: 'echo colado-ok'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await until(
      tester,
      () => screenText(tester).contains('echo colado-ok'),
      reason: 'texto colado na linha de comando',
    );
    expect(
      screenText(tester).split('\n').any((l) => l.trim() == 'colado-ok'),
      isFalse,
      reason: 'a colagem não pode executar antes do Enter',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await until(
      tester,
      () => screenText(tester).split('\n').any((l) => l.trim() == 'colado-ok'),
      reason: 'saída do comando colado',
    );

    // Tempo para uma captura de tela externa antes de fechar.
    await tester.runAsync(
      () => Future<void>.delayed(
        Duration(
          seconds: int.tryParse(Platform.environment['E2E_HOLD'] ?? '') ?? 6,
        ),
      ),
    );
    await tester.pump();
  });
}
