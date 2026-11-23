import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/pressable.dart';
import '../../../../commons/widgets/eg/status.dart';
import '../../../../commons/widgets/eg/status_dot.dart';
import '../../../../commons/widgets/eg/tooltip.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_type.dart';
import '../../../node/card/domain/entities/card_activity.dart'
    show ActivityTone;
import '../../domain/entities/chat_block.dart';
import '../../domain/entities/chat_participant.dart';
import '../../domain/entities/chat_queue.dart';
import 'chat_palette.dart';

/// A coluna de quem está na conversa (`Participant` do DS): "Participantes",
/// cada agente com o nome na cor, o endereço em mono e o estado em ponto; os
/// terminais depois; e as filas de prompts como participantes à parte. O clique
/// põe em foco — é para o focado que o composer manda.
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

  static const width = 232.0;

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
    final c = context.eg;
    final agents = [
      for (final p in participants)
        if (p.isAgent) p,
    ];
    final shells = [
      for (final p in participants)
        if (!p.isAgent) p,
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: c.lineSubtle)),
      ),
      child: SizedBox(
        width: width,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Text(
                'Participantes',
                style: EgeonType.caption.copyWith(
                  color: c.textMuted,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            for (final p in agents)
              _Row(participant: p, focused: p.id == focused, onTap: onPick),
            for (final p in shells)
              _Row(participant: p, focused: p.id == focused, onTap: onPick),
            if (onPickQueue != null || onNewQueue != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 10,
                ),
                child: SizedBox(
                  height: 1,
                  child: ColoredBox(color: c.lineSubtle),
                ),
              ),
              for (final queue in queues)
                _QueueRow(
                  queue: queue,
                  shown: queue.id == shownQueue,
                  onTap: () => onPickQueue?.call(queue.id),
                ),
              if (onNewQueue != null) _NewQueueRow(onTap: onNewQueue!),
            ],
          ],
        ),
      ),
    );
  }
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

  Status get _status {
    if (participant.isDead) return Status.dead;
    if (participant.isWorking) return Status.running;
    if (participant.needsAttention ||
        participant.tone == ActivityTone.orange ||
        participant.statusTone == StatusTone.orange) {
      return Status.attention;
    }
    if (participant.tone == ActivityTone.red ||
        participant.statusTone == StatusTone.red) {
      return Status.danger;
    }
    if (participant.tone == ActivityTone.green) return Status.success;
    return Status.idle;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final who = ChatWho(
      id: participant.id,
      address: participant.address,
      isAgent: participant.isAgent,
    );
    final color = participant.isAgent ? ChatPalette.of(c, who) : c.textPrimary;
    final status = _status;
    final label = participant.status.isEmpty
        ? status.label
        : participant.status;
    // Terminal fechado fica na coluna, mas não recebe: sem mão e sem clique.
    final dead = participant.isDead;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Pressable(
        key: ValueKey('participant-${participant.id}'),
        onPressed: dead ? null : () => onTap(participant.id),
        semanticLabel: '${participant.id}, $label',
        builder: (context, s) => DecoratedBox(
          decoration: BoxDecoration(
            color: focused
                ? EgeonColors.overlay4
                : s.hovered && !dead
                ? EgeonColors.overlay4
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        participant.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EgeonType.label.copyWith(
                          fontSize: 13,
                          height: 18 / 13,
                          fontWeight: FontWeight.w600,
                          color: color,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        participant.address,
                        key: ValueKey('participant-address-${participant.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EgeonType.monoMeta.copyWith(
                          fontSize: 11,
                          height: 15 / 11,
                          color: c.textMuted,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      // Só a falha escreve embaixo (o motivo importa); o papel e
                      // o "precisa de você" ficam no ícone do canto (v3).
                      if (participant.statusTone == StatusTone.red &&
                          participant.status.isNotEmpty)
                        Text(
                          participant.status,
                          key: ValueKey('participant-status-${participant.id}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: EgeonType.caption.copyWith(
                            fontSize: 11,
                            color: c.danger,
                            decoration: TextDecoration.none,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: label,
                  child: KeyedSubtree(
                    key: ValueKey('activity-${participant.activity}'),
                    // Concluído é um ✓ verde (a v3); os outros estados ficam
                    // como o StatusDot os desenha.
                    child: status == Status.success
                        ? SizedBox(
                            width: 12,
                            height: 12,
                            child: EgIcon(
                              EgIcons.check,
                              size: 12,
                              color: c.success,
                            ),
                          )
                        : StatusDot(status, animated: true),
                  ),
                ),
              ],
            ),
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Pressable(
        key: ValueKey('queue-${queue.id}'),
        onPressed: onTap,
        semanticLabel: 'Fila ${queue.id}',
        builder: (context, s) => DecoratedBox(
          decoration: BoxDecoration(
            color: shown
                ? c.steel
                : s.hovered
                ? EgeonColors.overlay4
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        queue.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EgeonType.label.copyWith(
                          fontSize: 13,
                          height: 18 / 13,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      Text(
                        queue.summary,
                        key: ValueKey('queue-summary-${queue.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EgeonType.monoMeta.copyWith(
                          fontSize: 11,
                          height: 15 / 11,
                          color: queue.asking ? c.attention : c.textMuted,
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
      ),
    );
  }
}

/// O "+ Nova fila": sem ele, bancada sem fila teria de voltar ao canvas para
/// começar uma.
class _NewQueueRow extends StatelessWidget {
  const _NewQueueRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Pressable(
      key: const ValueKey('new-queue'),
      onPressed: onTap,
      semanticLabel: 'Nova fila',
      builder: (context, s) => SizedBox(
        height: 32,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              EgIcon(
                EgIcons.plus,
                size: 14,
                color: s.hovered ? c.textPrimary : c.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Nova fila',
                style: EgeonType.label.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: s.hovered ? c.textPrimary : c.textSecondary,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
