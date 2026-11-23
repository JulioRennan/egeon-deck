import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'eg_icon.dart';
import 'field.dart';
import 'menu.dart';
import 'pressable.dart';

class SelectOption<T> {
  const SelectOption(
    this.value,
    this.label, {
    this.desc,
    this.disabled = false,
  });

  final T value;
  final String label;
  final String? desc;
  final bool disabled;
}

/// Lista de escolha única: o gatilho parece um campo e abre um menu (de vidro)
/// com a opção atual marcada, na largura do gatilho.
class Select<T> extends StatefulWidget {
  const Select({
    required this.options,
    required this.onChanged,
    this.value,
    this.label,
    this.placeholder = 'Selecionar…',
    this.icon,
    this.error,
    this.hint,
    this.enabled = true,
    this.width,
    super.key,
  });

  final List<SelectOption<T>> options;
  final T? value;

  /// Nulo desabilita.
  final ValueChanged<T>? onChanged;
  final String? label;
  final String placeholder;
  final EgIconData? icon;
  final String? error;
  final String? hint;
  final bool enabled;
  final double? width;

  @override
  State<Select<T>> createState() => _SelectState<T>();
}

class _SelectState<T> extends State<Select<T>> {
  bool _open = false;

  void _show(BuildContext triggerContext) {
    final box = triggerContext.findRenderObject()! as RenderBox;
    setState(() => _open = true);
    showMenu(
      triggerContext,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      width: box.size.width,
      onClosed: () {
        if (mounted) setState(() => _open = false);
      },
      items: [
        for (final o in widget.options)
          MenuItem(
            o.label,
            desc: o.desc,
            checked: o.value == widget.value,
            onSelected: o.disabled
                ? null
                : () => widget.onChanged?.call(o.value),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final enabled = widget.enabled && widget.onChanged != null;
    SelectOption<T>? current;
    for (final o in widget.options) {
      if (o.value == widget.value) current = o;
    }
    return Field(
      label: widget.label,
      hint: widget.hint,
      error: widget.error,
      width: widget.width,
      child: Builder(
        builder: (triggerContext) => Pressable(
          onPressed: enabled ? () => _show(triggerContext) : null,
          semanticLabel: widget.label ?? widget.placeholder,
          builder: (context, s) => InputShell(
            hovered: s.hovered,
            focused: s.focused || _open,
            error: widget.error != null,
            enabled: enabled,
            child: Row(
              children: [
                if (widget.icon != null) ...[
                  EgIcon(
                    widget.icon!,
                    color: enabled ? c.textMuted : c.textDisabled,
                  ),
                  const SizedBox(width: EgeonSpace.s2),
                ],
                Expanded(
                  child: Text(
                    current?.label ?? widget.placeholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EgeonType.body.copyWith(
                      height: 20 / 14,
                      color: !enabled
                          ? c.textDisabled
                          : current == null
                          ? c.textMuted
                          : c.textPrimary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(width: EgeonSpace.s2),
                EgIcon(
                  EgIcons.chevronDown,
                  size: EgeonSize.iconSm,
                  color: enabled ? c.textMuted : c.textDisabled,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
