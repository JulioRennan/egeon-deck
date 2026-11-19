import 'package:flutter/widgets.dart';

import '../../../../../commons/widgets/app_tooltip.dart';
import '../../../../../commons/widgets/context_menu.dart';
import '../../../../../commons/widgets/hand_cursor.dart';
import '../../../../../commons/widgets/spinner.dart';
import '../../../../../theme/app_colors.dart';
import '../../domain/entities/card_activity.dart';

/// A cor de cada tom do estado.
abstract final class ActivityColors {
  static const red = Color(0xFFFF453A);

  static Color? of(ActivityTone? tone) => switch (tone) {
    ActivityTone.green => AppColors.done,
    ActivityTone.orange => AppColors.attention,
    ActivityTone.red => red,
    null => null,
  };
}

/// O texto de estado do cabeçalho: o glifo (que anima), o rótulo e a fila, na
/// cor do tom — "⠋ trabalhando  ·  2 na fila". Vazio, não ocupa nada. Numa
/// tentativa agendada, com [onRetry], vira botão: "Tentar agora" ou "Cancelar
/// tentativa" (ADR-072). Fora disso não pega gesto: o arrasto do cabeçalho
/// passa por ele.
class CardStatus extends StatelessWidget {
  const CardStatus({required this.activity, this.onRetry, super.key});

  final CardActivity activity;

  /// Só agente tem tentativa agendada; nulo, o estado só mostra.
  final void Function({required bool now})? onRetry;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;
    final line = _line();
    if (retry == null || activity.state != 'retrying') {
      return IgnorePointer(child: line);
    }
    return AppTooltip(
      message: 'Clique para tentar agora ou cancelar',
      child: HandCursor(
        child: GestureDetector(
          key: const ValueKey('card-retry'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => showContextMenu(
            context,
            position: details.globalPosition,
            entries: [
              MenuEntry('Tentar agora', () => retry(now: true)),
              MenuEntry('Cancelar tentativa', () => retry(now: false)),
            ],
          ),
          child: line,
        ),
      ),
    );
  }

  Widget _line() {
    final text = activity.text;
    if (text.isEmpty && activity.glyph == null) return const SizedBox.shrink();
    final color = ActivityColors.of(activity.tone) ?? AppColors.white(0.62);
    Widget line(String glyph) => Text(
      [if (glyph.isNotEmpty) glyph, text].join(' '),
      key: const ValueKey('card-status'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w500,
        decoration: TextDecoration.none,
      ),
    );
    return switch (activity.glyph) {
      ActivityGlyph.spinner => SpinnerBuilder(
        builder: (_, glyph) => line(glyph),
      ),
      ActivityGlyph.hourglass => SpinnerBuilder(
        hourglass: true,
        builder: (_, glyph) => line(glyph),
      ),
      ActivityGlyph.dot => line('●'),
      ActivityGlyph.retry => line('↻'),
      ActivityGlyph.cross => line('✗'),
      null => line(''),
    };
  }
}
