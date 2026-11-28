import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../../commons/widgets/eg/tooltip.dart';
import '../../../../../commons/utils/path_names.dart';
import '../../../../../theme/egeon_colors.dart';
import '../../../../../theme/egeon_type.dart';
import '../../../../../commons/utils/app_shortcut.dart';

/// O caminho curto do cabeçalho: `~/…/a/b` quando passa de três partes.
/// Endereço (o nó web) e o que não é caminho ficam como estão.
String shortPath(String path) {
  if (!looksLikePath(path)) return path;
  final parts = splitPath(path);
  return parts.length > 3
      ? '~/…/${parts.sublist(parts.length - 2).join('/')}'
      : path;
}

/// O subtítulo do card (a pasta). Sem ⌘ é cabeçalho, por onde se arrasta o
/// card; com ⌘ sobre ele vira link — sublinhado e mão — e o clique abre a pasta
/// no Finder, como o caminho dentro do terminal (`NodeView.swift`). Sem
/// [onOpen] (o web, cujo subtítulo é a página), só mostra. A dica traz o
/// caminho inteiro.
class SubtitleLink extends StatefulWidget {
  const SubtitleLink({required this.text, this.onOpen, super.key});

  final String text;
  final VoidCallback? onOpen;

  @override
  State<SubtitleLink> createState() => _SubtitleLinkState();
}

class _SubtitleLinkState extends State<SubtitleLink> {
  /// Onde o clique no link abre: o Finder no macOS, a pasta nos outros.
  static String get _opensIn =>
      usesCommandKey ? 'abre no Finder' : 'abre a pasta';

  var _hovering = false;
  var _command = false;

  bool _onKey(KeyEvent event) {
    // A tecla do próprio evento: o conjunto de teclas apertadas pode ainda não
    // ter mudado quando o aviso chega.
    final key = event.logicalKey;
    final command = isPrimaryModifierKey(key)
        ? event is! KeyUpEvent
        : isPrimaryModifierPressed(HardwareKeyboard.instance);
    if (command != _command && mounted) setState(() => _command = command);
    return false;
  }

  @override
  void initState() {
    super.initState();
    _command = isPrimaryModifierPressed(HardwareKeyboard.instance);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final open = widget.onOpen;
    final linked = open != null && _command && _hovering;
    final color = linked ? c.textPrimary : c.textDisabled;
    final text = IgnorePointer(
      child: Text(
        shortPath(widget.text),
        key: const ValueKey('card-subtitle'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: EgeonType.monoMeta.copyWith(
          fontSize: 11,
          height: 14 / 11,
          color: color,
          decoration: linked ? TextDecoration.underline : TextDecoration.none,
          decorationColor: color,
        ),
      ),
    );
    return Tooltip(
      message: open == null
          ? widget.text
          : '${widget.text}  —  $primaryModifierName-clique $_opensIn',
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
                isPrimaryModifierPressed(HardwareKeyboard.instance)) {
              open();
            }
          },
          child: text,
        ),
      ),
    );
  }
}
