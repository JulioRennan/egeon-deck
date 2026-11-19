import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/widgets/hand_cursor.dart';
import '../../../../theme/app_colors.dart';
import '../../domain/entities/usage_view.dart';
import '../cubit/usage_cubit.dart';
import 'usage_popover.dart';

/// O custo da bancada numa pastilha (ADR-085): na barra de ações do canvas e no
/// topo do chat. O clique abre o detalhe, ancorado nela.
class UsagePill extends StatefulWidget {
  const UsagePill({super.key});

  @override
  State<UsagePill> createState() => _UsagePillState();
}

class _UsagePillState extends State<UsagePill> {
  var _hovering = false;

  void _open(UsageView view) {
    final panel = view.panel;
    if (panel == null) return;
    final box = context.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero) & box.size;
    showUsagePopover(context, anchor: anchor, panel: panel);
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<UsageCubit, UsageState>(
    builder: (context, state) => _pill(switch (state) {
      UsageWaiting() => const UsageView(),
      UsageShown(:final view) => view,
    }),
  );

  Widget _pill(UsageView view) => HandCursor(
    child: MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        key: const ValueKey('usage-pill'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(view),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: AppColors.white(_hovering ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size.square(14),
                painter: _DollarPainter(AppColors.white(0.6)),
              ),
              const SizedBox(width: 6),
              Text(
                view.pill.text,
                key: const ValueKey('usage-pill-text'),
                maxLines: 1,
                style: TextStyle(
                  color: AppColors.white(0.85),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DollarPainter extends CustomPainter {
  _DollarPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    canvas.drawCircle(c, size.width / 2 - 0.7, stroke);
    final tp = TextPainter(
      text: TextSpan(
        text: r'$',
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_DollarPainter old) => old.color != color;
}
