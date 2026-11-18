import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';

/// A pastilha de um workspace: o ícone que ele tem, ou a inicial do nome.
class WorkspaceBadge extends StatelessWidget {
  const WorkspaceBadge({
    required this.name,
    this.iconPath,
    this.side = 28,
    this.selected = false,
    this.wantsAttention = false,
    super.key,
  });

  final String name;

  /// Caminho do arquivo de ícone, quando o workspace tem um.
  final String? iconPath;
  final double side;
  final bool selected;
  final bool wantsAttention;

  String get _initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '' : trimmed.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular((side * 0.27).roundToDouble());
    final letter = Center(
      child: Text(
        _initial,
        style: TextStyle(
          fontSize: (side * 0.5).roundToDouble(),
          fontWeight: FontWeight.w600,
          color: selected ? const Color(0xFFFFFFFF) : AppColors.white(0.75),
          decoration: TextDecoration.none,
        ),
      ),
    );
    final path = iconPath;
    final image = path == null
        ? null
        : Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => letter,
          );
    return Container(
      width: side,
      height: side,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: image != null
            ? null
            : (selected
                  ? AppColors.accent.withValues(alpha: 0.85)
                  : AppColors.white(0.10)),
        border: wantsAttention
            ? Border.all(color: AppColors.attention, width: 2)
            : null,
      ),
      child: image ?? letter,
    );
  }
}
