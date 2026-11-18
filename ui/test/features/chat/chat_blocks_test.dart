import 'dart:convert';
import 'dart:io';

import 'package:egeon_deck/features/chat/domain/entities/chat_block.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_markdown.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_update.dart';
import 'package:flutter_test/flutter_test.dart';

// As fixtures são gravadas pelo core Rust: aqui só se prova que a UI lê o que
// ele fala e reconstrói a lista como ele a reconstrói.
Map<String, Object?> fixture(String name) => jsonDecode(
  File('../rust/crates/egeon-core/fixtures/chat/$name.json').readAsStringSync(),
) as Map<String, Object?>;

List<ChatBlock> blocksOf(Object? raw) => [
  for (final b in raw! as List<Object?>)
    ChatBlock.fromMap(b! as Map<String, Object?>),
];

void main() {
  final blocks = blocksOf(fixture('blocks')['blocks']);

  test('toda linha da fixture do core é lida, de todos os tipos', () {
    expect(blocks.map((b) => b.runtimeType.toString()).toSet(), {
      'PromptBlock',
      'HeaderBlock',
      'ProseBlock',
      'CodeBlock',
      'StepBlock',
      'GroupBlock',
      'DiffBlock',
      'StatusBlock',
      'TypingBlock',
    });
  });

  test('o prompt traz destinatário, hora, eco pendente e citação', () {
    final prompt = blocks.whereType<PromptBlock>().first;
    expect(prompt.id, 'p|u1');
    expect(prompt.text, 'faz');
    expect(prompt.to.address, 'deck/front');
    expect(prompt.to.isAgent, isTrue);
    expect(prompt.at.toUtc().millisecondsSinceEpoch, 1000 * 1000);
    expect(prompt.pending, isFalse);
    expect(prompt.quote, isNull);
    expect(blocks.whereType<PromptBlock>().any((p) => p.pending), isTrue);
    expect(
      blocks.whereType<PromptBlock>().any((p) => p.fromText == 'back'),
      isTrue,
      reason: 'prompt de outro agente traz de quem veio',
    );
  });

  test('o cabeçalho tem custo; "agora" é hora ausente', () {
    final headers = blocks.whereType<HeaderBlock>().toList();
    expect(headers.first.cost!.text, 'US\$ 20,00');
    expect(headers.first.cost!.detail, startsWith('Este turno:'));
    expect(headers.first.at, isNull);
    expect(headers.any((h) => h.cost == null && h.at != null), isTrue);
  });

  test('prosa vira parágrafos com trechos; código traz a linguagem', () {
    final prose = blocks.whereType<ProseBlock>().first;
    final paragraph = prose.blocks.single as MdParagraph;
    expect(paragraph.spans.single.plain, 'Vou olhar.');
    final code = blocks.whereType<CodeBlock>().first;
    expect(code.language, 'swift');
    expect(code.code, 'let a = 1');
  });

  test('o código chega em trechos coloridos pelo core, linha a linha', () {
    final code = blocks.whereType<CodeBlock>().first;
    final lines = code.lines!;
    expect(lines, hasLength(1));
    expect(lines.single.map((t) => (t.kind, t.text)).toList(), [
      ('keyword', 'let'),
      ('plain', ' a = '),
      ('number', '1'),
    ]);
    expect(
      lines.single.map((t) => t.text).join(),
      code.code,
      reason: 'os trechos reconstroem o código',
    );
  });

  test('o passo traz glifo, comando e se está aberto', () {
    final step = blocks.whereType<StepBlock>().first;
    expect(step.step.glyph, r'$');
    expect(step.step.text, 'Roda');
    expect(step.step.detail, 'swift test');
    expect(step.step.isExpandable, isTrue);
    expect(step.expanded, isTrue);
    expect(step.step.isError, isFalse);
  });

  test('a capa (lastStep), o diff e o status ao vivo', () {
    final group = blocks.whereType<GroupBlock>().first;
    expect(group.count, 3);
    expect(group.lastStep, 'três');
    expect(group.level, GroupLevel.summary);
    final diff = blocks.whereType<DiffBlock>().first;
    expect(diff.file, 'a.swift');
    expect(diff.lines, ['@@ -1 +1 @@', '-a', '+b']);
    final status = blocks.whereType<StatusBlock>().first;
    expect(status.live, isA<LiveThinking>());
    expect(status.live.label, 'pensando…');
  });

  test('a bolha é o conjunto de linhas com a mesma messageKey', () {
    // A primeira resposta: do cabeçalho até a linha que fecha a bolha.
    final start = blocks.indexWhere((b) => b.messageKey == 'r|u1');
    final end = blocks.indexWhere((b) => b.messageKey == 'r|u1' && b.last);
    final bubble = blocks.sublist(start, end + 1);
    expect(bubble.first.first, isTrue);
    expect(bubble.last.last, isTrue);
    expect(bubble.where((b) => b.first).length, 1);
    expect(bubble.where((b) => b.last).length, 1);
  });

  test('cada cenário do core: aplicar os ops à lista antiga dá a nova', () {
    final scenarios = fixture('diffs')['scenarios']! as List<Object?>;
    expect(scenarios, isNotEmpty);
    for (final raw in scenarios) {
      final scenario = raw! as Map<String, Object?>;
      final ops = [
        for (final op in scenario['ops']! as List<Object?>)
          BlockOp.fromMap(op! as Map<String, Object?>),
      ];
      final result = applyOps(blocksOf(scenario['old']), ops);
      final expected = blocksOf(scenario['new']);
      expect(
        result.map((b) => b.raw),
        expected.map((b) => b.raw),
        reason: '${scenario['name']}',
      );
    }
  });

  test('um evento do canal lê workbench, rev e ops', () {
    final update = ChatUpdate.fromMap({
      'topic': 'chat/w1',
      'workbench': 'w1',
      'rev': 7,
      'ops': [
        {'op': 'remove', 'id': 'b|u1|2'},
        {
          'op': 'insert',
          'index': 0,
          'block': {
            'id': 't|back',
            'messageKey': 't|back',
            'kind': 'typing',
            'first': true,
            'last': true,
            'depth': 0,
            'from': {'id': 'back', 'address': 'deck/back', 'isAgent': true},
          },
        },
      ],
    });
    expect(update.workbench, 'w1');
    expect(update.rev, 7);
    expect(update.ops.first, isA<RemoveOp>());
    expect(update.ops.last, isA<InsertOp>());
  });
}
