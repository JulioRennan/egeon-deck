import '../../../../core/adapters/injector.dart';
import '../domain/repository/agent_repository.dart';
import '../domain/repository/socket_agent_repository.dart';
import '../domain/usecase/choose_agent_option.dart';
import '../domain/usecase/clear_agent.dart';
import '../domain/usecase/watch_agent.dart';
import '../presentation/cubit/agent_cubit.dart';

/// Cada comando do agente leva a bancada: um repositório por bancada.
void registerAgentRepositories() {
  Injector.factoryParam<AgentRepository, String>(
    (workbenchId) => SocketAgentRepository(inject(), workbenchId),
  );
}

/// Os usecases são da bancada, como o repositório: pedem o id dela.
void registerAgentDomain() {
  Injector.factoryParam<WatchAgent, String>(
    (workbenchId) => WatchAgent(inject(workbenchId)),
  );
  Injector.factoryParam<ChooseAgentOption, String>(
    (workbenchId) => ChooseAgentOption(inject(workbenchId)),
  );
  Injector.factoryParam<ClearAgent, String>(
    (workbenchId) => ClearAgent(inject(workbenchId)),
  );
  Injector.factoryParam<AgentCubit, BenchNode>(
    (node) => AgentCubit(
      nodeId: node.nodeId,
      watch: inject(node.workbenchId),
      choose: inject(node.workbenchId),
      clear: inject(node.workbenchId),
    ),
  );
}
