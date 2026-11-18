import 'package:egeon_deck/features/node/card/domain/entities/card_activity.dart'
    show ActivityTone;
import 'package:egeon_deck/features/chat/domain/entities/chat_block.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_completion.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_participant.dart';
import 'package:egeon_deck/features/chat/domain/entities/permission_request.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_thread.dart';
import 'package:egeon_deck/features/chat/domain/entities/chat_update.dart';
import 'package:egeon_deck/features/chat/domain/repository/chat_repository.dart';
import 'package:egeon_deck/features/chat/presentation/page/chat_page.dart';
import 'package:egeon_deck/features/chat/presentation/widgets/chat_thread_view.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:egeon_deck/theme/code_palette.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/chat_fixtures.dart';
import '../../support/fake_chat_repository.dart';
import '../../support/hand_cursor.dart';
import '../../support/overlay_host.dart';

Map<String, Object?> blockMap(Map<String, Object?> extra) => {
  'messageKey': 'r|u1',
  'first': false,
  'last': false,
  'depth': 0,
  'from': front,
  ...extra,
};

Future<FakeChatRepository> mount(
  WidgetTester tester, {
  Size size = const Size(800, 500),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = FakeChatRepository();
  await tester.pumpWidget(
    overlayHost(
      RepositoryProvider<ChatRepository>.value(
        value: repository,
        child: const ChatPage(workbenchId: 'b1'),
      ),
      size: size,
    ),
  );
  return repository;
}

Future<void> deliver(
  WidgetTester tester,
  FakeChatRepository repository,
  int rev,
  List<ChatBlock> blocks, {
  List<ChatParticipantInfo>? participants,
  PermissionRequest? permission,
}) async {
  repository.reset(
    rev,
    blocks,
    participants: participants,
    permission: permission,
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

ScrollController controllerOf(WidgetTester tester) => tester
    .state<ChatThreadViewState>(find.byType(ChatThreadView))
    .scroll
    .controller;

void main() {
  testWidgets('mostra a conversa: prompt, cabeçalho, prosa', (tester) async {
    final repository = await mount(tester);
    await deliver(tester, repository, 1, conversation(2));
    expect(find.text('pergunta 0'), findsOneWidget);
    expect(find.text('✦ front'), findsWidgets);
    expect(find.text('deck/front'), findsWidgets);
    expect(
      find.textContaining('Resposta 1 com texto', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('o código é pintado pelo tipo de cada trecho', (tester) async {
    final repository = await mount(tester);
    final code = ChatBlock.fromMap(
      blockMap({
        'id': 'b|u1|1',
        'kind': 'code',
        'code': 'let a = 1',
        'language': 'swift',
        'spans': [
          [
            {'kind': 'keyword', 'text': 'let'},
            {'kind': 'plain', 'text': ' a = '},
            {'kind': 'number', 'text': '1'},
          ],
        ],
      }),
    );
    await deliver(tester, repository, 1, [header(1), code]);
    final colors = <String, Color?>{};
    for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
      widget.text.visitChildren((span) {
        if (span is TextSpan && span.text == 'let') {
          colors['let'] = span.style?.color;
        }
        if (span is TextSpan && span.text == '1') {
          colors['1'] = span.style?.color;
        }
        return true;
      });
    }
    expect(colors['let'], CodePalette.of('keyword'));
    expect(colors['1'], CodePalette.of('number'));
    expect(colors['let'], isNot(colors['1']));
  });

  testWidgets('o passo recolhido é só o título; o clique nele manda abrir', (
    tester,
  ) async {
    final repository = await mount(tester);
    final step = ChatBlock.fromMap(
      blockMap({
        'id': 'b|u1|3',
        'kind': 'step',
        'expanded': false,
        'step': {
          'glyph': r'$',
          'text': 'Roda',
          'detail': 'swift test',
          'isError': false,
        },
      }),
    );
    await deliver(tester, repository, 1, [header(1), step]);
    expect(find.textContaining('Roda'), findsOneWidget);
    expect(find.text('swift test'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('step-title')));
    await tester.pump();
    expect(repository.steps, ['b|u1|3']);
  });

  testWidgets('aberto mostra comando e saída; só o título responde ao clique', (
    tester,
  ) async {
    final repository = await mount(tester);
    final step = ChatBlock.fromMap(
      blockMap({
        'id': 'b|u1|3',
        'kind': 'step',
        'expanded': true,
        'step': {
          'glyph': r'$',
          'text': 'Roda',
          'detail': 'swift test',
          'output': 'ok',
          'isError': false,
        },
      }),
    );
    await deliver(tester, repository, 1, [header(1), step]);
    expect(find.text('swift test'), findsOneWidget);
    expect(find.text('ok'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('step-body')));
    await tester.pump();
    expect(
      repository.steps,
      isEmpty,
      reason: 'o corpo é texto para ler e copiar',
    );

    await tester.tap(find.byKey(const ValueKey('step-title')));
    await tester.pump();
    expect(repository.steps, ['b|u1|3']);
  });

  testWidgets('passo sem comando nem saída não tem o que abrir', (
    tester,
  ) async {
    final repository = await mount(tester);
    final step = ChatBlock.fromMap(
      blockMap({
        'id': 'b|u1|3',
        'kind': 'step',
        'expanded': false,
        'step': {'glyph': '→', 'text': 'Lê a.swift', 'isError': false},
      }),
    );
    await deliver(tester, repository, 1, [header(1), step]);
    await tester.tap(find.byKey(const ValueKey('step-title')));
    await tester.pump();
    expect(repository.steps, isEmpty);
  });

  testWidgets('a capa diz quantos passos e o último; o clique avança o nível', (
    tester,
  ) async {
    final repository = await mount(tester);
    final group = ChatBlock.fromMap(
      blockMap({
        'id': 'g|u1|0',
        'kind': 'group',
        'count': 3,
        'lastStep': 'três',
        'level': 'summary',
      }),
    );
    await deliver(tester, repository, 1, [header(1), group]);
    expect(find.text('3 passos · três'), findsOneWidget);
    await tester.tap(find.text('3 passos · três'));
    await tester.pump();
    expect(repository.groups, ['g|u1|0']);
  });

  testWidgets('o diff pinta o que entra, o que sai e a posição', (
    tester,
  ) async {
    final repository = await mount(tester);
    final diff = ChatBlock.fromMap(
      blockMap({
        'id': 'b|u1|4',
        'kind': 'diff',
        'file': 'a.swift',
        'diff': ['@@ -1 +1 @@', '-a', '+b'],
      }),
    );
    await deliver(tester, repository, 1, [header(1), diff]);
    expect(find.text('± a.swift'), findsOneWidget);
    final spans = <String, Color?>{};
    for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
      widget.text.visitChildren((span) {
        if (span is TextSpan &&
            (span.text ?? '').trim().startsWith(RegExp('[-+@]'))) {
          spans[span.text!.trim()] = span.style?.color;
        }
        return true;
      });
    }
    expect(spans['-a'], const Color(0xFFFF7B7B));
    expect(spans['+b'], const Color(0xFF6CCB7A));
    expect(spans['@@ -1 +1 @@'], const Color(0xFF6EA8FF));
  });

  testWidgets(
    'o status ao vivo diz o que o agente faz; pedir permissão é laranja',
    (tester) async {
      final repository = await mount(tester);
      ChatBlock status(String state) => ChatBlock.fromMap(
        blockMap({
          'id': 's|u1',
          'kind': 'status',
          'last': true,
          'live': {'state': state},
        }),
      );
      await deliver(tester, repository, 1, [header(1), status('thinking')]);
      expect(find.textContaining('pensando…'), findsOneWidget);
      await deliver(tester, repository, 2, [header(1), status('asking')]);
      expect(find.text('● precisa de você'), findsOneWidget);
    },
  );

  testWidgets('eco ainda não confirmado fica esmaecido', (tester) async {
    final repository = await mount(tester);
    await deliver(tester, repository, 1, [prompt(1, pending: true)]);
    final opacity = tester.widget<Opacity>(
      find
          .ancestor(of: find.text('pergunta 1'), matching: find.byType(Opacity))
          .first,
    );
    expect(opacity.opacity, 0.6);
  });

  testWidgets(
    'revisão perdida pede a thread de novo, não aplica o diff torto',
    (tester) async {
      final repository = await mount(tester);
      await deliver(tester, repository, 1, conversation(1));
      repository.thread = ChatThread(rev: 5, blocks: conversation(2));
      repository.push(
        ChatUpdate(workbench: 'b1', rev: 4, ops: [RemoveOp('p|u0')]),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(repository.snapshots, 1);
      expect(
        find.text('pergunta 1'),
        findsOneWidget,
        reason: 'veio do instantâneo',
      );
      expect(
        find.text('pergunta 0'),
        findsOneWidget,
        reason: 'o remove torto não valeu',
      );
    },
  );

  testWidgets('evento velho é descartado; só o buraco pede o instantâneo', (
    tester,
  ) async {
    final repository = await mount(tester);
    await deliver(tester, repository, 3, conversation(1));
    repository.push(
      ChatUpdate(workbench: 'b1', rev: 2, ops: [RemoveOp('p|u0')]),
    );
    repository.push(
      ChatUpdate(workbench: 'b1', rev: 3, ops: [RemoveOp('p|u0')]),
    );
    await tester.pump();
    await tester.pump();
    expect(repository.snapshots, 0, reason: 'velho não é buraco');
    expect(find.text('pergunta 0'), findsOneWidget, reason: 'e não se aplica');
  });

  testWidgets('os ops entram em ordem: insere, atualiza e remove', (
    tester,
  ) async {
    final repository = await mount(tester);
    await deliver(tester, repository, 1, conversation(1));
    repository.push(
      ChatUpdate(
        workbench: 'b1',
        rev: 2,
        ops: [InsertOp(3, prompt(7)), RemoveOp('p|u0')],
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('pergunta 7'), findsOneWidget);
    expect(find.text('pergunta 0'), findsNothing);
  });

  testWidgets('o cubit assina ao nascer e cancela ao sair', (tester) async {
    final repository = await mount(tester);
    expect(repository.watchers, 1);
    await tester.pumpWidget(const SizedBox());
    expect(repository.watchers, 0);
  });

  group('rolagem', () {
    testWidgets('a conversa nasce no fim', (tester) async {
      final repository = await mount(tester);
      await deliver(tester, repository, 1, conversation(20));
      final scroll = tester
          .state<ChatThreadViewState>(find.byType(ChatThreadView))
          .scroll;
      expect(scroll.isAtVeryBottom, isTrue);
      expect(controllerOf(tester).position.maxScrollExtent, greaterThan(0));
    });

    testWidgets('mensagem nova com você no fim: continua no fim', (
      tester,
    ) async {
      final repository = await mount(tester);
      await deliver(tester, repository, 1, conversation(20));
      final scroll = tester
          .state<ChatThreadViewState>(find.byType(ChatThreadView))
          .scroll;
      repository.push(
        ChatUpdate(
          workbench: 'b1',
          rev: 2,
          ops: [
            InsertOp(60, prompt(99)),
            InsertOp(61, header(99)),
            InsertOp(62, prose(99)),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(
        scroll.isAtVeryBottom,
        isTrue,
        reason: 'parou no fim antigo: a linha nova não contou',
      );
      expect(find.text('pergunta 99'), findsOneWidget);
    });

    testWidgets('subiu para ler: a mensagem nova não puxa de volta', (
      tester,
    ) async {
      final repository = await mount(tester);
      await deliver(tester, repository, 1, conversation(20));
      final controller = controllerOf(tester);
      controller.jumpTo(0);
      await tester.pump();
      repository.push(
        ChatUpdate(workbench: 'b1', rev: 2, ops: [InsertOp(60, prompt(99))]),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(controller.offset, 0);
    });

    testWidgets('descida animada em curso conta como "no fim"', (tester) async {
      final repository = await mount(tester);
      await deliver(tester, repository, 1, conversation(20));
      final scroll = tester
          .state<ChatThreadViewState>(find.byType(ChatThreadView))
          .scroll;
      scroll.controller.jumpTo(0);
      await tester.pump();
      expect(scroll.isAtBottom, isFalse);

      scroll.scrollToBottom(animated: true);
      await tester.pump();
      expect(scroll.scrollingToBottom, isTrue);
      expect(
        scroll.isAtBottom,
        isTrue,
        reason: 'descida a caminho conta como fim',
      );

      await tester.pumpAndSettle();
      expect(
        scroll.scrollingToBottom,
        isFalse,
        reason: 'a bandeira cai quando a descida acaba',
      );
      expect(scroll.isAtVeryBottom, isTrue);
    });

    testWidgets('pegar a thread na mão no meio da descida cancela a descida', (
      tester,
    ) async {
      final repository = await mount(tester);
      await deliver(tester, repository, 1, conversation(20));
      final scroll = tester
          .state<ChatThreadViewState>(find.byType(ChatThreadView))
          .scroll;
      scroll.controller.jumpTo(0);
      await tester.pump();
      scroll.scrollToBottom(animated: true);
      await tester.pump(const Duration(milliseconds: 50));
      scroll.stopScrolling();
      expect(scroll.scrollingToBottom, isFalse);
      expect(
        scroll.isAtBottom,
        isFalse,
        reason: 'quem parou no meio fica onde parou',
      );
    });

    testWidgets('mandar de um ponto acima do fim leva ao fim', (tester) async {
      final repository = await mount(tester);
      await deliver(
        tester,
        repository,
        1,
        conversation(20),
        participants: const [frontInfo],
      );
      final controller = controllerOf(tester);
      controller.jumpTo(0);
      await tester.pump();

      await tester.enterText(find.byType(EditableText), 'e agora?');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(repository.sent.single.text, 'e agora?');
      expect(
        controller.position.pixels,
        greaterThanOrEqualTo(controller.position.maxScrollExtent - 1),
      );
    });

    testWidgets('puxar o topo várias vezes pede o histórico uma vez só', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final repository = await mount(tester);
        await deliver(tester, repository, 1, conversation(20));
        controllerOf(tester).jumpTo(0);
        await tester.pump();
        // Com a física do macOS o topo rebate: cada movimento é um evento de
        // rolagem, e cada carga traria mais 60 mensagens.
        final gesture = await tester.startGesture(const Offset(400, 200));
        for (var i = 0; i < 8; i++) {
          await gesture.moveBy(const Offset(0, 40));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(repository.more, 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets(
      'se o pedido de histórico falha, o próximo toque pede de novo',
      (tester) async {
        final repository = await mount(tester);
        repository.failMore = true;
        await deliver(tester, repository, 1, conversation(20));
        final controller = controllerOf(tester);
        controller.jumpTo(0);
        await tester.pump();
        await tester.pump();
        expect(repository.more, 1);
        controller.jumpTo(50);
        await tester.pump();
        await tester.pump();
        expect(repository.more, 2, reason: 'a falha liberou o pedido');
      },
    );

    testWidgets('chegada de mais histórico libera o próximo pedido', (
      tester,
    ) async {
      final repository = await mount(tester);
      await deliver(tester, repository, 1, conversation(20, start: 10));
      controllerOf(tester).jumpTo(0);
      await tester.pump();
      expect(repository.more, 1);

      await deliver(tester, repository, 2, conversation(30, start: 0));
      controllerOf(tester).jumpTo(0);
      await tester.pump();
      expect(repository.more, 2);
    });

    testWidgets('perto do topo (300 pt) pede; longe dele não', (tester) async {
      final repository = await mount(tester);
      await deliver(tester, repository, 1, conversation(30));
      final controller = controllerOf(tester);
      controller.jumpTo(controller.position.maxScrollExtent / 2);
      await tester.pump();
      expect(repository.more, 0);
      controller.jumpTo(250);
      await tester.pump();
      expect(repository.more, 1);
    });

    testWidgets('histórico novo por cima não tira do lugar quem está lendo', (
      tester,
    ) async {
      final repository = await mount(tester);
      await deliver(tester, repository, 1, conversation(30, start: 10));
      final controller = controllerOf(tester);
      // Lendo a pergunta 12, no meio.
      controller.jumpTo(300);
      await tester.pump();
      final before = tester.getTopLeft(find.text('pergunta 12')).dy;

      await deliver(tester, repository, 2, conversation(40, start: 0));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      expect(
        find.text('pergunta 12'),
        findsOneWidget,
        reason: 'a linha que se lia continua na tela',
      );
      expect(
        tester.getTopLeft(find.text('pergunta 12')).dy,
        closeTo(before, 2),
        reason: 'e no mesmo ponto da tela',
      );
      expect(
        find.text('pergunta 0'),
        findsNothing,
        reason: 'o começo do que chegou fica acima, fora da tela',
      );
    });

    testWidgets('chegar ao começo pede mais histórico', (tester) async {
      final repository = await mount(tester);
      await deliver(tester, repository, 1, conversation(20));
      controllerOf(tester).jumpTo(0);
      await tester.pump();
      expect(repository.more, greaterThan(0));
    });
  });

  group('composer', () {
    Future<FakeChatRepository> ready(
      WidgetTester tester, {
      List<ChatParticipantInfo> participants = const [frontInfo],
    }) async {
      final repository = await mount(tester);
      await deliver(
        tester,
        repository,
        1,
        conversation(2),
        participants: participants,
      );
      return repository;
    }

    testWidgets('Enter manda para o participante em foco; o campo esvazia', (
      tester,
    ) async {
      final repository = await ready(tester);
      expect(find.byKey(const ValueKey('composer-target')), findsOneWidget);
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'oi');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(repository.sent.single.to, ['front']);
      expect(repository.sent.single.text, 'oi');
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
    });

    testWidgets('Shift+Enter não manda', (tester) async {
      final repository = await ready(tester);
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'oi');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(repository.sent, isEmpty);
    });

    testWidgets('texto vazio não manda; sem ninguém na conversa também não', (
      tester,
    ) async {
      final repository = await ready(tester, participants: const []);
      expect(find.byKey(const ValueKey('composer-target')), findsNothing);
      await tester.enterText(find.byType(EditableText), 'oi');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await tester.pump();
      expect(repository.sent, isEmpty);
    });

    testWidgets(
      'clicar num participante o põe em foco: o composer manda a ele',
      (tester) async {
        final repository = await ready(
          tester,
          participants: const [frontInfo, backInfo, shellInfo],
        );
        await tester.tap(find.byKey(const ValueKey('participant-back')));
        await tester.pump();
        await tester.enterText(find.byType(EditableText), 'oi');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('composer-send')));
        await tester.pump();
        expect(repository.sent.single.to, ['back']);
      },
    );

    testWidgets('Tab alterna entre os agentes, e só agentes', (tester) async {
      final repository = await ready(
        tester,
        participants: const [frontInfo, shellInfo, backInfo],
      );
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'a');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await tester.pump();
      expect(repository.sent.last.to, ['back']);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'b');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-send')));
      await tester.pump();
      expect(repository.sent.last.to, [
        'front',
      ], reason: 'o terminal não entra no Tab');
    });

    testWidgets('digitar não remonta a thread', (tester) async {
      await ready(tester);
      final view = tester.state<ChatThreadViewState>(
        find.byType(ChatThreadView),
      );
      final builds = view.builds;
      await tester.enterText(find.byType(EditableText), 'uma linha');
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'duas\nlinhas');
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'três\nlinhas\naqui');
      await tester.pump();
      expect(
        view.builds,
        builds,
        reason: 'o composer crescer não remonta a thread',
      );
    });

    testWidgets('onde se clica, o ponteiro diz', (tester) async {
      await ready(tester, participants: const [frontInfo, backInfo]);
      expectHandOnEveryClickable(tester);
    });
  });

  group('menu de @menção e /slash', () {
    Future<FakeChatRepository> ready(WidgetTester tester) async {
      final repository = await mount(tester);
      repository.completer = (text, caret) {
        final at = text.lastIndexOf('@', caret);
        if (at < 0) return ChatCompletion.none(caret);
        return ChatCompletion(
          items: const [
            CompletionItem(
              label: 'rev',
              insert: '@rev ',
              kind: 'mention',
              detail: 'revisor',
            ),
            CompletionItem(label: 'back', insert: '@back ', kind: 'mention'),
          ],
          start: at,
          end: caret,
        );
      };
      await deliver(
        tester,
        repository,
        1,
        conversation(1),
        participants: const [frontInfo, backInfo],
      );
      return repository;
    }

    Future<void> type(WidgetTester tester, String text) async {
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), text);
      await tester.pump();
      await tester.pump();
    }

    String fieldText(WidgetTester tester) =>
        tester.widget<EditableText>(find.byType(EditableText)).controller.text;

    testWidgets(
      'digitar @ pergunta ao core com o texto, o cursor e o destino',
      (tester) async {
        final repository = await ready(tester);
        await type(tester, 'pede ao @re');
        expect(repository.completions.last, (
          text: 'pede ao @re',
          caret: 11,
          to: 'front',
        ));
        expect(find.byKey(const ValueKey('completion-menu')), findsOneWidget);
        expect(find.text('@rev'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('completion-menu')),
            matching: find.text('revisor'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('sem gatilho o menu não aparece', (tester) async {
      await ready(tester);
      await type(tester, 'oi');
      expect(find.byKey(const ValueKey('completion-menu')), findsNothing);
    });

    testWidgets('Enter insere a sugestão no lugar do trecho — e não manda', (
      tester,
    ) async {
      final repository = await ready(tester);
      await type(tester, 'pede ao @re');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(fieldText(tester), 'pede ao @rev ');
      expect(repository.sent, isEmpty, reason: 'o Enter escolheu, não mandou');
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .controller
            .selection
            .baseOffset,
        13,
        reason: 'o cursor fica depois da sugestão',
      );
    });

    testWidgets('as setas escolhem a linha; Tab insere', (tester) async {
      await ready(tester);
      await type(tester, 'pede ao @re');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(fieldText(tester), 'pede ao @back ');
    });

    testWidgets('Esc fecha o menu sem mexer no texto', (tester) async {
      await ready(tester);
      await type(tester, 'pede ao @re');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const ValueKey('completion-menu')), findsNothing);
      expect(fieldText(tester), 'pede ao @re');
    });

    testWidgets('o clique numa sugestão a insere', (tester) async {
      await ready(tester);
      await type(tester, 'pede ao @re');
      await tester.tap(find.byKey(const ValueKey('completion-1')));
      await tester.pump();
      expect(fieldText(tester), 'pede ao @back ');
    });

    testWidgets('com o menu fechado o Enter volta a mandar', (tester) async {
      final repository = await ready(tester);
      await type(tester, 'oi');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(repository.sent.single.text, 'oi');
    });
  });

  group('participantes', () {
    testWidgets('a coluna separa agentes e terminais e mostra o que fazem', (
      tester,
    ) async {
      final repository = await mount(tester);
      await deliver(
        tester,
        repository,
        1,
        conversation(1),
        participants: const [frontInfo, backInfo, shellInfo],
      );
      expect(find.text('AGENTES'), findsOneWidget);
      expect(find.text('TERMINAIS'), findsOneWidget);
      expect(find.text('revisor'), findsOneWidget, reason: 'o papel do agente');
      expect(find.byKey(const ValueKey('activity-working')), findsOneWidget);
    });

    testWidgets('sem participantes a coluna não aparece', (tester) async {
      final repository = await mount(tester);
      await deliver(tester, repository, 1, conversation(1));
      expect(find.text('AGENTES'), findsNothing);
    });

    testWidgets('a lista de participantes muda com o evento do core', (
      tester,
    ) async {
      final repository = await mount(tester);
      await deliver(
        tester,
        repository,
        1,
        conversation(1),
        participants: const [frontInfo],
      );
      repository.push(
        ChatUpdate(
          workbench: 'b1',
          rev: 2,
          ops: [
            ParticipantsOp([
              frontInfo,
              const ChatParticipantInfo(
                id: 'back',
                address: 'deck/back',
                isAgent: true,
                activity: 'asking',
                tone: ActivityTone.orange,
              ),
            ]),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('participant-back')), findsOneWidget);
      expect(find.byKey(const ValueKey('activity-asking')), findsOneWidget);
    });
  });

  group('permissão', () {
    const tool = PermissionRequest(
      id: 'p1',
      tool: 'Bash',
      summary: 'rm -rf x',
      detail: 'apagar x',
      canAlwaysAllow: true,
      agent: 'front',
    );

    testWidgets(
      'a bandeja diz quem quer usar o quê, e os três botões respondem',
      (tester) async {
        final repository = await mount(tester);
        await deliver(
          tester,
          repository,
          1,
          conversation(1),
          participants: const [frontInfo],
          permission: tool,
        );
        expect(find.byKey(const ValueKey('permission-tray')), findsOneWidget);
        expect(
          find.textContaining('quer usar Bash — apagar x', findRichText: true),
          findsOneWidget,
        );
        expect(find.text('rm -rf x'), findsOneWidget);

        await tester.tap(find.text('Permitir'));
        await tester.tap(find.text('Sempre'));
        await tester.tap(find.text('Negar'));
        await tester.pump();
        expect(repository.answers, [
          {'request': 'p1', 'answer': 'allow'},
          {'request': 'p1', 'answer': 'always'},
          {'request': 'p1', 'answer': 'deny'},
        ]);
      },
    );

    testWidgets('sem regra sugerida não há "Sempre"', (tester) async {
      final repository = await mount(tester);
      await deliver(
        tester,
        repository,
        1,
        conversation(1),
        permission: const PermissionRequest(id: 'p2', tool: 'Bash'),
      );
      expect(find.text('Sempre'), findsNothing);
      expect(find.text('Permitir'), findsOneWidget);
    });

    testWidgets('a bandeja some quando o core diz que não há pedido', (
      tester,
    ) async {
      final repository = await mount(tester);
      await deliver(tester, repository, 1, conversation(1), permission: tool);
      repository.push(
        ChatUpdate(workbench: 'b1', rev: 2, ops: [const PermissionOp(null)]),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('permission-tray')), findsNothing);
    });

    testWidgets('uma pergunta de uma só escolha responde na hora', (
      tester,
    ) async {
      final repository = await mount(tester);
      await deliver(
        tester,
        repository,
        1,
        conversation(1),
        permission: const PermissionRequest(
          id: 'p8',
          tool: 'AskUserQuestion',
          questions: [
            PermissionQuestion(
              question: 'Qual cor?',
              header: 'Cor',
              options: ['azul', 'verde'],
            ),
          ],
        ),
      );
      expect(find.text('Cor · Qual cor?'), findsOneWidget);
      await tester.tap(find.text('verde'));
      await tester.pump();
      expect(repository.answers, [
        {'request': 'p8', 'choice': 'verde'},
      ]);
    });

    testWidgets(
      'várias perguntas juntam as escolhas e só enviam com "Responder"',
      (tester) async {
        final repository = await mount(tester);
        await deliver(
          tester,
          repository,
          1,
          conversation(1),
          permission: const PermissionRequest(
            id: 'p9',
            tool: 'AskUserQuestion',
            questions: [
              PermissionQuestion(
                question: 'Qual cor?',
                options: ['azul', 'verde'],
              ),
              PermissionQuestion(
                question: 'Quais frutas?',
                options: ['maçã', 'pera', 'uva'],
                multiSelect: true,
              ),
            ],
          ),
        );
        await tester.tap(find.text('Responder'));
        await tester.pump();
        expect(repository.answers, isEmpty, reason: 'falta responder tudo');

        await tester.tap(find.text('azul'));
        await tester.tap(find.text('maçã'));
        await tester.tap(find.text('uva'));
        await tester.pump();
        await tester.tap(find.text('Responder'));
        await tester.pump();
        expect(repository.answers.single, {
          'request': 'p9',
          'answers': {
            'Qual cor?': ['azul'],
            'Quais frutas?': ['maçã', 'uva'],
          },
        });
      },
    );
  });
}
