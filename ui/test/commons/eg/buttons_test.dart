import 'package:egeon_deck/commons/widgets/eg/button.dart';
import 'package:egeon_deck/commons/widgets/eg/eg_icon.dart';
import 'package:egeon_deck/commons/widgets/eg/icon_button.dart';
import 'package:egeon_deck/commons/widgets/eg/spinner.dart';
import 'package:egeon_deck/commons/widgets/eg/tool_button.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:egeon_deck/theme/egeon_tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';

const _c = EgeonColors.dark;

BoxDecoration _decoration(WidgetTester tester, Finder within) {
  final box = tester.widget<AnimatedContainer>(
    find.descendant(of: within, matching: find.byType(AnimatedContainer)),
  );
  return box.decoration! as BoxDecoration;
}

Future<TestGesture> _hover(WidgetTester tester, Finder target) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 100));
  return mouse;
}

void main() {
  spinnerGeometry();
  group('Button', () {
    for (final (kind, rest, hover, pressed) in [
      (ButtonKind.primary, _c.primary, _c.primaryHover, _c.primaryPressed),
      (ButtonKind.secondary, _c.carbon, _c.steel, _c.steelActive),
      (ButtonKind.ghost, const Color(0x00000000), _c.steel, _c.steelActive),
      (ButtonKind.danger, _c.carbon, _c.dangerSoft, _c.dangerSoft),
      (ButtonKind.dangerSolid, _c.danger, _c.dangerHover, _c.dangerPressed),
    ]) {
      testWidgets('${kind.name}: repouso, hover e pressionado', (tester) async {
        await tester.pumpWidget(
          egHost(Button(label: 'Salvar', kind: kind, onPressed: () {})),
        );
        final finder = find.byType(Button);
        expect(_decoration(tester, finder).color, rest);

        final mouse = await _hover(tester, finder);
        expect(_decoration(tester, finder).color, hover);

        await mouse.down(tester.getCenter(finder));
        await tester.pump(const Duration(milliseconds: 100));
        expect(_decoration(tester, finder).color, pressed);
        await mouse.up();
        await mouse.removePointer();
      });
    }

    testWidgets('perigo sólido: texto onDanger e sem anel de foco', (
      tester,
    ) async {
      await tester.pumpWidget(
        egHost(
          Button(
            label: 'Excluir',
            kind: ButtonKind.dangerSolid,
            size: ButtonSize.lg,
            onPressed: () {},
            autofocus: true,
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.widget<Text>(find.text('Excluir')).style!.color,
        _c.onDanger,
      );
      final border = _decoration(tester, find.byType(Button)).border;
      expect((border as Border?)?.top.width ?? 0, isNot(EgeonBorder.focus));
    });

    testWidgets('ícone à direita, atalho em chip e ligado', (tester) async {
      await tester.pumpWidget(
        egHost(
          Button(
            label: 'Enviar',
            iconRight: EgIcons.chevronDown,
            kbd: '⌘↵',
            selected: true,
            kind: ButtonKind.ghost,
            onPressed: () {},
          ),
        ),
      );
      expect(find.text('⌘↵'), findsOneWidget);
      expect(
        tester.widgetList<EgIcon>(find.byType(EgIcon)).single.icon,
        EgIcons.chevronDown,
      );
      expect(_decoration(tester, find.byType(Button)).color, _c.accentSoft);
    });

    testWidgets(
      'fio de luz no topo: 10% no primário, 4% no secundário e no perigo',
      (tester) async {
        double? top(ButtonKind kind) {
          final finder = find.descendant(
            of: find.byType(Button),
            matching: find.byWidgetPredicate(
              (w) => w is ColoredBox && w.color.a < 0.2 && w.color.a > 0,
            ),
          );
          return finder.evaluate().isEmpty
              ? null
              : tester.widget<ColoredBox>(finder.first).color.a;
        }

        for (final (kind, alpha) in [
          (ButtonKind.primary, 0.10),
          (ButtonKind.secondary, 0.04),
          (ButtonKind.danger, 0.04),
          (ButtonKind.ghost, null),
          (ButtonKind.dangerSolid, null),
        ]) {
          await tester.pumpWidget(
            egHost(Button(label: 'x', kind: kind, onPressed: () {})),
          );
          final a = top(kind);
          if (alpha == null) {
            expect(a, isNull, reason: kind.name);
          } else {
            expect(a, closeTo(alpha, 0.005), reason: kind.name);
          }
        }
      },
    );

    testWidgets('altura por tamanho: 30, 36 e 42', (tester) async {
      for (final size in ButtonSize.values) {
        await tester.pumpWidget(
          egHost(Button(label: 'Ok', size: size, onPressed: () {})),
        );
        expect(
          tester.getSize(find.byType(AnimatedContainer)).height,
          size.height,
        );
      }
      expect(ButtonSize.values.map((s) => s.height), [
        EgeonSize.controlSm,
        EgeonSize.controlMd,
        EgeonSize.controlLg,
      ]);
    });

    testWidgets('focado, o botão não ganha anel', (tester) async {
      await tester.pumpWidget(
        egHost(Button(label: 'Salvar', onPressed: () {}, autofocus: true)),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 100));
      final border = _decoration(tester, find.byType(Button)).border;
      expect((border as Border?)?.top.width ?? 0, isNot(EgeonBorder.focus));
    });

    testWidgets('clicar não deixa o foco no botão', (tester) async {
      await tester.pumpWidget(
        egHost(Button(label: 'Salvar', onPressed: () {})),
      );
      await tester.tap(find.byType(Button));
      await tester.pump();
      final focus = Focus.of(tester.element(find.text('Salvar')));
      expect(focus.hasFocus, isFalse);
    });

    testWidgets('Enter e Espaço ativam, o clique também', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        egHost(
          Button(label: 'Salvar', onPressed: () => taps++, autofocus: true),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.tap(find.byType(Button));
      expect(taps, 3);
    });

    testWidgets('desabilitado: 40% de opacidade e não responde', (
      tester,
    ) async {
      await tester.pumpWidget(
        egHost(const Button(label: 'Salvar', onPressed: null)),
      );
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(Button),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, EgeonOpacity.disabled);
      await tester.tap(find.byType(Button));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'carregando: spinner no lugar do ícone, mesmo tamanho, sem clique',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          egHost(
            Button(
              label: 'Salvar',
              icon: EgIcons.check,
              onPressed: () => taps++,
            ),
          ),
        );
        final normal = tester.getSize(find.byType(Button));
        await tester.pumpWidget(
          egHost(
            Button(
              label: 'Salvar',
              icon: EgIcons.check,
              loading: true,
              onPressed: () => taps++,
            ),
          ),
        );
        expect(find.byType(Spinner), findsOneWidget);
        expect(find.byType(EgIcon), findsNothing);
        expect(tester.getSize(find.byType(Button)), normal);
        await tester.tap(find.byType(Button));
        expect(taps, 0);
      },
    );

    testWidgets('carregando sem ícone também não muda de tamanho', (
      tester,
    ) async {
      await tester.pumpWidget(
        egHost(Button(label: 'Salvar', onPressed: () {})),
      );
      final normal = tester.getSize(find.byType(Button));
      await tester.pumpWidget(
        egHost(Button(label: 'Salvar', loading: true, onPressed: () {})),
      );
      expect(tester.getSize(find.byType(Button)), normal);
      expect(find.byType(Spinner), findsOneWidget);
    });

    testWidgets(
      'mão no ponteiro quando clicável, nenhuma quando desabilitado',
      (tester) async {
        Future<MouseCursor> cursorOver(Widget button) async {
          await tester.pumpWidget(egHost(button));
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(
            location: tester.getCenter(find.byType(Button)),
          );
          await tester.pump();
          final cursor = RendererBinding.instance.mouseTracker
              .debugDeviceActiveCursor(1);
          await mouse.removePointer();
          return cursor!;
        }

        expect(
          await cursorOver(Button(label: 'Ok', onPressed: () {})),
          SystemMouseCursors.click,
        );
        expect(
          await cursorOver(const Button(label: 'Ok', onPressed: null)),
          isNot(SystemMouseCursors.click),
        );
      },
    );
  });

  group('IconButton e ToolButton', () {
    testWidgets('36 quadrado, 30 no compacto', (tester) async {
      await tester.pumpWidget(
        egHost(
          IconButton(icon: EgIcons.plus, tooltip: 'Novo', onPressed: () {}),
        ),
      );
      expect(tester.getSize(find.byType(IconButton)), const Size(36, 36));
      await tester.pumpWidget(
        egHost(
          IconButton(
            icon: EgIcons.plus,
            tooltip: 'Novo',
            compact: true,
            onPressed: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(IconButton)), const Size(30, 30));
    });

    testWidgets('hover steel, pressionado steelActive', (tester) async {
      await tester.pumpWidget(
        egHost(
          IconButton(icon: EgIcons.plus, tooltip: 'Novo', onPressed: () {}),
        ),
      );
      final finder = find.byType(IconButton);
      expect(_decoration(tester, finder).color, const Color(0x00000000));
      final mouse = await _hover(tester, finder);
      expect(_decoration(tester, finder).color, _c.steel);
      await mouse.down(tester.getCenter(finder));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_decoration(tester, finder).color, _c.steelActive);
      await mouse.up();
      await mouse.removePointer();
    });

    testWidgets('ToolButton ligado: accentSoft com ícone accent', (
      tester,
    ) async {
      await tester.pumpWidget(
        egHost(
          ToolButton(
            icon: EgIcons.pointer,
            tooltip: 'Selecionar',
            selected: true,
            onPressed: () {},
          ),
        ),
      );
      expect(_decoration(tester, find.byType(ToolButton)).color, _c.accentSoft);
      final icon = tester.widget<EgIcon>(find.byType(EgIcon));
      expect(icon.color, _c.accent);
    });

    testWidgets('desabilitado: 40% e sem toque', (tester) async {
      await tester.pumpWidget(
        egHost(
          const IconButton(
            icon: EgIcons.plus,
            tooltip: 'Novo',
            onPressed: null,
          ),
        ),
      );
      expect(
        tester
            .widget<Opacity>(
              find.descendant(
                of: find.byType(IconButton),
                matching: find.byType(Opacity),
              ),
            )
            .opacity,
        EgeonOpacity.disabled,
      );
    });

    testWidgets('focado, não ganha anel', (tester) async {
      await tester.pumpWidget(
        egHost(
          ToolButton(
            icon: EgIcons.pointer,
            tooltip: 'Selecionar',
            onPressed: () {},
            autofocus: true,
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 100));
      final border = _decoration(tester, find.byType(ToolButton)).border;
      expect((border as Border?)?.top.width ?? 0, isNot(EgeonBorder.focus));
    });
  });
}

void spinnerGeometry() {
  testWidgets('Spinner: 14 por padrão e traço 1.75 do DS', (tester) async {
    await tester.pumpWidget(egHost(const Spinner()));
    expect(tester.getSize(find.byType(Spinner)), const Size(14, 14));
    expect(spinnerStroke, 1.75);
    await tester.pumpWidget(const SizedBox());
  });
}
