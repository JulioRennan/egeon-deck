import 'package:egeon_deck/features/chat/domain/entities/chat_block.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_participant.dart';

const front = {
  'id': 'front',
  'address': 'deck/front',
  'isAgent': true,
  'role': null,
};

ChatBlock prompt(int i, {bool pending = false}) => ChatBlock.fromMap({
  'id': 'p|u$i',
  'messageKey': 'p|u$i',
  'kind': 'prompt',
  'first': true,
  'last': true,
  'depth': 0,
  'mention': false,
  'pending': pending,
  'quote': null,
  'at': '1970-01-01T00:16:40.000Z',
  'from': null,
  'text': 'pergunta $i',
  'to': front,
});

ChatBlock header(int i) => ChatBlock.fromMap({
  'id': 'h|u$i',
  'messageKey': 'r|u$i',
  'kind': 'header',
  'first': true,
  'last': false,
  'depth': 0,
  'at': '1970-01-01T00:16:49.000Z',
  'from': front,
  'quote': null,
  'cost': null,
});

ChatBlock prose(int i) => ChatBlock.fromMap({
  'id': 'b|u$i|0',
  'messageKey': 'r|u$i',
  'kind': 'prose',
  'first': false,
  'last': true,
  'depth': 0,
  'from': front,
  'blocks': [
    {
      'kind': 'paragraph',
      'spans': [
        {
          'kind': 'text',
          'text':
              'Resposta $i com texto suficiente para a linha ter altura de '
              'verdade, e um pouco mais para quebrar em duas linhas na bolha.',
        },
      ],
    },
  ],
});

/// [count] conversas, numeradas a partir de [start]: um prompt seu e a resposta
/// do agente, cada uma.
List<ChatBlock> conversation(int count, {int start = 0}) => [
  for (var i = start; i < start + count; i++) ...[
    prompt(i),
    header(i),
    prose(i),
  ],
];

const frontInfo = ChatParticipantInfo(
  id: 'front',
  address: 'deck/front',
  isAgent: true,
  activity: 'working',
);
const backInfo = ChatParticipantInfo(
  id: 'back',
  address: 'deck/back',
  isAgent: true,
  role: 'revisor',
);
const shellInfo = ChatParticipantInfo(
  id: 'sh1',
  address: 'deck/sh1',
  isAgent: false,
);
