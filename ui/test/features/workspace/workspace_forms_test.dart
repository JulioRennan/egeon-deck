import 'package:egeon_deck/features/home/presentation/forms/app_forms.dart';
import 'package:egeon_deck/features/home/presentation/forms/form_request.dart';
import 'package:egeon_deck/features/workspace/domain/entities/workspace_draft.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_path_picker.dart';
import '../../support/fake_workspace_repository.dart';
import '../../support/hand_cursor.dart';
import '../../support/inject_fakes.dart';
import '../../support/overlay_host.dart';

class Env {
  final workspace = FakeWorkspaceRepository();
  final picker = FakePathPicker();
  late BuildContext context;

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    injectFakes(workspaces: workspace, paths: picker);
    await tester.pumpWidget(
      overlayHost(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
        size: const Size(1000, 1000),
      ),
    );
  }

  Future<void> ask(WidgetTester tester, FormRequest request) async {
    handleForm(context, request);
    await tester.pump();
    await tester.pump();
  }
}

Future<Env> mount(WidgetTester tester) async {
  final env = Env();
  await env.mount(tester);
  return env;
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  group('workspace', () {
    testWidgets('criar: nome, pastas e multi-projeto vão juntos ao core', (
      tester,
    ) async {
      final env = await mount(tester);
      await env.ask(tester, const NewWorkspace());
      expect(find.text('Novo workspace'), findsOneWidget);
      expect(find.text('Criar'), findsOneWidget);

      tester.testTextInput.enterText('Duck');
      await tester.pump();

      env.picker.nextFolders = ['/Users/x/code/egeon', '/Users/x/code/nexus'];
      await tester.tap(find.text('Adicionar pastas…'));
      await settle(tester);
      expect(find.text('/Users/x/code/egeon'), findsOneWidget);

      await tester.tap(find.text('Novo multi-projeto…'));
      await settle(tester);
      expect(find.text('Novo multi-projeto'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('multi-/Users/x/code/egeon')));
      await tester.tap(find.byKey(const ValueKey('multi-/Users/x/code/nexus')));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await settle(tester);
      expect(find.text('egeon + nexus — egeon + nexus'), findsOneWidget);

      await tester.tap(find.text('Criar'));
      await settle(tester);

      final (id, draft) = env.workspace.saved.single;
      expect(id, isNull);
      expect(draft.name, 'Duck');
      expect(draft.folders, ['/Users/x/code/egeon', '/Users/x/code/nexus']);
      expect(draft.multis.single.folders, hasLength(2));
      expect(
        draft.multis.single.name,
        'egeon + nexus',
        reason: 'sem nome digitado, o nome é o que o core sugeriu',
      );
      expect(env.workspace.multiNames, [
        'null:/Users/x/code/egeon,/Users/x/code/nexus',
      ]);
    });

    testWidgets('sem nome o botão fica desligado', (tester) async {
      final env = await mount(tester);
      await env.ask(tester, const NewWorkspace());
      await tester.tap(find.text('Criar'));
      await settle(tester);
      expect(env.workspace.saved, isEmpty);
      expect(find.text('Novo workspace'), findsOneWidget);
    });

    testWidgets('editar abre com o que o workspace já tem', (tester) async {
      final env = await mount(tester);
      env.workspace.existing = const WorkspaceDraft(
        name: 'Duck',
        folders: ['/a/egeon'],
        multis: [
          MultiDraft(id: 'm1', name: 'junto', folders: ['/a/egeon']),
        ],
      );
      await env.ask(tester, const EditWorkspace('w1', 'Duck'));
      expect(find.text('Editar workspace'), findsOneWidget);
      expect(find.text('Salvar'), findsOneWidget);
      expect(find.text('Duck'), findsWidgets);
      expect(find.text('/a/egeon'), findsOneWidget);
      expect(find.text('junto — egeon'), findsOneWidget);

      await tester.tap(find.text('Salvar'));
      await settle(tester);
      expect(env.workspace.log, ['carregar:w1', 'salvar:w1']);
      expect(env.workspace.saved.single.$1, 'w1');
      expect(env.workspace.saved.single.$2.multis.single.id, 'm1');
    });

    testWidgets('tirar uma pasta tira também dos multi-projetos', (
      tester,
    ) async {
      final env = await mount(tester);
      env.workspace.existing = const WorkspaceDraft(
        name: 'Duck',
        folders: ['/a/egeon', '/a/nexus'],
        multis: [
          MultiDraft(
            id: 'm1',
            name: 'junto',
            folders: ['/a/egeon', '/a/nexus'],
          ),
        ],
      );
      await env.ask(tester, const EditWorkspace('w1', 'Duck'));
      await tester.tap(find.byKey(const ValueKey('folder-0')));
      await tester.pump();
      await tester.tap(find.text('Tirar selecionadas'));
      await tester.pump();
      expect(find.text('/a/egeon'), findsNothing);
      expect(find.text('junto — nexus'), findsOneWidget);

      await tester.tap(find.text('Salvar'));
      await settle(tester);
      final draft = env.workspace.saved.single.$2;
      expect(draft.folders, ['/a/nexus']);
      expect(draft.multis.single.folders, ['/a/nexus']);
    });

    testWidgets('a imagem escolhida vai no rascunho; "sem imagem" a tira', (
      tester,
    ) async {
      final env = await mount(tester);
      env.workspace.existing = const WorkspaceDraft(
        name: 'Duck',
        icon: '/i.png',
      );
      await env.ask(tester, const EditWorkspace('w1', 'Duck'));

      await tester.tap(find.text('Sem imagem'));
      await tester.pump();
      await tester.tap(find.text('Salvar'));
      await settle(tester);
      var draft = env.workspace.saved.last.$2;
      expect(draft.clearIcon, isTrue);
      expect(draft.iconSource, isNull);

      await env.ask(tester, const EditWorkspace('w1', 'Duck'));
      env.picker.nextImage = '/nova.png';
      await tester.tap(find.text('Imagem…'));
      await settle(tester);
      await tester.tap(find.text('Salvar'));
      await settle(tester);
      draft = env.workspace.saved.last.$2;
      expect(draft.iconSource, '/nova.png');
      expect(draft.clearIcon, isFalse);
    });

    testWidgets('multi-projeto sem pastas no workspace avisa e não abre', (
      tester,
    ) async {
      final env = await mount(tester);
      await env.ask(tester, const NewWorkspace());
      await tester.tap(find.text('Novo multi-projeto…'));
      await settle(tester);
      expect(find.textContaining('Adicione antes as pastas'), findsOneWidget);
      await tester.tap(find.text('Entendi'));
      await settle(tester);
      expect(find.text('Novo workspace'), findsOneWidget);
    });

    testWidgets('onde se clica, o ponteiro diz', (tester) async {
      final env = await mount(tester);
      await env.ask(tester, const NewWorkspace());
      expectHandOnEveryClickable(tester);
    });
  });

  group('projeto novo', () {
    testWidgets('nome, destino sugerido e git vão ao core', (tester) async {
      final env = await mount(tester);
      env.workspace.parent = '~/code';
      await env.ask(tester, const NewProject('w1', 'Duck'));
      expect(find.text('Novo projeto em "Duck"'), findsOneWidget);
      expect(find.text('~/code'), findsOneWidget);

      tester.testTextInput.enterText('meu-app');
      await tester.pump();
      await tester.tap(find.text('Criar'));
      await settle(tester);
      expect(env.workspace.created, ['meu-app@~/code/true']);
    });

    testWidgets('Escolher… troca o destino e git desmarca', (tester) async {
      final env = await mount(tester);
      await env.ask(tester, const NewProject('w1', 'Duck'));
      env.picker.nextFolder = '/Users/x/projetos';
      await tester.tap(find.text('Escolher…'));
      await settle(tester);
      expect(find.text('/Users/x/projetos'), findsOneWidget);
      expect(env.picker.asked.single, 'pasta@~/code');

      await tester.tap(find.byKey(const ValueKey('git-box')));
      await tester.pump();
      // O checkbox do DS leva o foco ao ser clicado; o nome volta ao campo.
      await tester.tap(find.byType(EditableText).first);
      await tester.pump();
      tester.testTextInput.enterText('app');
      await tester.pump();
      await tester.tap(find.text('Criar'));
      await settle(tester);
      expect(env.workspace.created, ['app@/Users/x/projetos/false']);
    });

    testWidgets(
      'a recusa do core volta ao formulário, com o que foi digitado',
      (tester) async {
        final env = await mount(tester);
        await env.ask(tester, const NewProject('w1', 'Duck'));
        tester.testTextInput.enterText('app/../x');
        await tester.pump();

        env.workspace.refuse = 'O nome não pode ter barra.';
        await tester.tap(find.text('Criar'));
        await settle(tester);
        await tester.pump();
        expect(find.text('O nome não pode ter barra.'), findsOneWidget);
        expect(find.text('app/../x'), findsOneWidget);

        env.workspace.refuse = null;
        tester.testTextInput.enterText('app');
        await tester.pump();
        await tester.tap(find.text('Criar'));
        await settle(tester);
        expect(env.workspace.created, ['app@~/code/true']);
      },
    );

    testWidgets('cancelar não cria nada', (tester) async {
      final env = await mount(tester);
      await env.ask(tester, const NewProject('w1', 'Duck'));
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect(env.workspace.created, isEmpty);
    });
  });
}
