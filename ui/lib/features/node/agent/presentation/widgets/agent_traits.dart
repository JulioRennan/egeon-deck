import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/adapters/injector.dart';
import '../../../../../theme/egeon_colors.dart';
import '../../../../../theme/egeon_type.dart';
import '../cubit/agent_cubit.dart';
import '../../../../../commons/utils/effort_names.dart';

/// "Opus 5.5 · médio": o modelo e o esforço de um agente, lidos do mesmo
/// estado que a faixa do card mostra. Sem estado do core ainda, não desenha
/// nada. Quem junta isto a outra feature (o composer do chat) é a home.
class AgentTraits extends StatelessWidget {
  const AgentTraits({
    required this.workbenchId,
    required this.nodeId,
    super.key,
  });

  final String workbenchId;
  final String nodeId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey('$workbenchId/$nodeId'),
    create: (_) =>
        inject<AgentCubit>((workbenchId: workbenchId, nodeId: nodeId)),
    child: BlocBuilder<AgentCubit, AgentState>(
      builder: (context, state) {
        if (state is! AgentShown) return const SizedBox.shrink();
        final status = state.status;
        final effort = status.dial.label;
        final text = [
          status.modelTitle,
          if (effort.isNotEmpty) effortName(effort),
        ].join(' · ');
        return Text(
          text,
          key: const ValueKey('composer-traits'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: EgeonType.monoMeta.copyWith(
            color: context.eg.textMuted,
            decoration: TextDecoration.none,
          ),
        );
      },
    ),
  );
}
