import 'package:egeon_deck/commons/utils/agent_identity.dart';
import 'package:egeon_deck/commons/widgets/eg/identity.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_block.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/chat_palette.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('o mesmo id é sempre a mesma identidade', () {
    expect(agentIdentity('revisor'), agentIdentity('revisor'));
    expect(agentIdentity('maestro'), agentIdentity('maestro'));
  });

  test('os ids se espalham pelas 12 identidades', () {
    final seen = {
      for (final id in [
        'a',
        'b',
        'c',
        'revisor',
        'testes',
        'front',
        'back',
        'dev',
        'x1',
        'x2',
        'x3',
        'x4',
        'x5',
        'x6',
        'x7',
        'x8',
      ])
        agentIdentity(id),
    };
    expect(seen.length, greaterThan(5));
    expect(Identity.values.length, 12);
  });

  test('o chat e o card pintam o agente com a mesma cor', () {
    const c = EgeonColors.dark;
    const who = ChatWho(id: 'revisor', address: 'deck/revisor', isAgent: true);
    expect(ChatPalette.of(c, who), agentIdentity('revisor').color(c));
    expect(ChatPalette.ofId(c, 'revisor'), agentIdentity('revisor').color(c));
  });
}
