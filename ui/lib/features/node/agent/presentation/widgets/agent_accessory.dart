import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/adapters/injector.dart';
import '../../domain/entities/agent_status.dart';
import '../cubit/agent_cubit.dart';
import 'agent_strip.dart';

/// A faixa de um card de agente, presa ao nó: um cubit por agente. Antes de o
/// core mandar o primeiro estado, ela mostra o que se sabe (o CLI padrão, sem
/// nível de esforço nem contexto): a faixa nunca fica vazia.
class AgentAccessory extends StatelessWidget {
  const AgentAccessory({
    required this.workbenchId,
    required this.nodeId,
    this.onRequestClear,
    super.key,
  });

  /// A bancada do nó: os comandos do agente vão por ela.
  final String workbenchId;
  final String nodeId;

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
          AgentWaiting() => _strip(context.read<AgentCubit>(), _unknown),
          AgentShown(:final status) => _strip(
            context.read<AgentCubit>(),
            status,
          ),
        },
      ),
    );
  }

  /// O que se sabe antes do primeiro estado: limpar espera o core dizer que dá.
  static const _unknown = AgentStatus(clearable: false);

  Widget _strip(AgentCubit cubit, AgentStatus status) => AgentStrip(
    status: status,
    agentName: nodeId,
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
