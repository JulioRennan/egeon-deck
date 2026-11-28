import 'package:flutter/widgets.dart';

import '../../../../../commons/widgets/eg/menu.dart';
import '../../../../../commons/widgets/eg/pressable.dart';
import '../../../../../commons/widgets/eg/status.dart';
import '../../../../../commons/widgets/eg/status_dot.dart';
import '../../../../../commons/widgets/eg/tooltip.dart';
import '../../domain/entities/card_activity.dart';

/// O estado de um card, em cinco, como o DS o desenha: o texto e o glifo vêm
/// do core ([CardActivity]); aqui se escolhe só qual dos cinco.
enum CardState {
  working('Trabalhando', Status.running),
  attention('Precisa de você', Status.attention),
  done('Concluído', Status.success),
  idle('Parado', Status.idle),
  error('Erro', Status.danger);

  const CardState(this.label, this.status);

  final String label;
  final Status status;

  static CardState of(CardActivity activity) {
    if (activity.needsAttention) return CardState.attention;
    if (activity.tone == ActivityTone.red ||
        activity.glyph == ActivityGlyph.cross) {
      return CardState.error;
    }
    if (activity.glyph == ActivityGlyph.spinner ||
        activity.glyph == ActivityGlyph.hourglass) {
      return CardState.working;
    }
    if (activity.tone == ActivityTone.green) return CardState.done;
    return CardState.idle;
  }
}

/// O ponto de estado do cabeçalho (spinner quando trabalha, halo quando pede
/// você). Com tentativa agendada vira botão: "Tentar agora" ou "Cancelar
/// tentativa" (ADR-072). A dica diz o texto que o core mandou; sem ele, o nome
/// do estado.
class CardStateDot extends StatelessWidget {
  const CardStateDot({required this.activity, this.onRetry, super.key});

  final CardActivity activity;

  /// Só agente tem tentativa agendada; nulo, o ponto só mostra.
  final void Function({required bool now})? onRetry;

  @override
  Widget build(BuildContext context) {
    final state = CardState.of(activity);
    final text = activity.text.isEmpty ? state.label : activity.text;
    final dot = StatusDot(state.status, animated: true);
    final retry = onRetry;
    if (retry == null || activity.state != 'retrying') {
      return Tooltip(message: text, child: dot);
    }
    return Tooltip(
      message: '$text — clique para tentar agora ou cancelar',
      child: Pressable(
        key: const ValueKey('card-retry'),
        semanticLabel: 'Tentativa agendada',
        onPressed: () {
          final box = context.findRenderObject()! as RenderBox;
          showMenu(
            context,
            anchor: box.localToGlobal(Offset.zero) & box.size,
            items: [
              MenuItem('Tentar agora', onSelected: () => retry(now: true)),
              MenuItem(
                'Cancelar tentativa',
                onSelected: () => retry(now: false),
              ),
            ],
          );
        },
        builder: (context, s) => dot,
      ),
    );
  }
}
