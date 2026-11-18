import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/spinner.dart';
import '../../../node/card/presentation/widgets/card_status.dart'
    show ActivityColors;
import '../../../../theme/app_colors.dart';
import '../../domain/entities/chat_block.dart';
import '../../domain/entities/chat_participant.dart';
import '../../domain/entities/chat_queue.dart';
import 'chat_palette.dart';

/// A coluna de quem está na conversa: agentes em cima, terminais embaixo. O
/// clique põe em foco — é para o focado que o composer manda.
class ParticipantsColumn extends StatelessWidget {
  const ParticipantsColumn({
    required this.participants,
    required this.focused,
    required this.onPick,
    this.queues = const [],
    this.shownQueue,
    this.onPickQueue,
    this.onNewQueue,
    super.key,
  });

  static const width = 216.0;

  final List<ChatParticipantInfo> participants;

  /// O id em foco.
  final String? focused;
  final ValueChanged<String> onPick;

  /// As filas da bancada, a que está aberta no painel e os dois gestos: abrir
  /// uma e criar outra.
  final List<ChatQueueInfo> queues;
  final String? shownQueue;
  final ValueChanged<String>? onPickQueue;
  final VoidCallback? onNewQueue;

  @override
  Widget build(BuildContext context) {
    final agents = [
      for (final p in participants)
        if (p.isAgent) p,
    ];
    final shells = [
      for (final p in participants)
        if (!p.isAgent) p,
    ];
    return Container(
      width: width,
      margin: const EdgeInsets.fromLTRB(0, 10, 10, 10),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.white(0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.white(0.09)),
      ),
      child: ListView(
        children: [
          _title('AGENTES'),
          for (final p in agents)
            _Row(participant: p, focused: p.id == focused, onTap: onPick),
          if (shells.isNotEmpty) ...[
            const SizedBox(height: 10),
            _title('TERMINAIS'),
            for (final p in shells)
              _Row(participant: p, focused: p.id == focused, onTap: onPick),
          ],
          if (onPickQueue != null || onNewQueue != null) ...[
            const SizedBox(height: 10),
            _title('FILAS'),
            for (final queue in queues)
              _QueueRow(
                queue: queue,
                shown: queue.id == shownQueue,
                onTap: () => onPickQueue?.call(queue.id),
              ),
            if (onNewQueue != null) _NewQueueRow(onTap: onNewQueue!),
          ],
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              'Clique foca · Tab alterna entre agentes',
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.white(0.38),
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _title(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: AppColors.white(0.45),
        decoration: TextDecoration.none,
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.participant,
    required this.focused,
    required this.onTap,
  });

  final ChatParticipantInfo participant;
  final bool focused;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final who = ChatWho(
      id: participant.id,
      address: participant.address,
      isAgent: participant.isAgent,
    );
    final color = participant.isAgent
        ? ChatPalette.of(who)
        : AppColors.white(0.6);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: ValueKey('participant-${participant.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(participant.id),
        child: Container(
          height: 40,
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: focused ? color.withValues(alpha: 0.14) : null,
            borderRadius: BorderRadius.circular(10),
            border: focused
                ? Border.all(color: color.withValues(alpha: 0.5))
                : null,
          ),
          child: Row(
            children: [
              Text(
                participant.isAgent ? '✦' : '❯',
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      participant.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEBEBEB),
                        decoration: TextDecoration.none,
                      ),
                    ),
                    if (participant.role != null)
                      Text(
                        participant.role!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.white(0.45),
                          decoration: TextDecoration.none,
                        ),
                      ),
                  ],
                ),
              ),
              _Activity(participant),
            ],
          ),
        ),
      ),
    );
  }
}

/// O que o participante faz agora: spinner trabalhando, ponto laranja pedindo,
/// verde terminou.
class _Activity extends StatelessWidget {
  const _Activity(this.participant);

  final ChatParticipantInfo participant;

  @override
  Widget build(BuildContext context) {
    if (participant.isWorking) {
      return SpinnerBuilder(
        builder: (_, glyph) => Text(
          glyph,
          key: const ValueKey('activity-working'),
          style: TextStyle(
            fontFamily: 'Menlo',
            fontSize: 12,
            color: AppColors.white(0.6),
            decoration: TextDecoration.none,
          ),
        ),
      );
    }
    final color = ActivityColors.of(participant.tone);
    if (color == null) return const SizedBox.shrink();
    return Text(
      '●',
      key: ValueKey('activity-${participant.activity}'),
      style: TextStyle(
        fontSize: 12,
        color: color,
        decoration: TextDecoration.none,
      ),
    );
  }
}

/// Uma fila na coluna: não é participante — ninguém "fala" com ela pelo
/// composer; o clique abre a lista dela ao lado da conversa.
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.queue,
    required this.shown,
    required this.onTap,
  });

  final ChatQueueInfo queue;
  final bool shown;
  final VoidCallback onTap;

  static const _teal = Color(0xFF40C8E0);

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      key: ValueKey('queue-${queue.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: shown ? _teal.withValues(alpha: 0.06) : null,
          borderRadius: BorderRadius.circular(10),
          border: shown
              ? Border.all(color: _teal.withValues(alpha: 0.45))
              : null,
        ),
        child: Row(
          children: [
            const Text(
              '☑',
              style: TextStyle(
                fontSize: 13,
                color: _teal,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    queue.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.white(0.92),
                      decoration: TextDecoration.none,
                    ),
                  ),
                  Text(
                    queue.summary,
                    key: ValueKey('queue-summary-${queue.id}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: queue.asking
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: queue.asking
                          ? AppColors.attention
                          : AppColors.white(0.5),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// O "+ Nova fila": sem ele, bancada sem fila teria de voltar ao canvas para
/// começar uma.
class _NewQueueRow extends StatelessWidget {
  const _NewQueueRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      key: const ValueKey('new-queue'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: Text(
          '+  Nova fila',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.white(0.55),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
  );
}
