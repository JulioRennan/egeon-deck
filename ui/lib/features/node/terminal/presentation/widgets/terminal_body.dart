import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/adapters/injector.dart';
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
    return BlocProvider(
      key: ValueKey(nodeId),
      create: (_) => inject<TerminalCubit>(nodeId),
      child: TerminalPage(autofocus: autofocus),
    );
  }
}
