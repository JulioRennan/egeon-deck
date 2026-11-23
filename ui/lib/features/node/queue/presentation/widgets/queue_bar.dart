import 'package:flutter/widgets.dart';

import '../../../../../commons/widgets/eg/checkbox.dart';
import '../../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../../commons/widgets/eg/icon_button.dart';
import '../../../../../commons/widgets/eg/menu.dart';
import '../../../../../commons/widgets/hand_cursor.dart';
import '../../../../../theme/egeon_colors.dart';
import '../../../../../theme/egeon_type.dart';
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
      color: context.eg.carbon,
      child: Row(
        children: [
          Text(
            'para',
            style: EgeonType.small.copyWith(
              color: context.eg.textMuted,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: _TargetPicker(
              label: current?.label ?? 'ninguém ligado',
              enabled: targets.length > 1,
              onTap: (anchor) => showMenu(
                context,
                anchor: anchor,
                items: [
                  for (final t in targets)
                    MenuItem(
                      t.label,
                      checked: t.id == destination,
                      onSelected: () => onTarget(t.id),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _AutoBox(on: queue.auto, onChanged: onAuto),
          const SizedBox(width: 8),
          IconButton(
            key: const ValueKey('send-next'),
            icon: EgIcons.send,
            tooltip: 'Mandar a próxima',
            compact: true,
            onPressed: onSendNext,
          ),
          IconButton(
            key: const ValueKey('clear-done'),
            icon: EgIcons.check,
            tooltip: 'Tirar as feitas',
            compact: true,
            onPressed: onClearDone,
          ),
          if (onClose != null)
            IconButton(
              key: const ValueKey('queue-close'),
              icon: EgIcons.x,
              tooltip: 'Fechar',
              compact: true,
              onPressed: onClose!,
            ),
        ],
      ),
    );
  }
}

class _TargetPicker extends StatelessWidget {
  const _TargetPicker({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final ValueChanged<Rect> onTap;

  @override
  Widget build(BuildContext context) => HandCursor(
    enabled: enabled,
    child: GestureDetector(
      key: const ValueKey('queue-target'),
      behavior: HitTestBehavior.opaque,
      onTap: enabled
          ? () {
              final box = context.findRenderObject()! as RenderBox;
              onTap(box.localToGlobal(Offset.zero) & box.size);
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
              style: EgeonType.small.copyWith(
                color: enabled ? context.eg.textPrimary : context.eg.textMuted,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          if (enabled) ...[
            const SizedBox(width: 4),
            EgIcon(EgIcons.chevronDown, size: 12, color: context.eg.textMuted),
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
  Widget build(BuildContext context) => Checkbox(
    key: const ValueKey('queue-auto'),
    checked: on,
    onChanged: onChanged,
    label: const Text('Automático'),
  );
}
