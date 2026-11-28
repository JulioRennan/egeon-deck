import 'package:egeon_deck/features/chat/domain/entities/chat_participant.dart';
import 'package:egeon_deck/features/chat/domain/entities/permission_request.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/chat_composer.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/chat_dock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';
import '../../support/fake_agent_repository.dart';
import '../../support/fake_chat_repository.dart';
import '../../support/inject_fakes.dart';

const front = ChatParticipantInfo(
  id: 'front',
  address: 'deck/front',
  isAgent: true,
);

Future<FakeChatRepository> mount(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1000, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = FakeChatRepository();
  injectFakes(chat: repo, agent: (_) => FakeAgentRepository());
  await tester.pumpWidget(
    egHost(fill: true, const ChatDock(workbenchId: 'b1')),
  );
  await tester.pump();
  return repo;
}

void main() {
  testWidgets('o composer do canvas manda ao destinatário pela rota do chat', (
    tester,
  ) async {
    final repo = await mount(tester);
    repo.reset(1, const [], participants: const [front]);
    await tester.pump();
    await tester.pump();
    expect(find.byType(ChatComposer), findsOneWidget);
    expect(find.text('front'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'rode os testes');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    await tester.pump();
    expect(repo.sent.single.to, ['front']);
    expect(repo.sent.single.text, 'rode os testes');
  });

  testWidgets('não toma o teclado ao montar (o terminal pode estar em foco)', (
    tester,
  ) async {
    final repo = await mount(tester);
    repo.reset(1, const [], participants: const [front]);
    await tester.pump();
    await tester.pump();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isFalse);
  });

  testWidgets('a permissão do agente aparece dentro do composer do canvas', (
    tester,
  ) async {
    final repo = await mount(tester);
    repo.reset(
      1,
      const [],
      participants: const [front],
      permissions: const [
        PermissionRequest(id: 'p1', tool: 'Edit', agent: 'front'),
      ],
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Permitir'), findsOneWidget);
    expect(find.text('Negar'), findsOneWidget);
  });
}
