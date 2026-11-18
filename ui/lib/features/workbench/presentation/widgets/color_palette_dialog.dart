import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/app_dialog.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/workbench_palette.dart';

/// A grade das 24 cores. Devolve o nome da escolhida, ou `null` se fechou.
Future<String?> showColorPalette(BuildContext context, {String? current}) =>
    showAppDialog<String>(
      context,
      width: 14 * 2 + 6 * 26 + 5 * 10.0,
      builder: (_, close) => ColorPalette(current: current, onPick: close),
    );

class ColorPalette extends StatefulWidget {
  const ColorPalette({required this.current, required this.onPick, super.key});

  final String? current;
  final ValueChanged<String> onPick;

  static const columns = 6;
  static const side = 26.0;
  static const gap = 10.0;

  @override
  State<ColorPalette> createState() => _ColorPaletteState();
}

class _ColorPaletteState extends State<ColorPalette> {
  String? _hovered;

  String get _caption {
    final name = _hovered ?? widget.current;
    for (final swatch in WorkbenchPalette.all) {
      if (swatch.name == name) return swatch.label;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(14),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cor da bancada',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.white(0.6),
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: ColorPalette.gap,
          runSpacing: ColorPalette.gap,
          children: [
            for (final swatch in WorkbenchPalette.all)
              _Swatch(
                swatch: swatch,
                current: swatch.name == widget.current,
                onHover: (on) =>
                    setState(() => _hovered = on ? swatch.name : null),
                onTap: () => widget.onPick(swatch.name),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 16,
          child: Text(
            _caption,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFFFFFFF),
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Swatch extends StatefulWidget {
  const _Swatch({
    required this.swatch,
    required this.current,
    required this.onHover,
    required this.onTap,
  });

  final WorkbenchSwatch swatch;
  final bool current;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  @override
  State<_Swatch> createState() => _SwatchState();
}

class _SwatchState extends State<_Swatch> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final ring = widget.current || _hovering;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovering = true);
        widget.onHover(true);
      },
      onExit: (_) {
        setState(() => _hovering = false);
        widget.onHover(false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          key: ValueKey('swatch-${widget.swatch.name}'),
          width: ColorPalette.side,
          height: ColorPalette.side,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.white(widget.current ? 0.9 : 0.45),
              width: ring ? 2 : 0,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.swatch.color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
