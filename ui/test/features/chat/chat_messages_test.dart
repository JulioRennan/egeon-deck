import 'package:egeon_deck/commons/widgets/eg/diff_view.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_block.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/chat_block_view.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/chat_palette.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/diff_rows.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/message_frame.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';

const _who = {'id': 'front', 'address': 'deck/front', 'isAgent': true};

Map<String, Object?> map(Map<String, Object?> extra) => {
  'id': 'x',
  'messageKey': 'm',
  'first': true,
  'last': true,
  'depth': 0,
  ...extra,
};

Future<void> show(WidgetTester tester, Map<String, Object?> block) =>
    tester.pumpWidget(
      egHost(
        SizedBox(
          width: 900,
          child: ChatBlockView(
            block: ChatBlock.fromMap(map(block)),
            actions: ChatRowActions(
              onToggleStep: (_) {},
              onCycleGroup: (_) {},
              onQuote: (_) {},
            ),
          ),
        ),
        size: const Size(1000, 600),
      ),
    );

void main() {
  group('diffRowsOf', () {
    test('pareia remoções e adições e numera as linhas a partir do hunk', () {
      final d = diffRowsOf([
        '@@ -10,2 +20,3 @@',
        ' ctx',
        '-velha',
        '+nova 1',
        '+nova 2',
      ]);
      expect(d.added, 2);
      expect(d.removed, 1);
      expect(d.rows.first.fold, '@@ -10,2 +20,3 @@');
      final ctx = d.rows[1];
      expect(ctx.left!.n, 10);
      expect(ctx.right!.n, 20);
      expect(ctx.left!.sign, isNull);
      final pair = d.rows[2];
      expect(pair.left!.text, 'velha');
      expect(pair.left!.n, 11);
      expect(pair.right!.text, 'nova 1');
      expect(pair.right!.n, 21);
      final extra = d.rows[3];
      expect(extra.left, isNull);
      expect(extra.right!.text, 'nova 2');
    });

    test(
      'ignora "No newline", "diff --git" e "index": não andam os contadores',
      () {
        final d = diffRowsOf([
          'diff --git a/x b/x',
          'index 1..2 100644',
          '--- a/x',
          '+++ b/x',
          '@@ -1,2 +1,2 @@',
          '-a',
          r'\ No newline at end of file',
          '+b',
          ' c',
        ]);
        expect(d.removed, 1);
        expect(d.added, 1);
        // O contexto depois do aviso continua na linha 2 dos dois lados.
        final ctx = d.rows.last;
        expect(ctx.left!.n, 2);
        expect(ctx.right!.n, 2);
        expect(d.rows.where((r) => r.fold != null), hasLength(1));
      },
    );

    test('sem hunk, conta de 1 e ignora os cabeçalhos de arquivo', () {
      final d = diffRowsOf(['--- a', '+++ b', '-x', '+y']);
      expect(d.rows, hasLength(1));
      expect(d.rows.single.left!.n, 1);
    });
  });

  testWidgets(
    'a mensagem do usuário é a bolha carbon, canto de baixo apertado',
    (tester) async {
      await show(tester, {
        'kind': 'prompt',
        'to': _who,
        'text': 'Monte o time',
        'at': '2026-11-19T22:40:00',
        'pending': false,
        'mention': false,
      });
      final bubble = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration as BoxDecoration)
          .firstWhere((d) => d.color == EgeonColors.dark.carbon);
      final r = bubble.borderRadius! as BorderRadius;
      expect(r.bottomRight, const Radius.circular(4));
      expect(r.topLeft, const Radius.circular(12));
      expect(find.text('Monte o time'), findsOneWidget);
      expect(find.textContaining('você · '), findsOneWidget);
      expect(
        tester.getSize(find.byType(DecoratedBox).first).width,
        lessThanOrEqualTo(520),
      );
    },
  );

  testWidgets('o prompt de um agente para outro é uma linha com seta', (
    tester,
  ) async {
    await show(tester, {
      'kind': 'prompt',
      'from': 'maestro',
      'to': _who,
      'text': 'Revisar o diff',
      'at': '2026-11-19T23:31:00',
      'pending': false,
      'mention': false,
    });
    expect(find.text('maestro'), findsOneWidget);
    expect(find.text('front'), findsOneWidget);
    expect(find.text('Revisar o diff'), findsOneWidget);
    final name = tester.widget<Text>(find.text('maestro'));
    expect(name.style!.color, ChatPalette.ofId(EgeonColors.dark, 'maestro'));
  });

  testWidgets('o cabeçalho da resposta: nome na cor, hora e custo em mono', (
    tester,
  ) async {
    await show(tester, {
      'kind': 'header',
      'from': _who,
      'at': '2026-11-19T23:08:00',
      'cost': {'text': 'US\$ 1,12', 'detail': 'x'},
    });
    final name = tester.widget<Text>(find.text('front'));
    expect(name.style!.fontWeight, FontWeight.w600);
    expect(
      name.style!.color,
      ChatPalette.identityOfId('front').color(EgeonColors.dark),
    );
    expect(find.textContaining('US\$ 1,12'), findsOneWidget);
  });

  testWidgets('a capa de passos tem o fundo de 2,5% e o resumo em muted', (
    tester,
  ) async {
    await show(tester, {
      'kind': 'group',
      'from': _who,
      'count': 3,
      'lastStep': 'ligou a fila',
      'level': 'summary',
    });
    expect(find.text('3 passos'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('· ligou a fila')).style!.color,
      EgeonColors.dark.textMuted,
    );
  });

  test('a coluna da conversa: 760 com 32 de respiro, 28 e 10 de vão', () {
    expect(MessageFrame.maxWidth, 760);
    expect(MessageFrame.side, 32);
    expect(MessageFrame.messageGap, 28);
    expect(MessageFrame.pieceGap, 10);
  });

  testWidgets('o diff usa o DiffView do DS com +n −n', (tester) async {
    await show(tester, {
      'kind': 'diff',
      'from': _who,
      'file': 'lib/a.dart',
      'diff': ['@@ -1 +1 @@', '-a', '+b'],
    });
    final v = tester.widget<DiffView>(find.byType(DiffView));
    expect([v.added, v.removed], [1, 1]);
  });

  testWidgets('a citação é um botão steel de uma linha, sem o fio colorido', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      egHost(
        SizedBox(
          width: 900,
          child: QuoteView(
            quote: ChatQuote(
              authorId: 'maestro',
              text: 'um texto bem comprido ' * 20,
              at: DateTime(2026, 11, 19, 23, 31),
              targetKey: 'p|1',
            ),
            onTap: () => taps++,
          ),
        ),
        size: const Size(1000, 600),
      ),
    );
    final box = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => d.decoration as BoxDecoration)
        .firstWhere((d) => d.color == EgeonColors.dark.steel);
    expect(box.border, isNull);
    expect(box.borderRadius, BorderRadius.circular(8));
    expect(
      tester.getSize(find.byType(QuoteView)).width,
      lessThanOrEqualTo(900),
    );
    final text = tester.widget<Text>(find.textContaining('um texto bem'));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    await tester.tap(find.byType(QuoteView));
    expect(taps, 1);
  });

  testWidgets('o cabeçalho põe a hora e o custo colados ao nome, sempre', (
    tester,
  ) async {
    await tester.pumpWidget(
      egHost(
        SizedBox(
          width: 900,
          child: ChatBlockView(
            block: ChatBlock.fromMap(
              map({
                'kind': 'header',
                'from': _who,
                'at': '2026-11-19T23:08:00',
                'cost': {'text': 'US\$ 1,12', 'detail': 'x'},
              }),
            ),
            actions: ChatRowActions(
              onToggleStep: (_) {},
              onCycleGroup: (_) {},
              onQuote: (_) {},
            ),
          ),
        ),
        size: const Size(1000, 600),
      ),
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('message-meta'))).data,
      '23:08 · US\$ 1,12',
    );
    expect(find.text('deck/front'), findsNothing);
  });
}
