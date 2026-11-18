import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/attention_ring.dart';
import '../../../../commons/widgets/spinner.dart';
import '../../../../core/domain/entities/activity_summary.dart';
import '../../../../theme/app_colors.dart';
import '../../domain/entities/workbench_tab.dart';

/// A pastilha de uma bancada aberta. Só desenha: clique, fechar e arrasto são
/// da faixa, que sabe a ordem das vizinhas.
class WorkbenchTabPill extends StatefulWidget {
  const WorkbenchTabPill({
    required this.tab,
    required this.onClose,
    this.lifted = false,
    super.key,
  });

  final WorkbenchTab tab;
  final VoidCallback onClose;

  /// Na mão, durante o arrasto: sobe com sombra.
  final bool lifted;

  static const height = 26.0;
  static const radius = 7.0;
  static const _labelStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    decoration: TextDecoration.none,
  );
  static const badgeStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    fontFamily: 'Menlo',
    decoration: TextDecoration.none,
  );

  /// Largura que a pastilha pede: o nome, o badge e a folga do ✕.
  static double fittingWidth(WorkbenchTab tab) {
    final label = _measure(TextSpan(text: tab.name, style: _labelStyle));
    final badge = badgeSpans(tab.summary, glyph: '⠋', hourglass: '⏳');
    final badgeWidth = badge.isEmpty
        ? 0.0
        : _measure(TextSpan(style: badgeStyle, children: badge)) + 6;
    return math.min(math.max(label + badgeWidth + 48, 110), 240);
  }

  static double _measure(TextSpan span) {
    final painter = TextPainter(text: span, textDirection: TextDirection.ltr)
      ..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// Os três avisos na ordem fixa — trabalhando, precisa de você, terminou —,
  /// porque ordenar por urgência faria a bolinha trocar de lugar.
  static List<InlineSpan> badgeSpans(
    ActivitySummary summary, {
    required String glyph,
    required String hourglass,
  }) {
    final spans = <InlineSpan>[];
    void add(String mark, int count, Color color) {
      if (count == 0) return;
      if (spans.isNotEmpty) spans.add(const TextSpan(text: ' '));
      spans.add(
        TextSpan(
          text: count > 1 ? '$mark$count' : mark,
          style: TextStyle(color: color),
        ),
      );
    }

    add(glyph, summary.starting, AppColors.white(0.3));
    add(glyph, summary.working, AppColors.white(0.6));
    add(hourglass, summary.background, AppColors.white(0.6));
    add('●', summary.attention, AppColors.attention);
    add('●', summary.done, AppColors.done);
    return spans;
  }

  @override
  State<WorkbenchTabPill> createState() => _WorkbenchTabPillState();
}

class _WorkbenchTabPillState extends State<WorkbenchTabPill> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final shadowed = tab.isActive || _hovering;
    final background = tab.isActive ? 0.16 : (_hovering ? 0.10 : 0.0);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Opacity(
        opacity: widget.lifted ? 0.96 : 1,
        child: AttentionRing(
          tone: AttentionTone.of(tab.summary),
          radius: WorkbenchTabPill.radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.white(background * 0.6),
              borderRadius: BorderRadius.circular(WorkbenchTabPill.radius),
              boxShadow: widget.lifted
                  ? [
                      BoxShadow(
                        color: AppColors.black(0.45),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tab.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WorkbenchTabPill._labelStyle.copyWith(
                        color: AppColors.white(tab.isActive ? 0.95 : 0.55),
                      ),
                    ),
                  ),
                  _Badge(summary: tab.summary),
                  const SizedBox(width: 4),
                  _CloseButton(visible: shadowed, onTap: widget.onClose),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.summary});

  final ActivitySummary summary;

  @override
  Widget build(BuildContext context) {
    if (WorkbenchTabPill.badgeSpans(
      summary,
      glyph: '',
      hourglass: '',
    ).isEmpty) {
      return const SizedBox.shrink();
    }
    // O relógio só roda quando há glifo que gira.
    final animated = summary.isWorking || summary.background > 0;
    Widget build(String glyph, String hourglass) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Text.rich(
        TextSpan(
          style: WorkbenchTabPill.badgeStyle,
          children: WorkbenchTabPill.badgeSpans(
            summary,
            glyph: glyph,
            hourglass: hourglass,
          ),
        ),
        maxLines: 1,
      ),
    );
    if (!animated) return build('', '');
    return SpinnerBuilder(
      builder: (_, glyph) => build(glyph, SpinnerGlyph.hourglass()),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 10,
    child: visible
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Text(
              '✕',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppColors.white(0.45),
                decoration: TextDecoration.none,
              ),
            ),
          )
        : null,
  );
}
