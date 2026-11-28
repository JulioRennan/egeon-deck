import 'package:flutter/widgets.dart';

import '../../theme/egeon_colors.dart';
import '../../theme/egeon_tokens.dart';
import '../../theme/egeon_type.dart';
import 'eg/checkbox.dart';
import 'eg/eg_icon.dart';
import 'eg/icon_button.dart' as eg;
import 'eg/pressable.dart';
import 'eg/radio.dart';
import 'eg/select.dart';
import 'eg/text_area.dart';
import 'eg/text_field.dart';

/// O rótulo de uma seção de formulário ("Branch da bancada", "Template"):
/// `caption` em `textSecondary`, acima do que descreve.
class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: EgeonType.caption.copyWith(
        color: context.eg.textSecondary,
        fontWeight: FontWeight.w500,
        decoration: TextDecoration.none,
      ),
    ),
  );
}

/// Campo de texto de formulário: uma linha (`TextField` do DS) ou, com
/// [maxLines] maior, várias (`TextArea`).
class FormTextField extends StatelessWidget {
  const FormTextField({
    required this.controller,
    this.placeholder,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.onKeyEvent,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    super.key,
  });

  final TextEditingController controller;
  final String? placeholder;
  final bool autofocus;
  final int maxLines;

  /// Linhas mínimas do campo de várias linhas.
  final int? minLines;

  /// Tecla antes do campo: devolver `handled` come o evento (o Enter que manda
  /// em vez de quebrar a linha).
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;
  final VoidCallback? onSubmitted;
  final ValueChanged<String>? onChanged;

  /// De fora, para quem compõe pôr o teclado no campo depois de um gesto.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final field = maxLines > 1
        ? TextArea(
            controller: controller,
            placeholder: placeholder,
            autofocus: autofocus,
            focusNode: focusNode,
            rows: minLines ?? maxLines,
            onChanged: onChanged,
          )
        : TextField(
            controller: controller,
            placeholder: placeholder,
            autofocus: autofocus,
            focusNode: focusNode,
            onChanged: onChanged,
            onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
          );
    if (onKeyEvent == null) return field;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => onKeyEvent!(event),
      child: field,
    );
  }
}

/// Abas lado a lado, uma marcada: o "Shell × Agente" e o "Criar do zero ×
/// Começar de outro" (`SegmentedControl` do DS, com as abas chamadas
/// `<prefixo>-<n>`).
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.keyPrefix = 'segment',
    super.key,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  /// As abas se chamam `<prefixo>-<n>`.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.obsidian,
        borderRadius: BorderRadius.circular(EgeonRadius.md),
        border: Border.all(color: c.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                child: Pressable(
                  key: ValueKey('$keyPrefix-$i'),
                  onPressed: () => onSelect(i),
                  semanticLabel: labels[i],
                  builder: (context, s) => DecoratedBox(
                    decoration: BoxDecoration(
                      color: i == selected
                          ? c.steelActive
                          : s.pressed
                          ? c.steel
                          : null,
                      borderRadius: BorderRadius.circular(EgeonRadius.sm),
                    ),
                    child: SizedBox(
                      height: 28,
                      child: Center(
                        child: Text(
                          labels[i],
                          style: EgeonType.label.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: i == selected
                                ? c.textPrimary
                                : s.hovered
                                ? c.textPrimary
                                : c.textMuted,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Uma opção de um grupo: só uma marcada por vez (`Radio` do DS).
class FormRadio extends StatelessWidget {
  const FormRadio({
    required this.label,
    required this.selected,
    required this.onTap,
    this.monospace = false,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool monospace;

  @override
  Widget build(BuildContext context) => Radio(
    checked: selected,
    onSelected: onTap,
    label: Text(
      label,
      style: monospace
          ? EgeonType.code.copyWith(decoration: TextDecoration.none)
          : null,
    ),
  );
}

/// Uma opção marcável (`Checkbox` do DS).
class FormCheckbox extends StatelessWidget {
  const FormCheckbox({
    required this.label,
    required this.on,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) =>
      Checkbox(checked: on, onChanged: onChanged, label: Text(label));
}

/// Um popup: mostra o item escolhido e, no clique, a lista para trocar
/// (`Select` do DS).
class PopupField extends StatelessWidget {
  const PopupField({
    required this.items,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  final List<String> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Select<int>(
    options: [for (var i = 0; i < items.length; i++) SelectOption(i, items[i])],
    value: items.isEmpty ? null : selected.clamp(0, items.length - 1),
    onChanged: onSelect,
  );
}

/// O "escolher outro" de um campo: um + ao lado do título, igual em todos.
class PlusButton extends StatelessWidget {
  const PlusButton({required this.tooltip, required this.onTap, super.key});

  /// O que o + escolhe ("Outra pasta").
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => eg.IconButton(
    icon: EgIcons.plus,
    tooltip: tooltip,
    compact: true,
    onPressed: onTap,
  );
}

/// Uma lista curta de textos em caixa com rolagem, de linhas selecionáveis. Um
/// toque marca ou desmarca a linha; o duplo toque avisa por [onOpen].
class PickList extends StatelessWidget {
  const PickList({
    required this.items,
    required this.selected,
    required this.onToggle,
    this.onOpen,
    this.height = 100,
    this.emptyText,
    this.keyPrefix = 'pick',
    super.key,
  });

  final List<String> items;
  final Set<int> selected;
  final ValueChanged<int> onToggle;
  final ValueChanged<int>? onOpen;
  final double height;
  final String? emptyText;

  /// As linhas se chamam `<prefixo>-<n>`: duas listas na mesma janela não se
  /// confundem.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.obsidian,
        borderRadius: BorderRadius.circular(EgeonRadius.md),
        border: Border.all(color: c.line),
      ),
      child: SizedBox(
        height: height,
        child: items.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  emptyText ?? '',
                  style: EgeonType.caption.copyWith(
                    color: c.textMuted,
                    decoration: TextDecoration.none,
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(4),
                itemCount: items.length,
                itemBuilder: (context, index) => GestureDetector(
                  key: ValueKey('$keyPrefix-$index'),
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: onOpen == null ? null : () => onOpen!(index),
                  child: Pressable(
                    onPressed: () => onToggle(index),
                    semanticLabel: items[index],
                    builder: (context, s) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected.contains(index)
                            ? c.accentSoft
                            : s.hovered
                            ? c.steel
                            : null,
                        borderRadius: BorderRadius.circular(EgeonRadius.sm),
                      ),
                      child: SizedBox(
                        height: 26,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              items[index],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: EgeonType.small.copyWith(
                                color: selected.contains(index)
                                    ? c.accent
                                    : c.textPrimary,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
