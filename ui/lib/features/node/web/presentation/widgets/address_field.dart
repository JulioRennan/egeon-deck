import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../../commons/widgets/eg/text_field.dart';

/// A barra de endereço: um `TextField` mono de uma linha, Enter vai (pela tecla, num só lugar), Esc devolve
/// o que a página mostra. Enquanto você digita, a página não mexe no texto.
class AddressField extends StatefulWidget {
  const AddressField({
    required this.address,
    required this.onSubmit,
    this.loading = false,
    super.key,
  });

  /// O endereço da página agora.
  final String address;
  final ValueChanged<String> onSubmit;

  /// A página está carregando: o spinner do campo.
  final bool loading;

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
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _onKey,
    child: TextField(
      key: const ValueKey('address-field'),
      controller: _controller,
      focusNode: _focus,
      mono: true,
      icon: EgIcons.globe,
      loading: widget.loading,
      placeholder: 'Endereço ou busca',
    ),
  );
}
