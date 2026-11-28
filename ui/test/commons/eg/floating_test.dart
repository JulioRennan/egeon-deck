import 'package:egeon_deck/commons/widgets/eg/agent_name.dart';
import 'package:egeon_deck/commons/widgets/eg/button.dart';
import 'package:egeon_deck/commons/widgets/eg/dialog.dart';
import 'package:egeon_deck/commons/widgets/eg/eg_icon.dart';
import 'package:egeon_deck/commons/widgets/eg/glass_surface.dart';
import 'package:egeon_deck/commons/widgets/eg/icon_button.dart';
import 'package:egeon_deck/commons/widgets/eg/identity.dart';
import 'package:egeon_deck/commons/widgets/eg/kbd.dart';
import 'package:egeon_deck/commons/widgets/eg/spinner.dart';
import 'package:egeon_deck/commons/widgets/eg/layer.dart';
import 'package:egeon_deck/commons/widgets/eg/menu.dart';
import 'package:egeon_deck/commons/widgets/eg/popover.dart';
import 'package:egeon_deck/commons/widgets/eg/toast.dart';
import 'package:egeon_deck/commons/widgets/eg/tooltip.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:egeon_deck/theme/egeon_tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';

const _c = EgeonColors.dark;

/// Um botão que abre o que o teste pede, no lugar em que o teste o põe.
class _Opener extends StatelessWidget {
  const _Opener(this.open, {this.left = 100, this.top = 100});

  final void Function(BuildContext context, Rect anchor) open;
  final double left, top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: left, top: top),
    child: Builder(
      builder: (context) => Button(
        label: 'Abrir',
        onPressed: () => open(context, globalRectOf(context)),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

void main() {
  group('GlassSurface', () {
    testEg('desfoca o fundo e pinta o vidro e o fio de luz', (tester) async {
      await tester.pumpWidget(
        egHost(const GlassSurface(child: SizedBox(width: 80, height: 40))),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
      final decorations = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>();
      expect(decorations.any((d) => d.boxShadow == EgeonShadow.glass), isTrue);
    });
  });

  group('Popover', () {
    testEg('abre ancorado, desce da âncora e fecha com Esc', (tester) async {
      await tester.pumpWidget(
        egHost(
          _Opener(
            (context, anchor) => showPopover(
              context,
              anchor: anchor,
              builder: (_, _) => const Text('conteúdo'),
            ),
          ),
        ),
      );
      await _open(tester);
      final anchor = tester.getRect(find.byType(Button));
      final box = tester.getRect(find.byType(GlassSurface));
      expect(box.top, anchor.bottom + 6);
      expect(box.left, anchor.left);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('conteúdo'), findsNothing);
    });

    testEg('radius e gap trocam o raio do vidro e o vão da âncora', (
      tester,
    ) async {
      await tester.pumpWidget(
        egHost(
          _Opener(
            (context, anchor) => showPopover(
              context,
              anchor: anchor,
              radius: 16,
              gap: 8,
              builder: (_, _) => const Text('conteúdo'),
            ),
          ),
        ),
      );
      await _open(tester);
      final anchor = tester.getRect(find.byType(Button));
      expect(tester.getRect(find.byType(GlassSurface)).top, anchor.bottom + 8);
      expect(tester.widget<GlassSurface>(find.byType(GlassSurface)).radius, 16);
    });

    testEg('clique fora fecha, clique dentro não', (tester) async {
      await tester.pumpWidget(
        egHost(
          _Opener(
            (context, anchor) => showPopover(
              context,
              anchor: anchor,
              builder: (_, _) => const Text('conteúdo'),
            ),
          ),
        ),
      );
      await _open(tester);
      await tester.tapAt(tester.getCenter(find.text('conteúdo')));
      await tester.pumpAndSettle();
      expect(find.text('conteúdo'), findsOneWidget);
      await tester.tapAt(const Offset(700, 600));
      await tester.pumpAndSettle();
      expect(find.text('conteúdo'), findsNothing);
    });

    testEg('sem espaço embaixo, sobe', (tester) async {
      await tester.pumpWidget(
        egHost(
          _Opener(
            top: 740,
            (context, anchor) => showPopover(
              context,
              anchor: anchor,
              builder: (_, _) => const SizedBox(height: 100, child: Text('x')),
            ),
          ),
        ),
      );
      await _open(tester);
      final anchor = tester.getRect(find.byType(Button));
      final box = tester.getRect(find.byType(GlassSurface));
      expect(box.bottom, anchor.top - 6);
    });

    testEg('na borda direita encosta com 8px de margem', (tester) async {
      await tester.pumpWidget(
        egHost(
          _Opener(
            left: 880,
            (context, anchor) => showPopover(
              context,
              anchor: anchor,
              width: 200,
              builder: (_, _) => const Text('x'),
            ),
          ),
        ),
      );
      await _open(tester);
      expect(tester.getRect(find.byType(GlassSurface)).right, 1000 - 8);
    });

    testEg('movimento reduzido: já nasce opaco', (tester) async {
      await tester.pumpWidget(
        egHost(
          reduceMotion: true,
          _Opener(
            (context, anchor) => showPopover(
              context,
              anchor: anchor,
              builder: (_, _) => const Text('conteúdo'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pump();
      await tester.pump();
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byType(GlassSurface),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, 1);
    });
  });

  group('Menu', () {
    List<MenuElement> items(List<String> log) => [
      MenuItem('Renomear', icon: EgIcons.edit, onSelected: () => log.add('r')),
      MenuItem('Duplicar', shortcut: '⌘D', onSelected: () => log.add('d')),
      const MenuItem('Em breve'),
      const MenuSeparator(),
      MenuItem(
        'Remover',
        icon: EgIcons.trash,
        danger: true,
        onSelected: () => log.add('x'),
      ),
    ];

    Widget host(List<String> log) => egHost(
      _Opener(
        (context, anchor) =>
            showMenu(context, anchor: anchor, items: items(log)),
      ),
    );

    testEg('linhas de 32, atalho à direita', (tester) async {
      await tester.pumpWidget(host([]));
      await _open(tester);
      final row = find.ancestor(
        of: find.text('Renomear'),
        matching: find.byType(SizedBox),
      );
      expect(tester.getSize(row.first).height, EgeonSize.row);
      expect(find.widgetWithText(Kbd, '⌘D'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('⌘D')).dx,
        greaterThan(tester.getTopLeft(find.text('Duplicar')).dx),
      );
    });

    testEg('escolher chama a ação e fecha', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(host(log));
      await _open(tester);
      await tester.tap(find.text('Duplicar'));
      await tester.pumpAndSettle();
      expect(log, ['d']);
      expect(find.text('Duplicar'), findsNothing);
    });

    testEg('linha sem ação não escolhe nem fecha', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(host(log));
      await _open(tester);
      await tester.tap(find.text('Em breve'));
      await tester.pumpAndSettle();
      expect(log, isEmpty);
      expect(find.text('Em breve'), findsOneWidget);
    });

    testEg('setas movem o foco e Enter escolhe', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(host(log));
      await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      // Renomear (foco inicial) → Duplicar → Remover (a sem ação é pulada).
      expect(log, ['x']);
    });

    testEg('perigo: texto danger e hover dangerSoft', (tester) async {
      await tester.pumpWidget(host([]));
      await _open(tester);
      final text = tester.widget<Text>(find.text('Remover'));
      expect(text.style!.color, _c.danger);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Remover')));
      await tester.pump();
      final bg = tester
          .widgetList<DecoratedBox>(
            find.ancestor(
              of: find.text('Remover'),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((d) => (d.decoration as BoxDecoration).color)
          .whereType<Color>();
      expect(bg, contains(_c.dangerSoft));
      await mouse.removePointer();
    });

    testEg('é de vidro e fecha com Esc', (tester) async {
      await tester.pumpWidget(host([]));
      await _open(tester);
      expect(find.byType(GlassSurface), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Renomear'), findsNothing);
    });
  });

  group('Menu — grupos, check, descrição e submenu', () {
    testEg('header, coluna de check, desc e chevron do submenu', (
      tester,
    ) async {
      await tester.pumpWidget(
        egHost(
          Menu(
            items: [
              const MenuHeader('Cor da bancada'),
              MenuItem(
                'Sky',
                checked: true,
                identity: Identity.sky,
                onSelected: () {},
              ),
              MenuItem(
                'Iris',
                checked: false,
                desc: 'padrão',
                onSelected: () {},
              ),
              MenuItem('Mais', submenu: true, onSelected: () {}),
            ],
          ),
        ),
      );
      expect(find.text('Cor da bancada'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Cor da bancada')).style!.color,
        _c.textMuted,
      );
      expect(
        find.byWidgetPredicate((w) => w is EgIcon && w.icon.name == 'check'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is EgIcon && w.icon.name == 'chevron-right',
        ),
        findsOneWidget,
      );
      expect(find.text('padrão'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Sky')).style!.color, _c.idSky);
      // A coluna de check alinha os rótulos: Sky e Iris começam no mesmo x.
      expect(
        tester.getTopLeft(find.text('Sky')).dx,
        tester.getTopLeft(find.text('Iris')).dx,
      );
    });

    testEg('sem nenhum check, não há coluna reservada', (tester) async {
      await tester.pumpWidget(
        egHost(Menu(items: [MenuItem('A', onSelected: () {})])),
      );
      expect(tester.getTopLeft(find.text('A')).dx, lessThan(6 + 12 + 1));
    });
  });

  group('Layer', () {
    testEg('ao fechar, o foco volta a quem o tinha', (tester) async {
      await tester.pumpWidget(
        egHost(
          Builder(
            builder: (context) => Button(
              label: 'Abrir',
              autofocus: true,
              onPressed: () => showPopover(
                context,
                anchor: globalRectOf(context),
                builder: (_, _) => const Text('conteúdo'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final before = FocusManager.instance.primaryFocus;
      expect(before, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('conteúdo'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, isNot(before));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('conteúdo'), findsNothing);
      expect(FocusManager.instance.primaryFocus, before);
    });
  });

  group('Dialog', () {
    Widget host(void Function(Object? result) onResult) => egHost(
      _Opener((context, _) async {
        onResult(
          await showEgDialog<String>(
            context,
            builder: (context, close) => Dialog(
              title: 'Limpar o contexto?',
              actions: [
                Button(label: 'Cancelar', onPressed: () => close()),
                Button(
                  label: 'Limpar',
                  kind: ButtonKind.primary,
                  onPressed: () => close('limpar'),
                ),
              ],
              child: const Text('O agente perde a conversa.'),
            ),
          ),
        );
      }),
    );

    testEg('centrado, sólido, raio 14, shadow modal e scrim', (tester) async {
      await tester.pumpWidget(host((_) {}));
      await _open(tester);
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find
                        .ancestor(
                          of: find.text('O agente perde a conversa.'),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.color, _c.carbon);
      expect(decoration.boxShadow, EgeonShadow.modal);
      expect(decoration.borderRadius, BorderRadius.circular(EgeonRadius.xl));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(
        tester.getCenter(find.text('Limpar o contexto?')).dx,
        closeTo(500, 40),
      );
      final scrim = find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == _c.scrim,
      );
      expect(scrim, findsOneWidget);
    });

    testEg('a ação devolve o resultado e fecha', (tester) async {
      Object? result = 'nada';
      await tester.pumpWidget(host((r) => result = r));
      await _open(tester);
      await tester.tap(find.text('Limpar'));
      await tester.pumpAndSettle();
      expect(result, 'limpar');
      expect(find.text('Limpar o contexto?'), findsNothing);
    });

    testEg('Esc e clique fora devolvem null', (tester) async {
      Object? result = 'nada';
      await tester.pumpWidget(host((r) => result = r));
      await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(result, isNull);

      result = 'nada';
      await _open(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('Limpar o contexto?'), findsNothing);
    });

    testEg('o foco fica preso: Tab dá a volta nos botões do diálogo', (
      tester,
    ) async {
      await tester.pumpWidget(
        egHost(
          Column(
            children: [
              _Opener(
                (context, _) => showEgDialog<void>(
                  context,
                  builder: (context, close) => Dialog(
                    title: 'T',
                    actions: [
                      Button(label: 'Um', onPressed: () {}),
                      Button(label: 'Dois', onPressed: () {}),
                    ],
                    child: const Text('c'),
                  ),
                ),
              ),
              Button(label: 'Fundo', onPressed: () {}),
            ],
          ),
        ),
      );
      await _open(tester);
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus!;
        final inDialog = find
            .ancestor(of: find.text('Um'), matching: find.byType(Dialog))
            .evaluate()
            .isNotEmpty;
        expect(inDialog, isTrue);
        final fundo = tester.getRect(find.text('Fundo'));
        expect(focused.rect.overlaps(fundo), isFalse, reason: 'tab $i');
      }
    });

    testEg('barrierDismissible falso ignora Esc', (tester) async {
      await tester.pumpWidget(
        egHost(
          _Opener(
            (context, _) => showEgDialog<void>(
              context,
              barrierDismissible: false,
              builder: (context, close) =>
                  const Dialog(title: 'T', child: Text('c')),
            ),
          ),
        ),
      );
      await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('T'), findsOneWidget);
    });
  });

  group('Toast', () {
    testEg('aparece no pé, some sozinho e o novo toma o lugar', (tester) async {
      await tester.pumpWidget(
        egHost(
          _Opener(
            (context, _) => showToast(
              context,
              title: 'Salvo',
              tone: ToastTone.success,
              duration: const Duration(seconds: 2),
            ),
          ),
        ),
      );
      await _open(tester);
      expect(find.text('Salvo'), findsOneWidget);
      expect(tester.getCenter(find.text('Salvo')).dy, greaterThan(700));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Salvo'), findsNothing);
    });

    testEg('cada tom tem o seu ícone e a sua cor', (tester) async {
      final expected = {
        ToastTone.attention: (EgIcons.hand, _c.attention),
        ToastTone.success: (EgIcons.check, _c.success),
        ToastTone.danger: (EgIcons.octagon, _c.danger),
        ToastTone.info: (EgIcons.info, _c.textSecondary),
      };
      for (final entry in expected.entries) {
        await tester.pumpWidget(
          egHost(Toast(title: 'x', tone: entry.key, onDismiss: () {})),
        );
        final icon = tester
            .widgetList<EgIcon>(find.byType(EgIcon))
            .firstWhere((i) => i.icon.name != EgIcons.x.name);
        expect(icon.icon, entry.value.$1, reason: entry.key.name);
        expect(icon.color, entry.value.$2, reason: entry.key.name);
      }
      await tester.pumpWidget(
        egHost(const Toast(title: 'x', tone: ToastTone.running)),
      );
      expect(tester.widget<Spinner>(find.byType(Spinner)).size, 16);
      await tester.pumpWidget(const SizedBox());
    });

    testEg('título, descrição, agente na cor e ações', (tester) async {
      await tester.pumpWidget(
        egHost(
          Toast(
            title: 'terminou',
            description: 'Pronto para revisar.',
            agent: const Person('maestro', identity: Identity.iris),
            actions: [Button(label: 'Ver', onPressed: () {})],
            onDismiss: () {},
          ),
        ),
      );
      expect(find.text('Pronto para revisar.'), findsOneWidget);
      expect(find.text('Ver'), findsOneWidget);
      final name = tester.widget<Text>(find.byType(Text).first);
      final span = (name.textSpan! as TextSpan).children!.first;
      expect(span, isA<WidgetSpan>());
      final agent = tester.widget<AgentName>(find.byType(AgentName));
      expect(agent.name, 'maestro');
    });

    testEg('Dispensar fecha o aviso antes do tempo', (tester) async {
      await tester.pumpWidget(
        egHost(_Opener((context, _) => showToast(context, title: 'Arquivada'))),
      );
      await _open(tester);
      expect(find.text('Arquivada'), findsOneWidget);
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(find.text('Arquivada'), findsNothing);
    });

    testEg('não rouba o clique de quem está por baixo', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        egHost(
          Column(
            children: [
              _Opener((context, _) => showToast(context, title: 'Oi')),
              Button(label: 'Embaixo', onPressed: () => taps++),
            ],
          ),
        ),
      );
      await _open(tester);
      await tester.tap(find.text('Embaixo'));
      await tester.pump();
      expect(taps, 1);
      expect(find.text('Oi'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testEg('a ação recebe o close do aviso', (tester) async {
      var seen = false;
      await tester.pumpWidget(
        egHost(
          _Opener(
            (context, _) => showToast(
              context,
              title: 'Arquivada',
              actions: (close) => [
                Button(
                  label: 'Desfazer',
                  onPressed: () {
                    seen = true;
                    close();
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await _open(tester);
      await tester.tap(find.text('Desfazer'));
      await tester.pumpAndSettle();
      expect(seen, isTrue);
      expect(find.text('Arquivada'), findsNothing);
    });

    testEg('um de cada vez', (tester) async {
      await tester.pumpWidget(
        egHost(
          Column(
            children: [
              _Opener((context, _) => showToast(context, title: 'Um')),
              _Opener(
                (context, _) => showToast(context, title: 'Dois'),
                top: 0,
              ),
            ],
          ),
        ),
      );
      final buttons = find.text('Abrir');
      await tester.tap(buttons.first);
      await tester.pump();
      await tester.tap(buttons.last);
      await tester.pumpAndSettle();
      expect(find.text('Um'), findsNothing);
      expect(find.text('Dois'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  });

  group('Tooltip', () {
    testEg('aparece depois de 500 ms parado e some ao sair', (tester) async {
      await tester.pumpWidget(
        egHost(
          const Padding(
            padding: EdgeInsets.all(100),
            child: Tooltip(
              message: 'Novo nó',
              shortcut: '⌘3',
              child: SizedBox(width: 36, height: 36),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(const Offset(118, 118));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Novo nó'), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('Novo nó'), findsOneWidget);
      expect(find.widgetWithText(Kbd, '⌘3'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Novo nó')).dy, greaterThan(136));
      await mouse.moveTo(const Offset(600, 600));
      await tester.pumpAndSettle();
      expect(find.text('Novo nó'), findsNothing);
      await mouse.removePointer();
    });

    testEg('IconButton traz a dica', (tester) async {
      await tester.pumpWidget(
        egHost(
          Padding(
            padding: const EdgeInsets.all(100),
            child: IconButton(
              icon: EgIcons.plus,
              tooltip: 'Adicionar',
              onPressed: () {},
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(const Offset(118, 118));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Adicionar'), findsOneWidget);
      await mouse.removePointer();
    });

    testEg('clicar esconde a dica', (tester) async {
      await tester.pumpWidget(
        egHost(
          const Padding(
            padding: EdgeInsets.all(100),
            child: Tooltip(
              message: 'Dica',
              child: SizedBox(width: 36, height: 36),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(const Offset(118, 118));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Dica'), findsOneWidget);
      await mouse.down(const Offset(118, 118));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.text('Dica'), findsNothing);
      await mouse.removePointer();
    });
  });
}
