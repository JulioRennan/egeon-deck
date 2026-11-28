import 'package:egeon_deck/commons/widgets/eg/glass_surface.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_participant.dart';
import 'package:egeon_deck/features/chat/domain/entities/permission_request.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/chat_composer.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/permission_tray.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';

const front = ChatParticipantInfo(
  id: 'front',
  address: 'deck/front',
  isAgent: true,
);
const back = ChatParticipantInfo(
  id: 'back',
  address: 'deck/back',
  isAgent: true,
);

Future<List<String>> mount(
  WidgetTester tester, {
  ChatParticipantInfo? target = front,
  List<Widget> above = const [],
  ValueChanged<String>? onPick,
  double width = 1000,
  Widget? traits,
}) async {
  tester.view
    ..physicalSize = Size(width, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final sent = <String>[];
  await tester.pumpWidget(
    egHost(
      fill: true,
      ChatComposer(
        target: target,
        participants: const [front, back],
        onPickTarget: onPick,
        onSend: sent.add,
        above: above,
        traits: traits,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return sent;
}

void main() {
  testWidgets('os botões têm vão 4 e não há "+" enquanto o chat não anexa', (
    tester,
  ) async {
    await mount(tester);
    expect(find.byKey(const ValueKey('composer-attach')), findsNothing);
    final slash = tester.getRect(find.byKey(const ValueKey('composer-slash')));
    final at = tester.getRect(find.byKey(const ValueKey('composer-at')));
    expect(at.left - slash.right, 4);
  });

  testWidgets('o modelo e o esforço aparecem com largura e somem sem ela', (
    tester,
  ) async {
    const traits = Text('Opus 5.5 · médio', key: ValueKey('traits'));
    await mount(tester, traits: traits);
    expect(find.byKey(const ValueKey('traits')), findsOneWidget);
    await mount(tester, traits: traits, width: 400);
    expect(find.byKey(const ValueKey('traits')), findsNothing);
  });

  testWidgets('na janela mínima o "Para" encurta e nada estoura', (
    tester,
  ) async {
    await mount(tester, width: 300);
    expect(find.text('Para'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o composer é um cartão de vidro de 720, com o convite', (
    tester,
  ) async {
    await mount(tester);
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(
      tester.getSize(find.byType(GlassSurface)).width,
      lessThanOrEqualTo(720),
    );
    expect(find.textContaining('Peça algo ao time'), findsOneWidget);
    expect(find.text('Para'), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-target')), findsOneWidget);
  });

  testWidgets('enviar fica a 40% sem texto e manda com Enter', (tester) async {
    final sent = await mount(tester);
    expect(
      tester
          .widget<Opacity>(
            find.descendant(
              of: find.byKey(const ValueKey('composer-send')),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      lessThan(1),
    );
    await tester.enterText(find.byType(EditableText), 'oi');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pump();
    expect(sent, ['oi']);
  });

  testWidgets('os botões / e @ digitam o caractere no campo', (tester) async {
    await mount(tester);
    await tester.tap(find.byKey(const ValueKey('composer-slash')));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '/',
    );
    await tester.tap(find.byKey(const ValueKey('composer-at')));
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '/@',
    );
  });

  testWidgets('o destinatário abre a lista e escolher foca o agente', (
    tester,
  ) async {
    final picked = <String>[];
    await mount(tester, onPick: picked.add);
    await tester.tap(find.byKey(const ValueKey('composer-target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Mandar para'), findsOneWidget);
    await tester.tap(find.text('back'));
    await tester.pump();
    expect(picked, ['back']);
  });

  testWidgets('sem ninguém na conversa, não manda e avisa', (tester) async {
    await mount(tester, target: null);
    expect(find.text('Ninguém na conversa ainda'), findsOneWidget);
    expect(find.text('Para'), findsNothing);
  });

  group('permissão acima do campo, dentro do composer', () {
    Widget tray(PermissionRequest r, List<String> log) => PermissionTray(
      request: r,
      agentName: 'revisor',
      onAnswer: (id, a) => log.add('$id:$a'),
      onChoose: (id, c) => log.add('$id:$c'),
      onAnswerAll: (id, a) => log.add('$id:$a'),
    );

    testWidgets('Permitir · Sempre · Negar, em attention', (tester) async {
      final log = <String>[];
      await mount(
        tester,
        above: [
          tray(
            const PermissionRequest(
              id: 'p1',
              tool: 'Edit',
              summary: 'lib/canvas/toolbar.dart',
              canAlwaysAllow: true,
            ),
            log,
          ),
        ],
      );
      expect(find.text('Permitir'), findsOneWidget);
      expect(find.text('Sempre'), findsOneWidget);
      expect(find.text('Negar'), findsOneWidget);
      expect(find.textContaining('quer editar'), findsOneWidget);
      expect(
        find.textContaining('lib/canvas/toolbar.dart', findRichText: true),
        findsOneWidget,
      );
      final box =
          tester
                  .widget<DecoratedBox>(
                    find.byKey(const ValueKey('permission-tray')),
                  )
                  .decoration
              as BoxDecoration;
      expect(box.color, EgeonColors.dark.attention.withValues(alpha: 0.08));
      await tester.tap(find.text('Sempre'));
      await tester.tap(find.text('Negar'));
      await tester.tap(find.text('Permitir'));
      expect(log, ['p1:always', 'p1:deny', 'p1:allow']);
    });

    testWidgets('sem sugestão de regra, não há "Sempre"', (tester) async {
      await mount(
        tester,
        above: [
          tray(const PermissionRequest(id: 'p', tool: 'Bash'), <String>[]),
        ],
      );
      expect(find.text('Sempre'), findsNothing);
    });
  });
}
