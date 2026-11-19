import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../../commons/widgets/app_tooltip.dart';
import '../../../../../theme/app_colors.dart';
import '../../../../../theme/app_theme.dart';

/// O subtítulo do card (a pasta). Sem ⌘ é cabeçalho, por onde se arrasta o
/// card; com ⌘ sobre ele vira link — sublinhado e mão — e o clique abre a pasta
/// no Finder, como o caminho dentro do terminal (`NodeView.swift`). Sem
/// [onOpen] (o web, cujo subtítulo é a página), só mostra.
class SubtitleLink extends StatefulWidget {
  const SubtitleLink({required this.text, this.onOpen, super.key});

  final String text;
  final VoidCallback? onOpen;

  @override
  State<SubtitleLink> createState() => _SubtitleLinkState();
}

class _SubtitleLinkState extends State<SubtitleLink> {
  var _hovering = false;
  var _command = false;

  bool _onKey(KeyEvent event) {
    // A tecla do próprio evento: o conjunto de teclas apertadas pode ainda não
    // ter mudado quando o aviso chega.
    final key = event.logicalKey;
    final command =
        key == LogicalKeyboardKey.metaLeft ||
            key == LogicalKeyboardKey.metaRight
        ? event is! KeyUpEvent
        : HardwareKeyboard.instance.isMetaPressed;
    if (command != _command && mounted) setState(() => _command = command);
    return false;
  }

  @override
  void initState() {
    super.initState();
    _command = HardwareKeyboard.instance.isMetaPressed;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.onOpen;
    final linked = open != null && _command && _hovering;
    final text = IgnorePointer(
      child: Text(
        widget.text,
        key: const ValueKey('card-subtitle'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.textStyle.copyWith(
          fontSize: 10,
          fontFamily: AppTheme.terminalFontFamily,
          color: AppColors.white(linked ? 0.85 : 0.58),
          decoration: linked ? TextDecoration.underline : TextDecoration.none,
          decorationColor: AppColors.white(0.85),
        ),
      ),
    );
    return AppTooltip(
      message: open == null
          ? widget.text
          : '${widget.text}  —  ⌘-clique abre no Finder',
      passThrough: true,
      child: MouseRegion(
        // Translúcida para saber do mouse sem ⌘; quem decide se o clique passa
        // é o Listener de dentro (`opaque: false` aqui deixaria passar sempre).
        hitTestBehavior: HitTestBehavior.translucent,
        cursor: linked ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Listener(
          // Com ⌘, o clique é do link e não chega ao arrasto do cabeçalho.
          behavior: open != null && _command
              ? HitTestBehavior.opaque
              : HitTestBehavior.translucent,
          onPointerDown: (e) {
            if (open != null &&
                e.buttons == kPrimaryButton &&
                HardwareKeyboard.instance.isMetaPressed) {
              open();
            }
          },
          child: text,
        ),
      ),
    );
  }
}
