import 'package:egeon_deck/commons/widgets/web_surface.dart';
import 'package:egeon_deck/features/node/card/presentation/widgets/card_motion.dart';

import '../../../support/in_memory_web_repository.dart';

import 'package:egeon_deck/core/adapters/injector.dart';
import 'package:egeon_deck/features/node/web/presentation/cubit/web_capture_registry.dart';
import 'package:egeon_deck/features/node/web/presentation/widgets/web_body.dart';
import 'package:egeon_deck/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_web_surface.dart';
import '../../../support/inject_fakes.dart';

void main() {
  late InMemoryWebRepository repository;
  late List<FakeWebSurface> surfaces;
  var live = true;

  Future<void> pumpWeb(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(900, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    surfaces = [];
    repository = InMemoryWebRepository();
    injectFakes(
      web: (_) => repository,
      createWebController: (profile, _) {
        final surface = FakeWebSurface(profile);
        surfaces.add(surface);
        return surface;
      },
    );
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        textStyle: AppTheme.textStyle,
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        ),
        home: StatefulBuilder(
          builder: (context, setState) => CardMotion(
            live: live,
            child: const WebBody(workbenchId: 'bancada', nodeId: 'web1'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  setUp(() => live = true);

  testWidgets('abre a página do perfil do nó na URL que o core guardou', (
    tester,
  ) async {
    await pumpWeb(tester);
    expect(surfaces, hasLength(1));
    expect(surfaces.single.profile, 'pessoal');
    expect(surfaces.single.loaded, ['https://www.google.com']);
    expect(find.byKey(const ValueKey('native-view')), findsOneWidget);
    expect(find.text('pessoal'), findsOneWidget);
  });

  testWidgets(
    'digitar na barra manda o texto cru; o core normaliza e a página carrega',
    (tester) async {
      await pumpWeb(tester);
      await tester.tap(find.byKey(const ValueKey('address-field')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('address-field')),
        'docs.rs',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(surfaces.single.loaded.last, 'https://docs.rs');
    },
  );

  testWidgets('texto que não parece endereço vira busca', (tester) async {
    await pumpWeb(tester);
    await tester.tap(find.byKey(const ValueKey('address-field')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('address-field')),
      'flutter webview',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump();
    expect(surfaces.single.loaded.last, contains('search?q=flutter+webview'));
  });

  testWidgets('a página navega sozinha: a barra acompanha e o core grava', (
    tester,
  ) async {
    await pumpWeb(tester);
    surfaces.single.navigate(
      const WebPageState(url: 'https://docs.rs/serde', canGoBack: true),
    );
    await tester.pump();
    await tester.pump();
    final field = tester.widget<EditableText>(
      find.byKey(const ValueKey('address-field')),
    );
    expect(field.controller.text, 'https://docs.rs/serde');
    expect(repository.reported, ['https://docs.rs/serde']);
    // E o eco do core não manda a página carregar de novo o que ela já mostra.
    expect(surfaces.single.loaded, ['https://www.google.com']);
  });

  testWidgets('voltar, avançar e recarregar só valem quando a página deixa', (
    tester,
  ) async {
    await pumpWeb(tester);
    await tester.tap(find.byKey(const ValueKey('web-back')));
    expect(surfaces.single.backs, 0);

    surfaces.single.navigate(
      const WebPageState(
        url: 'https://a.com',
        canGoBack: true,
        canGoForward: true,
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('web-back')));
    await tester.tap(find.byKey(const ValueKey('web-forward')));
    await tester.tap(find.byKey(const ValueKey('web-reload')));
    expect(surfaces.single.backs, 1);
    expect(surfaces.single.forwards, 1);
    expect(surfaces.single.reloads, 1);
  });

  testWidgets(
    'trocar de perfil joga a página fora e monta outra na mesma URL',
    (tester) async {
      await pumpWeb(tester);
      await tester.tap(find.byKey(const ValueKey('web-profile')));
      await tester.pump();
      await tester.tap(find.text('trabalho'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(surfaces, hasLength(2));
      expect(surfaces.first.disposed, isTrue);
      expect(surfaces.last.profile, 'trabalho');
      expect(surfaces.last.loaded, ['https://www.google.com']);
    },
  );

  testWidgets('com zoom ou canvas em movimento, mostra a última captura', (
    tester,
  ) async {
    await pumpWeb(tester);
    expect(find.byKey(const ValueKey('native-view')), findsOneWidget);

    live = false;
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        textStyle: AppTheme.textStyle,
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        ),
        home: CardMotion(
          live: false,
          child: const WebBody(workbenchId: 'bancada', nodeId: 'web1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('native-view')), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a página viva se registra para o /shot e sai com o nó', (
    tester,
  ) async {
    await pumpWeb(tester);
    final captures = inject<WebCaptureRegistry>();
    expect(await tester.runAsync(() => captures.capture('web1')), isNotNull);
    expect(await captures.capture('outro'), isNull);

    // Trocar de perfil: a página nova assume o registro.
    await tester.tap(find.byKey(const ValueKey('web-profile')));
    await tester.pump();
    await tester.tap(find.text('trabalho'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(surfaces, hasLength(2));
    expect(await tester.runAsync(() => captures.capture('web1')), isNotNull);

    await tester.pumpWidget(const SizedBox());
    expect(await captures.capture('web1'), isNull);
  });

  testWidgets('mão em tudo que responde a clique', (tester) async {
    await pumpWeb(tester);
    surfaces.single.navigate(
      const WebPageState(
        url: 'https://a.com',
        canGoBack: true,
        canGoForward: true,
      ),
    );
    await tester.pump();
    await tester.pump();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    for (final key in [
      'web-back',
      'web-forward',
      'web-reload',
      'web-profile',
    ]) {
      await mouse.moveTo(tester.getCenter(find.byKey(ValueKey(key))));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
        reason: '$key responde a clique',
      );
    }
  });
}
