import 'package:egeon_deck/features/home/domain/repository/node_repositories.dart';
import 'package:egeon_deck/features/node/agent/domain/repository/agent_repository.dart';

import 'in_memory_queue_repository.dart';

import 'package:egeon_deck/features/node/queue/domain/repository/queue_repository.dart';

import 'in_memory_web_repository.dart';

import 'package:egeon_deck/features/node/web/domain/repository/web_repository.dart';

import 'fake_agent_repository.dart';

/// Os repositórios dos nós, falsos, e a conta de quantos conjuntos nasceram:
/// cada bancada na tela ganha o seu.
class FakeNodeRepositories implements NodeRepositories {
  final benches = <String>[];

  @override
  AgentRepository agent(String workbenchId) {
    benches.add(workbenchId);
    return FakeAgentRepository();
  }

  @override
  QueueRepository queue(String workbenchId) => InMemoryQueueRepository();

  @override
  WebRepository web(String workbenchId) => InMemoryWebRepository();
}
