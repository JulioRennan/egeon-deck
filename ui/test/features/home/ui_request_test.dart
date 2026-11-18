import 'dart:async';

import 'package:egeon_deck/features/home/domain/entities/ui_request.dart';
import 'package:egeon_deck/features/home/domain/repository/screen_control.dart';
import 'package:egeon_deck/features/home/domain/repository/ui_request_repository.dart';
import 'package:egeon_deck/features/home/domain/usecase/answer_ui_request.dart';
import 'package:egeon_deck/features/home/domain/usecase/reply_ui_request.dart';
import 'package:egeon_deck/features/home/domain/usecase/watch_ui_requests.dart';
import 'package:egeon_deck/features/home/presentation/cubit/ui_request_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:egeon_deck/features/home/domain/errors/home_error.dart';

class _Screen implements ScreenControl {
  String? layoutApplied = 'chat';
  String? tabApplied = 'active';
  bool? lastCollapsed = true;
  bool collapsed = true;
  final calls = <String>[];
  Object? failure;

  @override
  String? setLayout(String mode) {
    calls.add('layout:$mode');
    return layoutApplied;
  }

  @override
  bool setSidebarCollapsed(bool? value) {
    calls.add('collapsed:$value');
    lastCollapsed = value;
    return collapsed;
  }

  @override
  String? setSidebarTab(String tab) {
    calls.add('tab:$tab');
    return tabApplied;
  }

  @override
  Future<Map<String, Object?>> geometry() async {
    if (failure != null) throw failure!;
    return {'mode': 'canvas', 'nodes': <Object?>[]};
  }

  @override
  Future<String> snapshot(String target, String file) async {
    calls.add('shot:$target:$file');
    return file;
  }
}

class _Repository implements UiRequestRepository {
  final requests = StreamController<UiRequest>.broadcast();
  final replies = <(Object, UiReply)>[];
  final activates = StreamController<void>.broadcast();
  var failReply = false;

  @override
  Stream<UiRequest> watch() => requests.stream;

  @override
  Stream<void> activations() => activates.stream;

  @override
  Future<void> reply(Object request, UiReply reply) async {
    if (failReply) throw const HomeOffline();
    replies.add((request, reply));
  }
}

UiRequest request(String route, [Map<String, String> params = const {}]) =>
    UiRequest(id: 7, route: route, params: params);

void main() {
  late _Screen screen;
  late AnswerUiRequest answer;

  setUp(() {
    screen = _Screen();
    answer = AnswerUiRequest(screen);
  });

  group('a tela devolve só o valor; o core monta o HTTP', () {
    test('layout: o modo aplicado, ou null quando não deu', () async {
      expect((await answer(request('layout', {'mode': 'chat'}))).value, 'chat');
      screen.layoutApplied = null;
      expect((await answer(request('layout', {'mode': 'xyz'}))).value, isNull);
    });

    test(
      'sidebar: collapsed 1, 0 e toggle devolvem o estado recolhido',
      () async {
        var reply = await answer(request('sidebar', {'collapsed': '1'}));
        expect(screen.lastCollapsed, isTrue);
        expect(reply.value, true);

        await answer(request('sidebar', {'collapsed': '0'}));
        expect(screen.lastCollapsed, isFalse);

        screen.collapsed = false;
        reply = await answer(request('sidebar', {'collapsed': 'toggle'}));
        expect(screen.lastCollapsed, isNull, reason: 'null é alternar');
        expect(reply.value, false);
      },
    );

    test(
      'sidebar com tab: a aba aplicada, ou null quando não existe',
      () async {
        expect(
          (await answer(request('sidebar', {'tab': 'active'}))).value,
          'active',
        );
        screen.tabApplied = null;
        expect(
          (await answer(request('sidebar', {'tab': 'nada'}))).value,
          isNull,
        );
      },
    );

    test('geometry devolve o dicionário da tela, sem envelope', () async {
      final reply = await answer(request('geometry'));
      expect((reply.value! as Map)['mode'], 'canvas');
    });

    test(
      'shot grava no arquivo que o core mandou e devolve o caminho',
      () async {
        final reply = await answer(
          request('shot', {
            'target': 'deck/claude',
            'file': '/tmp/s/deck_claude.png',
          }),
        );
        expect(screen.calls, ['shot:deck/claude:/tmp/s/deck_claude.png']);
        expect(reply.value, '/tmp/s/deck_claude.png');
      },
    );

    test(
      'shot sem arquivo não chama a tela e devolve o erro em texto',
      () async {
        final reply = await answer(request('shot', {'target': 'window'}));
        expect(screen.calls, isEmpty);
        expect(reply.value as String, startsWith('erro:'));
      },
    );

    test('rota que a tela não conhece não tem valor', () async {
      expect((await answer(request('outra'))).value, isNull);
    });
  });

  group('o cubit', () {
    late _Repository repository;
    late UiRequestCubit cubit;
    var activated = 0;

    setUp(() {
      activated = 0;
      repository = _Repository();
      cubit = UiRequestCubit(
        watch: WatchUiRequests(repository),
        answer: answer,
        reply: ReplyUiRequest(repository),
        activate: () async => activated++,
        activations: repository.activates.stream,
      );
      addTearDown(cubit.close);
    });

    test('atende cada pedido e responde com o id dele', () async {
      repository.requests.add(request('layout', {'mode': 'chat'}));
      await Future<void>.delayed(Duration.zero);
      expect(repository.replies.single.$1, 7, reason: 'o id volta como veio');
      expect(repository.replies.single.$2.value, 'chat');
    });

    test(
      'falha ao atender vira 500 em vez de deixar o cliente esperando',
      () async {
        screen.failure = StateError('sem janela');
        repository.requests.add(request('geometry'));
        await Future<void>.delayed(Duration.zero);
        expect(
          repository.replies.single.$2.value,
          isNull,
          reason: 'a tela falhou: para o core, não deu',
        );
      },
    );

    test('a conexão cair ao responder não derruba o cubit', () async {
      repository.failReply = true;
      repository.requests.add(request('layout', {'mode': 'chat'}));
      await Future<void>.delayed(Duration.zero);
      repository.failReply = false;
      repository.requests.add(request('layout', {'mode': 'canvas'}));
      await Future<void>.delayed(Duration.zero);
      expect(repository.replies, hasLength(1));
    });

    test('o core pedir a janela para a frente aciona o ativador', () async {
      repository.activates.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(activated, 1);
    });

    test('fechar cancela a assinatura', () async {
      await cubit.close();
      expect(repository.requests.hasListener, isFalse);
      expect(repository.activates.hasListener, isFalse);
    });
  });

  test('UiRequest lê o evento do core, params em texto', () {
    final read = UiRequest.fromMap({
      'topic': 'app',
      'effect': 'ui_request',
      'id': 7,
      'route': 'shot',
      'params': {'target': 'window', 'n': 3},
    });
    expect(read.id, 7);
    expect(read.route, 'shot');
    expect(read.params, {'target': 'window', 'n': '3'});
  });
}
