import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repository/agent_repository.dart';
import '../../domain/usecase/choose_agent_option.dart';
import '../../domain/usecase/clear_agent.dart';
import '../../domain/usecase/watch_agent.dart';
import '../cubit/agent_cubit.dart';
import '../cubit/agent_state.dart';
import 'agent_strip.dart';

/// A faixa de um card de agente, presa ao nó: um cubit por agente. Antes de o
/// core mandar o primeiro estado, a faixa fica vazia.
class AgentAccessory extends StatelessWidget {
  const AgentAccessory({
    required this.nodeId,
    this.onRequestClear,
    this.tint = const Color(0xFFBF5AF2),
    super.key,
  });

  final String nodeId;
  final Color tint;

  /// Limpar apaga a conversa: quem compõe a tela confirma antes de chamar
  /// `confirm`. Sem ouvinte, limpa direto.
  final void Function(VoidCallback confirm)? onRequestClear;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<AgentRepository>();
    return BlocProvider(
      key: ValueKey(nodeId),
      create: (_) => AgentCubit(
        nodeId: nodeId,
        watch: WatchAgent(repository),
        choose: ChooseAgentOption(repository),
        clear: ClearAgent(repository),
      ),
      child: BlocBuilder<AgentCubit, AgentState>(
        builder: (context, state) {
          final status = state.status;
          if (status == null) return const SizedBox.shrink();
          final cubit = context.read<AgentCubit>();
          return AgentStrip(
            status: status,
            tint: tint,
            onModel: cubit.chooseModel,
            onEffortMove: cubit.moveEffort,
            onEffortAuto: cubit.toggleEffortAuto,
            onEffortSettle: cubit.settleEffort,
            onUltracode: (on) => cubit.setUltracode(on: on),
            onClear: () => onRequestClear != null
                ? onRequestClear!(cubit.clearConversation)
                : cubit.clearConversation(),
          );
        },
      ),
    );
  }
}
