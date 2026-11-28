import 'package:egeon_deck/commons/widgets/eg/eg_icon.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_block.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_markdown.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_participant.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/chat_block_view.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/chat_palette.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/md_text.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/participants_column.dart';
import 'package:egeon_deck/commons/widgets/eg/tooltip.dart';
import 'package:egeon_deck/features/chat/domain/entities/permission_request.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/permission_tray.dart';
import 'package:egeon_deck/features/node/card/domain/entities/card_activity.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';

const _c = EgeonColors.dark;

void main() {
  test(
    'o verbo da ferramenta sai em português; a desconhecida fica usar X',
    () {
      expect(toolVerb('Edit'), 'editar');
      expect(toolVerb('Write'), 'escrever');
      expect(toolVerb('Bash'), 'rodar');
      expect(toolVerb('Foo'), 'usar Foo');
    },
  );

  test('nome de agente no texto fica na cor dele; só a palavra inteira', () {
    final spans = mdSpans(
      const [MdText('o revisor e os testes, revisores não')],
      base: const TextStyle(),
      colors: _c,
      mentions: const {'revisor', 'testes'},
    );
    final parts = (spans.single as TextSpan).children!.cast<TextSpan>();
    Color? colorOf(String text) =>
        parts.firstWhere((s) => s.text == text).style?.color;
    expect(colorOf('revisor'), ChatPalette.ofId(_c, 'revisor'));
    expect(colorOf('testes'), ChatPalette.ofId(_c, 'testes'));
    expect(parts.any((s) => s.text == 'revisores'), isFalse);
  });

  test(
    'sessão de comando: o prompt em accent, andamento muted, passou verde',
    () {
      expect(isShellSession(r'$ flutter test'), isTrue);
      expect(isShellSession('flutter test'), isFalse);
      final spans = shellSession(
        '\$ flutter test\n00:04 +18: a.dart\n00:05 +23: All tests passed!',
        _c,
      ).cast<TextSpan>();
      Color? colorOf(String text) =>
          spans.firstWhere((s) => s.text == text).style?.color;
      expect(spans.first.style?.color, _c.accent);
      expect(colorOf('00:04 +18: a.dart'), _c.textMuted);
      expect(colorOf('00:05 +23: All tests passed!'), _c.success);
    },
  );

  testWidgets('passo da capa aberta mora na caixa do grupo e sem glifo tofu', (
    tester,
  ) async {
    ChatBlock step(String glyph, String text, {String? detail}) =>
        ChatBlock.fromMap({
          'id': 's',
          'messageKey': 'm',
          'first': false,
          'last': false,
          'depth': 1,
          'kind': 'step',
          'from': {'id': 'a', 'address': 'd/a', 'isAgent': true},
          'expanded': false,
          'step': {'glyph': glyph, 'text': text, 'detail': detail},
        });
    await tester.pumpWidget(
      egHost(
        Column(
          children: [
            ChatBlockView(
              block: step('⇄', 'aresta d/a → d/b'),
              actions: ChatRowActions(
                onToggleStep: (_) {},
                onCycleGroup: (_) {},
                onQuote: (_) {},
              ),
            ),
            ChatBlockView(
              block: step(r'$', 'ls x', detail: '59 arquivos'),
              actions: ChatRowActions(
                onToggleStep: (_) {},
                onCycleGroup: (_) {},
                onQuote: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
    expect(find.textContaining('⇄', findRichText: true), findsNothing);
    expect(
      find.textContaining('59 arquivos', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('aresta', findRichText: true), findsOneWidget);
  });

  testWidgets('participante concluído é um ✓ verde, não um ponto', (
    tester,
  ) async {
    await tester.pumpWidget(
      egHost(
        ParticipantsColumn(
          participants: const [
            ChatParticipantInfo(
              id: 'testes',
              address: 'd/testes',
              isAgent: true,
              activity: 'done',
              tone: ActivityTone.green,
            ),
          ],
          focused: null,
          onPick: (_) {},
        ),
      ),
    );
    final icons = tester.widgetList<EgIcon>(find.byType(EgIcon));
    expect(icons.map((i) => i.icon), contains(EgIcons.check));
    expect(icons.firstWhere((i) => i.icon == EgIcons.check).color, _c.success);
  });

  testWidgets(
    'comando longo: a dica traz o texto inteiro e o corte é só no fim',
    (tester) async {
      final long =
          'rm -rf build && flutter build macos --release && ${'x' * 200}\n'
          'echo pronto';
      await tester.pumpWidget(
        egHost(
          SizedBox(
            width: 520,
            child: PermissionTray(
              request: PermissionRequest(id: 'p', tool: 'Bash', summary: long),
              agentName: 'revisor',
              onAnswer: (_, _) {},
              onChoose: (_, _) {},
              onAnswerAll: (_, _) {},
            ),
          ),
        ),
      );
      final tip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('permission-summary-tip')),
      );
      expect(tip.message, long, reason: 'sem a troca do \\n: o texto inteiro');
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('permission-summary-tip')),
          matching: find.byType(Text),
        ),
      );
      expect(text.maxLines, 3);
      expect(text.overflow, TextOverflow.ellipsis);
    },
  );
}
