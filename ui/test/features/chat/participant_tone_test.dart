import 'dart:convert';
import 'dart:io';

import 'package:egeon_deck/features/chat/domain/entities/chat_participant.dart';
import 'package:egeon_deck/features/node/card/domain/entities/card_activity.dart';
import 'package:flutter_test/flutter_test.dart';

// O tom e o aviso do participante são do core; a UI só os lê.
void main() {
  test('lê tone e needsAttention como o core manda no participants', () {
    final raw = jsonDecode(
      File('../rust/crates/egeon-core/fixtures/chat/events.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    final participants = <Map<String, Object?>>[];
    void walk(Object? node) {
      if (node is Map<String, Object?>) {
        if (node['op'] == 'participants') {
          participants.addAll(
            (node['list']! as List<Object?>).cast<Map<String, Object?>>(),
          );
        }
        node.values.forEach(walk);
      } else if (node is List<Object?>) {
        node.forEach(walk);
      }
    }

    walk(raw);
    expect(participants, isNotEmpty);
    for (final map in participants) {
      final read = ChatParticipantInfo.fromMap(map);
      expect(read.tone, ActivityTone.parse(map['tone']));
      expect(read.needsAttention, map['needsAttention']);
      // A tela do terminal vem pronta do core: `<bancada>.<nó>`.
      expect(read.screen, map['screen']);
      expect(read.screen, endsWith('.${read.id}'));
      // A linha de estado vem pronta: a UI não monta texto a partir do nome.
      expect(read.status, map['status']);
      expect(read.statusTone, StatusTone.parse(map['statusTone']));
    }
    expect(participants.any((m) => m['status'] == 'trabalhando…'), isTrue);
    expect(participants.any((m) => m['tone'] == 'green'), isTrue);
  });

  test('sem tone no mapa, sem cor; sem needsAttention, falso', () {
    final read = ChatParticipantInfo.fromMap({
      'id': 'a',
      'address': 'w/a',
      'activity': 'asking',
    });
    expect(read.tone, isNull, reason: 'a UI não infere cor do nome do estado');
    expect(read.needsAttention, isFalse);
  });
}
