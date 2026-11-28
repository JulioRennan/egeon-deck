import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../theme/egeon_colors.dart';
import '../../theme/egeon_type.dart';

/// A inicial do workspace (ou a foto dele) num quadrado (26 na barra lateral).
class WorkspaceMark extends StatelessWidget {
  const WorkspaceMark({
    required this.name,
    this.iconPath,
    this.side = 26,
    super.key,
  });

  final String name;
  final String? iconPath;
  final double side;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? ''
        : trimmed.substring(0, 1).toUpperCase();
    final fallback = Center(
      child: Text(
        initial,
        style: EgeonType.caption.copyWith(
          fontSize: side * 0.46,
          letterSpacing: 0,
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
          decoration: TextDecoration.none,
        ),
      ),
    );
    return SizedBox(
      width: side,
      height: side,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.steelActive,
          borderRadius: BorderRadius.circular(7),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          // A inicial fica por baixo: aparece enquanto a foto carrega e se ela
          // não abre.
          child: Stack(
            fit: StackFit.expand,
            children: [
              fallback,
              if (iconPath != null)
                Image.file(
                  File(iconPath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
