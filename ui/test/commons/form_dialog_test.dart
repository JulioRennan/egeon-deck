import 'package:egeon_deck/commons/widgets/form_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/hand_cursor.dart';
import '../support/overlay_host.dart';

class _Opener extends StatelessWidget {
  const _Opener(this.open);

  final void Function(BuildContext) open;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => open(context),
        child: const Text('abrir'),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'confirmar devolve true; cancelar, Esc e clicar fora devolvem false',
    (tester) async {
      bool? answer;
      await tester.pumpWidget(
        overlayHost(
          _Opener((context) async {
            answer = await confirmDialog(
              context,
              title: 'Remover?',
              message: 'A bancada sai da lista.',
              confirmLabel: 'Remover',
              destructive: true,
            );
          }),
        ),
      );

      Future<void> ask() async {
        await tester.tap(find.text('abrir'));
        await tester.pump();
        expect(find.text('Remover?'), findsOneWidget);
        expect(find.text('A bancada sai da lista.'), findsOneWidget);
      }

      await ask();
      await tester.tap(find.text('Remover'));
      await tester.pump();
      expect(answer, isTrue);
      expect(find.text('Remover?'), findsNothing);

      await ask();
      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      expect(answer, isFalse);

      await ask();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(answer, isFalse);
      expect(find.text('Remover?'), findsNothing);

      await ask();
      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      expect(answer, isFalse);
    },
  );

  testWidgets('a pergunta de uma linha devolve o texto aparado', (
    tester,
  ) async {
    String? answer = 'não rodou';
    await tester.pumpWidget(
      overlayHost(
        _Opener((context) async {
          answer = await promptDialog(
            context,
            title: 'Renomear bancada',
            confirmLabel: 'Renomear',
            initial: 'deck',
          );
        }),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();

    tester.testTextInput.enterText('  novo nome  ');
    await tester.pump();
    await tester.tap(find.text('Renomear'));
    await tester.pump();
    expect(answer, 'novo nome');
  });

  testWidgets('vazio na pergunta de uma linha conta como cancelar', (
    tester,
  ) async {
    String? answer = 'não rodou';
    await tester.pumpWidget(
      overlayHost(
        _Opener((context) async {
          answer = await promptDialog(
            context,
            title: 'Nome novo',
            confirmLabel: 'Renomear',
            initial: 'x',
          );
        }),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();
    tester.testTextInput.enterText('   ');
    await tester.pump();
    await tester.tap(find.text('Renomear'));
    await tester.pump();
    expect(answer, isNull);
  });

  testWidgets('a área de texto aceita vazio: apagar as regras é um valor', (
    tester,
  ) async {
    String? answer = 'não rodou';
    await tester.pumpWidget(
      overlayHost(
        _Opener((context) async {
          answer = await textAreaDialog(
            context,
            title: 'Regras — deck',
            confirmLabel: 'Salvar',
            initial: 'peça antes de commitar',
          );
        }),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();
    expect(find.text('peça antes de commitar'), findsOneWidget);
    tester.testTextInput.enterText('');
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    expect(answer, '');
  });

  testWidgets('a mensagem se fecha com o OK', (tester) async {
    await tester.pumpWidget(
      overlayHost(
        _Opener(
          (context) => messageDialog(
            context,
            title: 'Projeto com bancadas fica',
            message: 'Remova antes as bancadas de: egeon.',
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();
    expectHandOnEveryClickable(tester);
    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(find.text('Projeto com bancadas fica'), findsNothing);
  });
}
