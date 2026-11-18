import 'package:flutter/widgets.dart';

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
/// cor do tom — "⠋ trabalhando  ·  2 na fila". Vazio, não ocupa nada.
class CardStatus extends StatelessWidget {
  const CardStatus({required this.activity, super.key});

  final CardActivity activity;

  @override
  Widget build(BuildContext context) {
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
