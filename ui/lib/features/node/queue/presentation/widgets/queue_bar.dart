import 'package:flutter/widgets.dart';

import '../../../../../commons/widgets/context_menu.dart';
import '../../../../../commons/widgets/glyphs.dart';
import '../../../../../commons/widgets/hand_cursor.dart';
import '../../../../../commons/widgets/toolbar_button.dart';
import '../../../../../theme/app_colors.dart';
import '../../domain/entities/prompt_queue.dart';

/// A barra de cima da fila: para quem manda, o automático, mandar a próxima e
/// tirar da lista o que já foi.
class QueueBar extends StatelessWidget {
  const QueueBar({
    required this.queue,
    required this.onTarget,
    required this.onAuto,
    required this.onSendNext,
    required this.onClearDone,
    this.onClose,
    super.key,
  });

  final PromptQueue queue;
  final ValueChanged<String> onTarget;
  final ValueChanged<bool> onAuto;
  final VoidCallback onSendNext;
  final VoidCallback onClearDone;

  /// Só no painel ao lado da conversa: fechar o painel (a fila continua na
  /// bancada).
  final VoidCallback? onClose;

  static const height = 46.0;

  @override
  Widget build(BuildContext context) {
    final targets = queue.targets;
    final destination = queue.destination;
    final current = targets.where((t) => t.id == destination).firstOrNull;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF242424),
      child: Row(
        children: [
          Text(
            'para',
            style: TextStyle(
              color: AppColors.white(0.55),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: _TargetPicker(
              label: current?.label ?? 'ninguém ligado',
              enabled: targets.length > 1,
              onTap: (position) => showContextMenu(
                context,
                position: position,
                entries: [
                  for (final t in targets)
                    MenuEntry(t.label, () => onTarget(t.id)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _AutoBox(on: queue.auto, onChanged: onAuto),
          const SizedBox(width: 8),
          _BarButton(
            key: const ValueKey('send-next'),
            glyph: _Glyph.send,
            onTap: onSendNext,
          ),
          _BarButton(
            key: const ValueKey('clear-done'),
            glyph: _Glyph.check,
            onTap: onClearDone,
          ),
          if (onClose != null)
            ToolbarButton(
              key: const ValueKey('queue-close'),
              size: 28,
              onTap: onClose!,
              child: CustomPaint(
                size: const Size(10, 10),
                painter: _CrossPainter(AppColors.white(0.7)),
              ),
            ),
        ],
      ),
    );
  }
}

class _CrossPainter extends CustomPainter {
  const _CrossPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height)
      ..moveTo(size.width, 0)
      ..lineTo(0, size.height),
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round,
  );

  @override
  bool shouldRepaint(_CrossPainter old) => old.color != color;
}

class _TargetPicker extends StatelessWidget {
  const _TargetPicker({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final ValueChanged<Offset> onTap;

  @override
  Widget build(BuildContext context) => HandCursor(
    enabled: enabled,
    child: GestureDetector(
      key: const ValueKey('queue-target'),
      behavior: HitTestBehavior.opaque,
      onTap: enabled
          ? () {
              final box = context.findRenderObject()! as RenderBox;
              onTap(box.localToGlobal(Offset(0, box.size.height + 4)));
            }
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.white(enabled ? 0.9 : 0.6),
                fontSize: 13,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          if (enabled) ...[
            const SizedBox(width: 4),
            ChevronGlyph(
              ChevronDirection.down,
              color: AppColors.white(0.5),
              size: 10,
            ),
          ],
        ],
      ),
    ),
  );
}

class _AutoBox extends StatelessWidget {
  const _AutoBox({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => HandCursor(
    child: GestureDetector(
      key: const ValueKey('queue-auto'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!on),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: on ? AppColors.accent : null,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: on ? AppColors.accent : AppColors.white(0.4),
              ),
            ),
            child: on
                ? CustomPaint(painter: _TickPainter())
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 6),
          Text(
            'Automático',
            style: TextStyle(
              color: AppColors.white(0.85),
              fontSize: 13,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TickPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    Path()
      ..moveTo(size.width * 0.25, size.height * 0.52)
      ..lineTo(size.width * 0.43, size.height * 0.7)
      ..lineTo(size.width * 0.76, size.height * 0.3),
    Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round,
  );

  @override
  bool shouldRepaint(_TickPainter old) => false;
}

enum _Glyph { send, check }

class _BarButton extends StatefulWidget {
  const _BarButton({required this.glyph, required this.onTap, super.key});

  final _Glyph glyph;
  final VoidCallback onTap;

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovering = true),
    onExit: (_) => setState(() => _hovering = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: _hovering ? AppColors.white(0.10) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: CustomPaint(painter: _BarGlyphPainter(widget.glyph)),
      ),
    ),
  );
}

class _BarGlyphPainter extends CustomPainter {
  _BarGlyphPainter(this.glyph);

  final _Glyph glyph;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final stroke = Paint()
      ..color = AppColors.white(0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (glyph) {
      case _Glyph.send:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - 7, c.dy - 1)
            ..lineTo(c.dx + 7, c.dy - 7)
            ..lineTo(c.dx + 3, c.dy + 7)
            ..lineTo(c.dx - 1, c.dy + 1)
            ..close(),
          stroke,
        );
      case _Glyph.check:
        canvas
          ..drawCircle(c, 7.5, stroke)
          ..drawPath(
            Path()
              ..moveTo(c.dx - 3.5, c.dy)
              ..lineTo(c.dx - 1, c.dy + 3)
              ..lineTo(c.dx + 3.5, c.dy - 3),
            stroke,
          );
    }
  }

  @override
  bool shouldRepaint(_BarGlyphPainter old) => old.glyph != glyph;
}
