import 'package:flutter/widgets.dart';

import '../../../../../theme/egeon_colors.dart';
import '../../domain/entities/queue_item.dart';

/// A conversa de uma tarefa: o que o agente perguntou, comentou, e o que você
/// respondeu.
class ThreadView extends StatelessWidget {
  const ThreadView({required this.messages, super.key});

  final List<QueueMessage> messages;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final message in messages)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _Message(message),
        ),
    ],
  );
}

class _Message extends StatelessWidget {
  const _Message(this.message);

  final QueueMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.kind == MessageKind.reply;
    final color = switch (message.kind) {
      MessageKind.question => context.eg.attention,
      MessageKind.done => context.eg.success,
      MessageKind.note => context.eg.textMuted,
      MessageKind.reply => context.eg.accent,
    };
    final who = mine ? 'você' : (message.author ?? 'agente');
    final label = switch (message.kind) {
      MessageKind.question => '$who perguntou',
      MessageKind.done => '$who terminou',
      MessageKind.note => who,
      MessageKind.reply => who,
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
      decoration: BoxDecoration(
        color: context.eg.steel,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: color, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.text,
            style: TextStyle(
              color: context.eg.textPrimary,
              fontSize: 12,
              height: 1.3,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
