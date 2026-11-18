import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/adapters/injector.dart';
import '../../domain/entities/agent_status.dart';
import '../cubit/agent_cubit.dart';
import 'agent_strip.dart';

/// A faixa de um card de agente, presa ao nó: um cubit por agente. Antes de o
/// core mandar o primeiro estado, a faixa fica vazia.
class AgentAccessory extends StatelessWidget {
  const AgentAccessory({
    required this.workbenchId,
    required this.nodeId,
    this.onRequestClear,
    this.tint = const Color(0xFFBF5AF2),
    super.key,
  });

  /// A bancada do nó: os comandos do agente vão por ela.
  final String workbenchId;
  final String nodeId;
  final Color tint;

  /// Limpar apaga a conversa: quem compõe a tela confirma antes de chamar
  /// `confirm`. Sem ouvinte, limpa direto.
  final void Function(VoidCallback confirm)? onRequestClear;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      key: ValueKey((workbenchId, nodeId)),
      create: (_) =>
          inject<AgentCubit>((workbenchId: workbenchId, nodeId: nodeId)),
      child: BlocBuilder<AgentCubit, AgentState>(
        builder: (context, state) => switch (state) {
          AgentWaiting() => const SizedBox.shrink(),
          AgentShown(:final status) => _strip(
            context.read<AgentCubit>(),
            status,
          ),
        },
      ),
    );
  }

  Widget _strip(AgentCubit cubit, AgentStatus status) => AgentStrip(
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
}
