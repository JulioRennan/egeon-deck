import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// Uma linha do menu: ação, ou separador.
class MenuEntry {
  const MenuEntry(this.label, this.onSelected, {this.leading})
    : isSeparator = false;

  const MenuEntry.separator()
    : label = '',
      onSelected = null,
      leading = null,
      isSeparator = true;

  final String label;
  final VoidCallback? onSelected;

  /// Marca à esquerda do rótulo (a bolinha da cor da bancada, por exemplo).
  final Widget? leading;
  final bool isSeparator;
}

/// Abre um menu sobre a tela, no ponto pedido. Precisa de um `Overlay` acima
/// de [context]; o menu fecha ao escolher, ao clicar fora ou com Esc.
void showContextMenu(
  BuildContext context, {
  required Offset position,
  required List<MenuEntry> entries,
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  void dismiss() => entry.remove();
  entry = OverlayEntry(
    builder: (_) =>
        _MenuLayer(position: position, entries: entries, onDismiss: dismiss),
  );
  overlay.insert(entry);
}

class _MenuLayer extends StatelessWidget {
  const _MenuLayer({
    required this.position,
    required this.entries,
    required this.onDismiss,
  });

  final Offset position;
  final List<MenuEntry> entries;
  final VoidCallback onDismiss;

  static const width = 240.0;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final height = entries.fold<double>(
      8,
      (total, e) => total + (e.isSeparator ? 9 : 26),
    );
    final left = position.dx.clamp(
      8.0,
      (screen.width - width - 8).clamp(8.0, double.infinity),
    );
    final top = position.dy.clamp(
      8.0,
      (screen.height - height - 8).clamp(8.0, double.infinity),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => onDismiss(),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: width,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2C),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.white(0.10)),
              boxShadow: [
                BoxShadow(color: AppColors.black(0.45), blurRadius: 16),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in entries)
                    e.isSeparator
                        ? Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            color: AppColors.white(0.10),
                          )
                        : _MenuRow(
                            entry: e,
                            onPick: () {
                              onDismiss();
                              e.onSelected?.call();
                            },
                          ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({required this.entry, required this.onPick});

  final MenuEntry entry;
  final VoidCallback onPick;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovering = true),
    onExit: (_) => setState(() => _hovering = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPick,
      child: Container(
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: _hovering ? AppColors.accent : null,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            if (widget.entry.leading != null) ...[
              widget.entry.leading!,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                widget.entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.textStyle.copyWith(
                  fontSize: 13,
                  color: const Color(0xFFFFFFFF),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
