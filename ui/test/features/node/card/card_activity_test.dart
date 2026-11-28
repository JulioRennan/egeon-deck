import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';
import 'package:egeon_deck/features/node/card/domain/entities/card_activity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('o agente aguardando vizinhos lê a lista do core', () {
    final activity = CardActivity.fromMap({
      'state': 'awaiting',
      'needs_attention': false,
      'waiting_on': ['claude', 'dev'],
      'label': 'aguardando claude',
      'pending': 0,
    });
    expect(activity.waitingOn, ['claude', 'dev']);
    expect(CardActivity.fromMap({'state': 'ready'}).waitingOn, isEmpty);
  });

  test('um card aguardando não derruba o nó (e o canvas inteiro com ele)', () {
    final card = CanvasCard.fromNode({
      'id': 'revisor',
      'type': 'agent',
      'frame': {'x': 3412.0, 'y': 1581.0, 'w': 720.0, 'h': 460.0},
      'activity': {
        'state': 'awaiting',
        'waiting_on': ['claude'],
        'label': 'aguardando claude',
        'glyph': 'hourglass',
      },
    });
    expect(card.activity.state, 'awaiting');
  });
}
