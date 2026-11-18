import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repository/terminal_repository.dart';
import '../../domain/usecase/resize_terminal.dart';
import '../../domain/usecase/send_terminal_input.dart';
import '../../domain/usecase/watch_terminal.dart';
import '../../domain/usecase/watch_terminal_effects.dart';
import '../cubit/terminal_cubit.dart';
import '../page/terminal_page.dart';

/// O corpo de um card de terminal: um cubit por terminal, preso ao nó. Quem
/// compõe o canvas só diz qual nó mostrar; o cubit fecha a assinatura quando o
/// card sai da tela.
class TerminalBody extends StatelessWidget {
  const TerminalBody({required this.nodeId, this.autofocus = false, super.key});

  final String nodeId;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<TerminalRepository>();
    return BlocProvider(
      key: ValueKey(nodeId),
      create: (_) => TerminalCubit(
        nodeId: nodeId,
        watch: WatchTerminal(repository),
        input: SendTerminalInput(repository),
        resize: ResizeTerminal(repository),
        effects: WatchTerminalEffects(repository),
      ),
      child: TerminalPage(autofocus: autofocus),
    );
  }
}
