import '../../../../core/adapters/injector.dart';
import '../domain/repository/agent_repository.dart';
import '../domain/repository/node_form_repository.dart';
import '../domain/repository/socket_node_form_repository.dart';
import '../domain/usecase/list_components.dart';
import '../domain/usecase/node_form_actions.dart';
import '../domain/repository/socket_agent_repository.dart';
import '../domain/usecase/choose_agent_option.dart';
import '../domain/usecase/clear_agent.dart';
import '../domain/usecase/retry_agent.dart';
import '../domain/usecase/watch_agent.dart';
import '../presentation/cubit/agent_cubit.dart';
import '../presentation/cubit/node_form_cubit.dart';

/// Cada comando do agente leva a bancada: um repositório por bancada. O do
/// formulário de terminal manda a bancada em cada pedido: um só.
void registerAgentRepositories() {
  Injector.factoryParam<AgentRepository, String>(
    (workbenchId) => SocketAgentRepository(inject(), workbenchId),
  );
  Injector.factory<NodeFormRepository>(
    () => SocketNodeFormRepository(inject()),
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
  Injector.factoryParam<RetryAgent, String>(
    (workbenchId) => RetryAgent(inject(workbenchId)),
  );
  Injector.factoryParam<AgentCubit, BenchNode>(
    (node) => AgentCubit(
      nodeId: node.nodeId,
      watch: inject(node.workbenchId),
      choose: inject(node.workbenchId),
      clear: inject(node.workbenchId),
    ),
  );

  Injector.factory(() => NodeFormActions(inject()));
  Injector.factory(() => ListComponents(inject()));
  Injector.factoryParam<NodeFormCubit, NodeFormTarget>(
    (target) => NodeFormCubit(target: target, actions: inject()),
  );
}
