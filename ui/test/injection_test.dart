import 'package:egeon_deck/core/adapters/egeon_socket_client.dart';
import 'package:egeon_deck/core/adapters/injector.dart';
import 'package:egeon_deck/core/adapters/organization_feed.dart';
import 'package:egeon_deck/core/di/injection.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_probe.dart';
import 'package:egeon_deck/features/canvas/domain/repository/canvas_repository.dart';
import 'package:egeon_deck/features/chat/domain/repository/chat_repository.dart';
import 'package:egeon_deck/features/chat/presentation/cubit/queue_panel_width.dart';
import 'package:egeon_deck/features/node/agent/domain/repository/agent_repository.dart';
import 'package:egeon_deck/features/node/agent/domain/repository/socket_agent_repository.dart';
import 'package:egeon_deck/features/node/agent/domain/usecase/watch_agent.dart';
import 'package:egeon_deck/features/node/queue/domain/usecase/edit_queue.dart';
import 'package:egeon_deck/features/node/web/domain/usecase/edit_web.dart';
import 'package:egeon_deck/features/node/web/presentation/cubit/web_capture_registry.dart';
import 'package:egeon_deck/features/node/web/presentation/cubit/web_cubit.dart';
import 'package:egeon_deck/features/workbench/domain/repository/workbench_repository.dart';
import 'package:egeon_deck/features/workbench/domain/usecase/bench_creation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_workbench_repository.dart';

/// O registro real monta sem abrir conexão: só pegar os objetos não liga o
/// socket — quem liga é o cubit da conexão.
void main() {
  tearDown(Injector.reset);

  group('infraestrutura e domínio juntos', () {
    setUp(() {
      registerInfrastructure({'EGEON_HOME': '/tmp/egeon-injection-test'});
      registerDomain();
    });

    test('o socket, o feed e o canvas são um só', () {
      expect(
        identical(inject<EgeonSocketClient>(), inject<EgeonSocketClient>()),
        isTrue,
      );
      expect(
        identical(inject<OrganizationFeed>(), inject<OrganizationFeed>()),
        isTrue,
      );
      expect(
        identical(inject<CanvasRepository>(), inject<CanvasRepository>()),
        isTrue,
        reason: 'o cache de frames é repartido entre watch e saveFrames',
      );
    });

    test('os registros que a casca reparte são um só, cada um no módulo', () {
      expect(
        identical(inject<CanvasProbeRegistry>(), inject<CanvasProbeRegistry>()),
        isTrue,
      );
      expect(
        identical(inject<WebCaptureRegistry>(), inject<WebCaptureRegistry>()),
        isTrue,
      );
      expect(
        identical(inject<QueuePanelWidth>(), inject<QueuePanelWidth>()),
        isTrue,
      );
    });

    test('repositório sem estado e usecase nascem a cada pedido', () {
      expect(
        identical(inject<ChatRepository>(), inject<ChatRepository>()),
        isFalse,
      );
      expect(
        identical(inject<WorktreeActions>(), inject<WorktreeActions>()),
        isFalse,
      );
    });

    test('o repositório de nó é o da bancada pedida', () {
      final agent = inject<AgentRepository>('b1') as SocketAgentRepository;
      expect(agent.workbenchId, 'b1');
      expect(
        (inject<AgentRepository>('b2') as SocketAgentRepository).workbenchId,
        'b2',
      );
    });

    test('usecase de nó também é por bancada', () {
      expect(inject<WatchAgent>('b1'), isA<WatchAgent>());
      expect(inject<EditQueue>('b1'), isA<EditQueue>());
      expect(inject<EditWeb>('b1'), isA<EditWeb>());
    });

    test('a página nativa vem do registro real do módulo web', () {
      expect(inject<WebControllerFactory>(), isNotNull);
    });
  });

  group('só o domínio, como nos testes', () {
    setUp(registerDomain);

    test('nenhum repositório real entra: quem registra é o teste', () {
      expect(() => inject<ChatRepository>(), throwsA(anything));
      expect(() => inject<WebControllerFactory>(), throwsA(anything));
    });

    test('o domínio de um módulo sobe sobre o falso registrado', () {
      final fake = FakeWorkbenchRepository();
      Injector.singleton<WorkbenchRepository>(fake);
      expect(inject<WorktreeActions>(), isA<WorktreeActions>());
    });
  });
}
