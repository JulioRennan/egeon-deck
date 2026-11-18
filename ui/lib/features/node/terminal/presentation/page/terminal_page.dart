import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../commons/widgets/file_drop_target.dart';
import '../cubit/terminal_cubit.dart';
import '../widgets/terminal_view.dart';

/// Liga o [TerminalView] ao cubit do terminal. O cubit vem de cima: quem
/// compõe a tela decide qual nó mostrar.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, this.autofocus = true});

  /// Vários terminais no canvas: só um nasce com o foco, e o clique move.
  final bool autofocus;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _focus = FocusNode(debugLabel: 'terminal');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TerminalCubit>();
    return FileDropTarget(
      onFiles: (paths) {
        cubit.dropFiles(paths);
        // Soltar leva o foco ao terminal: o próximo gesto já é dele.
        _focus.requestFocus();
      },
      // Imagem sem arquivo (print arrastado): vai em PNG, e o foco também.
      onImage: (png) {
        cubit.dropImage(png);
        _focus.requestFocus();
      },
      child: _view(cubit),
    );
  }

  Widget _view(TerminalCubit cubit) {
    return TerminalView(
      focusNode: _focus,
      frames: cubit.frames,
      initialFrame: cubit.lastFrame,
      onKey: cubit.sendKey,
      onText: cubit.sendText,
      onPaste: cubit.paste,
      onResize: cubit.resize,
      autofocus: widget.autofocus,
      effects: cubit.effects,
      onPointer: cubit.pointer,
      onScroll: cubit.scroll,
      onSelectAll: cubit.selectAll,
      onCopy: cubit.copy,
      onClipboardResponse: cubit.sendClipboard,
      onLinkHover: cubit.linkHover,
    );
  }
}
