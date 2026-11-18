import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../../theme/app_colors.dart';

/// A barra de endereço: uma linha, Enter vai, Esc devolve o que a página
/// mostra. Enquanto você digita, a página não mexe no texto.
class AddressField extends StatefulWidget {
  const AddressField({
    required this.address,
    required this.onSubmit,
    super.key,
  });

  /// O endereço da página agora.
  final String address;
  final ValueChanged<String> onSubmit;

  @override
  State<AddressField> createState() => _AddressFieldState();
}

class _AddressFieldState extends State<AddressField> {
  late final _controller = TextEditingController(text: widget.address);
  final _focus = FocusNode(debugLabel: 'address');

  @override
  void didUpdateWidget(AddressField old) {
    super.didUpdateWidget(old);
    if (widget.address != old.address && !_focus.hasFocus) {
      _controller.text = widget.address;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onSubmit(_controller.text);
      _focus.unfocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _controller.text = widget.address;
      _focus.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 20,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      color: const Color(0xFF171717),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Focus(
      onKeyEvent: _onKey,
      skipTraversal: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: EditableText(
          key: const ValueKey('address-field'),
          controller: _controller,
          focusNode: _focus,
          style: TextStyle(
            color: AppColors.white(0.85),
            fontSize: 10,
            fontFamily: 'Menlo',
            decoration: TextDecoration.none,
          ),
          cursorColor: AppColors.white(0.9),
          backgroundCursorColor: AppColors.white(0.2),
          selectionColor: AppColors.accent.withValues(alpha: 0.4),
          maxLines: 1,
          keyboardType: TextInputType.url,
          onSubmitted: (_) {},
        ),
      ),
    ),
  );
}
