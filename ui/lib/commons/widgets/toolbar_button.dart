import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';

/// Botão quadrado de barra: ícone no centro, fundo ao passar o ponteiro.
class ToolbarButton extends StatefulWidget {
  const ToolbarButton({
    required this.child,
    required this.onTap,
    this.size = 22,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;
  final double size;

  @override
  State<ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<ToolbarButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovering = true),
    onExit: (_) => setState(() => _hovering = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _hovering ? AppColors.white(0.10) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: widget.child,
      ),
    ),
  );
}
