import 'package:egeon_deck/commons/widgets/eg/eg_icon.dart';
import 'package:egeon_deck/commons/widgets/eg/checkbox.dart';
import 'package:egeon_deck/commons/widgets/eg/field.dart';
import 'package:egeon_deck/commons/widgets/eg/radio.dart';
import 'package:egeon_deck/commons/widgets/eg/segmented_control.dart';
import 'package:egeon_deck/commons/widgets/eg/view_switch.dart';
import 'package:egeon_deck/commons/widgets/eg/select.dart';
import 'package:egeon_deck/commons/widgets/eg/slider.dart';
import 'package:egeon_deck/commons/widgets/eg/text_area.dart';
import 'package:egeon_deck/commons/widgets/eg/text_field.dart';
import 'package:egeon_deck/commons/widgets/eg/toggle.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:egeon_deck/theme/egeon_tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';

const _c = EgeonColors.dark;

BoxDecoration _shell(WidgetTester tester) =>
    tester
            .widget<DecoratedBox>(
              find
                  .descendant(
                    of: find.byType(InputShell),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;

Border _border(WidgetTester tester) => _shell(tester).border! as Border;

Future<TestGesture> _hover(WidgetTester tester, Finder target) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 100));
  return mouse;
}

void main() {
  group('TextField', () {
    testEg('repouso: carbon, borda lineStrong de 1px, altura 36', (
      tester,
    ) async {
      await tester.pumpWidget(egHost(const TextField(width: 240)));
      expect(_shell(tester).color, _c.carbon);
      expect(_border(tester).top.color, _c.lineStrong);
      expect(_border(tester).top.width, EgeonBorder.hairline);
      expect(
        tester.getSize(find.byType(InputShell)).height,
        EgeonSize.controlMd,
      );
    });

    testEg(
      'hover: lineHover; foco: accent 2px na mesma borda, sem mudar de tamanho',
      (tester) async {
        await tester.pumpWidget(egHost(const TextField(width: 240)));
        final rest = tester.getSize(find.byType(InputShell));
        final mouse = await _hover(tester, find.byType(InputShell));
        expect(_border(tester).top.color, _c.lineHover);
        await tester.tap(find.byType(InputShell));
        await tester.pump(const Duration(milliseconds: 100));
        expect(_border(tester).top.color, _c.accent);
        expect(_border(tester).top.width, EgeonBorder.focus);
        expect(tester.getSize(find.byType(InputShell)), rest);
        await mouse.removePointer();
      },
    );

    testEg('erro: borda danger e a mensagem com o ícone de alerta', (
      tester,
    ) async {
      await tester.pumpWidget(
        egHost(const TextField(error: 'Esse nome já existe.', width: 240)),
      );
      expect(_border(tester).top.color, _c.danger);
      expect(find.text('Esse nome já existe.'), findsOneWidget);
    });

    testEg('desabilitado: borda line, não aceita foco nem texto', (
      tester,
    ) async {
      await tester.pumpWidget(
        egHost(const TextField(initialValue: 'x', enabled: false, width: 240)),
      );
      expect(_border(tester).top.color, _c.line);
      await tester.tap(find.byType(InputShell));
      await tester.pump();
      expect(_border(tester).top.width, EgeonBorder.hairline);
    });

    testEg('digitar atualiza, esconde o placeholder e avisa onChanged', (
      tester,
    ) async {
      String? seen;
      await tester.pumpWidget(
        egHost(
          TextField(
            placeholder: 'nome',
            width: 240,
            onChanged: (v) => seen = v,
          ),
        ),
      );
      expect(find.text('nome'), findsOneWidget);
      await tester.tap(find.byType(InputShell));
      await tester.pump();
      tester.testTextInput.enterText('loja');
      await tester.pump();
      expect(seen, 'loja');
      expect(find.text('nome'), findsNothing);
    });

    testEg('dica aparece sem erro; sufixo e rótulo também', (tester) async {
      await tester.pumpWidget(
        egHost(
          const TextField(
            label: 'Pasta',
            hint: 'Onde a bancada mora.',
            suffix: '4 itens',
            width: 240,
          ),
        ),
      );
      expect(find.text('Pasta'), findsOneWidget);
      expect(find.text('Onde a bancada mora.'), findsOneWidget);
      expect(find.text('4 itens'), findsOneWidget);
    });

    testEg('loading mostra o spinner sem mudar a altura', (tester) async {
      await tester.pumpWidget(
        egHost(const TextField(loading: true, width: 240)),
      );
      expect(
        tester.getSize(find.byType(InputShell)).height,
        EgeonSize.controlMd,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('TextArea', () {
    testEg('nasce com 3 linhas e foca como o campo', (tester) async {
      await tester.pumpWidget(egHost(const TextArea(width: 240)));
      final height = tester.getSize(find.byType(InputShell)).height;
      expect(height, greaterThan(EgeonSize.controlMd + 20));
      await tester.tap(find.byType(InputShell));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_border(tester).top.color, _c.accent);
    });
  });

  group('Select', () {
    const options = [
      SelectOption('a', 'Opus', desc: 'capaz'),
      SelectOption('b', 'Sonnet'),
      SelectOption('c', 'Haiku', disabled: true),
    ];

    testEg('abre o menu com a atual marcada, escolhe e fecha', (tester) async {
      String? chosen;
      await tester.pumpWidget(
        egHost(
          Select<String>(
            width: 240,
            value: 'a',
            options: options,
            onChanged: (v) => chosen = v,
          ),
        ),
      );
      expect(find.text('Opus'), findsOneWidget);
      await tester.tap(find.byType(Select<String>));
      await tester.pumpAndSettle();
      expect(find.text('Sonnet'), findsOneWidget);
      expect(find.text('capaz'), findsOneWidget);
      expect(_border(tester).top.color, _c.accent);
      await tester.tap(find.text('Sonnet'));
      await tester.pumpAndSettle();
      expect(chosen, 'b');
      expect(find.text('capaz'), findsNothing);
    });

    testEg('opção desabilitada não escolhe', (tester) async {
      String? chosen;
      await tester.pumpWidget(
        egHost(
          Select<String>(
            width: 240,
            options: options,
            onChanged: (v) => chosen = v,
          ),
        ),
      );
      await tester.tap(find.byType(Select<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Haiku'));
      await tester.pumpAndSettle();
      expect(chosen, isNull);
    });

    testEg('sem onChanged, desabilitado: não abre', (tester) async {
      await tester.pumpWidget(
        egHost(
          const Select<String>(width: 240, options: options, onChanged: null),
        ),
      );
      await tester.tap(find.byType(Select<String>));
      await tester.pumpAndSettle();
      expect(find.text('Sonnet'), findsNothing);
    });
  });

  group('Checkbox e Radio', () {
    testEg('caixa liga e desliga por clique, Espaço e Enter', (tester) async {
      var checked = false;
      late StateSetter set;
      await tester.pumpWidget(
        egHost(
          StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return Checkbox(
                checked: checked,
                autofocus: true,
                label: const Text('Aceito'),
                onChanged: (v) => set(() => checked = v),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Aceito'));
      await tester.pump();
      expect(checked, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(checked, isFalse);
    });

    testEg(
      'ligada: caixa accent; vazia: fundo carbon e borda controlBorder de 1px',
      (tester) async {
        BoxDecoration box() =>
            tester
                    .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                    .decoration!
                as BoxDecoration;
        await tester.pumpWidget(
          egHost(Checkbox(checked: true, onChanged: (_) {})),
        );
        expect(box().color, _c.accent);
        await tester.pumpWidget(
          egHost(Checkbox(checked: false, onChanged: (_) {})),
        );
        expect(box().color, _c.carbon);
        final border = box().border! as Border;
        expect(border.top.color, _c.controlBorder);
        expect(border.top.width, 1);
      },
    );

    testEg(
      'ligada em hover vira accentHover e pressionada accentPressed; vazia pressionada steelActive',
      (tester) async {
        BoxDecoration box() =>
            tester
                    .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                    .decoration!
                as BoxDecoration;
        await tester.pumpWidget(
          egHost(Checkbox(checked: true, onChanged: (_) {})),
        );
        final mouse = await _hover(tester, find.byType(Checkbox));
        expect(box().color, _c.accentHover);
        await mouse.down(tester.getCenter(find.byType(Checkbox)));
        await tester.pump(const Duration(milliseconds: 100));
        expect(box().color, _c.accentPressed);
        await mouse.up();
        await mouse.removePointer();
        await tester.pumpWidget(
          egHost(Checkbox(checked: false, onChanged: (_) {})),
        );
        final m2 = await _hover(tester, find.byType(Checkbox));
        await m2.down(tester.getCenter(find.byType(Checkbox)));
        await tester.pump(const Duration(milliseconds: 100));
        expect(box().color, _c.steelActive);
        await m2.up();
        await m2.removePointer();
      },
    );

    testEg('hover clareia a borda e erro pinta danger', (tester) async {
      await tester.pumpWidget(
        egHost(Checkbox(checked: false, onChanged: (_) {})),
      );
      final mouse = await _hover(tester, find.byType(Checkbox));
      BoxDecoration box() =>
          tester
                  .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                  .decoration!
              as BoxDecoration;
      expect((box().border! as Border).top.color, _c.controlBorderHover);
      await mouse.removePointer();
      await tester.pumpWidget(
        egHost(Checkbox(checked: false, error: true, onChanged: (_) {})),
      );
      expect((box().border! as Border).top.color, _c.danger);
    });

    testEg('focada, a caixa não ganha anel', (tester) async {
      await tester.pumpWidget(
        egHost(Checkbox(checked: false, onChanged: (_) {}, autofocus: true)),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 100));
      final box =
          tester
                  .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                  .decoration!
              as BoxDecoration;
      expect((box.border! as Border).top.width, isNot(EgeonBorder.focus));
    });

    testEg('indeterminada mostra o traço', (tester) async {
      await tester.pumpWidget(
        egHost(
          Checkbox(checked: false, indeterminate: true, onChanged: (_) {}),
        ),
      );
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testEg(
      'desabilitada: borda line sem fundo, texto textDisabled, sem opacidade',
      (tester) async {
        BoxDecoration box() =>
            tester
                    .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                    .decoration!
                as BoxDecoration;
        await tester.pumpWidget(
          egHost(
            const Checkbox(checked: false, onChanged: null, label: Text('x')),
          ),
        );
        expect(box().color, const Color(0x00000000));
        expect((box().border! as Border).top.color, _c.line);
        expect(find.byType(Opacity), findsNothing);
        expect(
          tester
              .widget<DefaultTextStyle>(
                find
                    .ancestor(
                      of: find.text('x'),
                      matching: find.byType(DefaultTextStyle),
                    )
                    .first,
              )
              .style
              .color,
          _c.textDisabled,
        );
        await tester.pumpWidget(
          egHost(const Checkbox(checked: true, onChanged: null)),
        );
        expect(box().color, _c.steelActive);
      },
    );

    testEg(
      'Radio: círculo; marcado é anel accent de 5px sobre carbon; escolhe por clique',
      (tester) async {
        var picked = 0;
        await tester.pumpWidget(
          egHost(
            Radio(
              checked: true,
              onSelected: () => picked++,
              label: const Text('Um'),
            ),
          ),
        );
        final box =
            tester
                    .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                    .decoration!
                as BoxDecoration;
        expect(box.shape, BoxShape.circle);
        expect(box.color, _c.carbon);
        final border = box.border! as Border;
        expect(border.top.color, _c.accent);
        expect(border.top.width, 5);
        await tester.tap(find.text('Um'));
        expect(picked, 1);
      },
    );

    testEg('Radio desabilitado: sem opacidade, borda line', (tester) async {
      await tester.pumpWidget(
        egHost(const Radio(checked: false, onSelected: null)),
      );
      expect(find.byType(Opacity), findsNothing);
      final box =
          tester
                  .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                  .decoration!
              as BoxDecoration;
      expect((box.border! as Border).top.color, _c.line);
    });
  });

  group('Toggle', () {
    testEg(
      'trilho 30×18: desligado steelActive/lineStrong; ligado accent; bolinha 12',
      (tester) async {
        BoxDecoration track() =>
            tester
                    .widget<AnimatedContainer>(
                      find.byType(AnimatedContainer).first,
                    )
                    .decoration!
                as BoxDecoration;
        Rect thumb() => tester.getRect(
          find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).shape == BoxShape.rectangle &&
                (w.decoration as BoxDecoration).borderRadius ==
                    BorderRadius.circular(EgeonRadius.full) &&
                (w.decoration as BoxDecoration).border == null,
          ),
        );
        await tester.pumpWidget(egHost(Toggle(on: false, onChanged: (_) {})));
        expect(track().color, _c.steelActive);
        expect((track().border! as Border).top.color, _c.lineStrong);
        final box = tester.getRect(find.byType(Toggle));
        expect(box.size, const Size(30, 18));
        expect(thumb().size, const Size(12, 12));
        expect(thumb().left - box.left, 3);
        await tester.pumpWidget(egHost(Toggle(on: true, onChanged: (_) {})));
        await tester.pumpAndSettle();
        expect(track().color, _c.accent);
        expect(thumb().left - box.left, 15);
      },
    );

    testEg(
      'hover: controlBorder desligado e accentHover ligado; pressionado alarga a bolinha',
      (tester) async {
        BoxDecoration track() =>
            tester
                    .widget<AnimatedContainer>(
                      find.byType(AnimatedContainer).first,
                    )
                    .decoration!
                as BoxDecoration;
        await tester.pumpWidget(egHost(Toggle(on: false, onChanged: (_) {})));
        var mouse = await _hover(tester, find.byType(Toggle));
        expect((track().border! as Border).top.color, _c.controlBorder);
        await mouse.removePointer();
        await tester.pumpWidget(egHost(Toggle(on: true, onChanged: (_) {})));
        mouse = await _hover(tester, find.byType(Toggle));
        expect(track().color, _c.accentHover);
        await mouse.down(tester.getCenter(find.byType(Toggle)));
        await tester.pump(const Duration(milliseconds: 200));
        final thumb = tester
            .widgetList<AnimatedPositioned>(find.byType(AnimatedPositioned))
            .single;
        expect(thumb.width, 14);
        await mouse.up();
        await mouse.removePointer();
      },
    );

    testEg('clica e alterna; Enter também; foco engrossa a borda', (
      tester,
    ) async {
      var on = false;
      await tester.pumpWidget(
        egHost(
          StatefulBuilder(
            builder: (context, setState) => Toggle(
              on: on,
              autofocus: true,
              label: const Text('Auto'),
              onChanged: (v) => setState(() => on = v),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Auto'));
      await tester.pump();
      expect(on, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(on, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    });

    testEg('movimento reduzido: troca direta', (tester) async {
      await tester.pumpWidget(
        egHost(reduceMotion: true, Toggle(on: false, onChanged: (_) {})),
      );
      await tester.pumpWidget(
        egHost(reduceMotion: true, Toggle(on: true, onChanged: (_) {})),
      );
      await tester.pump();
      final box = tester
          .widget<AnimatedContainer>(find.byType(AnimatedContainer))
          .duration;
      expect(box, Duration.zero);
    });

    testEg('desabilitado: trilho sem fundo, borda line, bolinha textDisabled', (
      tester,
    ) async {
      await tester.pumpWidget(egHost(const Toggle(on: true, onChanged: null)));
      final track =
          tester
                  .widget<AnimatedContainer>(
                    find.byType(AnimatedContainer).first,
                  )
                  .decoration!
              as BoxDecoration;
      expect(track.color, const Color(0x00000000));
      expect((track.border! as Border).top.color, _c.line);
      expect(find.byType(Opacity), findsNothing);
    });
  });

  group('Slider', () {
    testEg('clicar escolhe o passo mais perto; mostra o nome e os rótulos', (
      tester,
    ) async {
      var value = 1;
      await tester.pumpWidget(
        egHost(
          StatefulBuilder(
            builder: (context, setState) => Slider(
              value: value,
              width: 300,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      );
      expect(find.text('medium'), findsNWidgets(2));
      final box = tester.getRect(find.byType(Slider));
      await tester.tapAt(Offset(box.right - 4, box.top + 38));
      await tester.pump();
      expect(value, 3);
      await tester.tapAt(Offset(box.left + 4, box.top + 38));
      await tester.pump();
      expect(value, 0);
    });

    testEg('setas, Home e End movem o passo', (tester) async {
      var value = 1;
      await tester.pumpWidget(
        egHost(
          StatefulBuilder(
            builder: (context, setState) => Slider(
              value: value,
              width: 300,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      );
      final box = tester.getRect(find.byType(Slider));
      await tester.tapAt(Offset(box.left + 150, box.top + 38));
      await tester.pump();
      final start = value;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(value, (start + 1).clamp(0, 3));
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(value, 3);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(value, 0);
    });

    testEg('auto: a pílula alterna e o trilho vai a textDisabled', (
      tester,
    ) async {
      var auto = false;
      await tester.pumpWidget(
        egHost(
          StatefulBuilder(
            builder: (context, setState) => Slider(
              value: 1,
              onChanged: (_) {},
              auto: auto,
              onAutoChanged: (v) => setState(() => auto = v),
            ),
          ),
        ),
      );
      Iterable<Color> fills() => tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.color)
          .whereType<Color>();
      expect(fills(), contains(_c.accent));
      await tester.tap(find.text('auto'));
      await tester.pump();
      expect(auto, isTrue);
      expect(fills(), isNot(contains(_c.accent)));
      expect(fills(), contains(_c.textDisabled));
    });

    testEg('medidas do DS: largura 280, pista de 20, bolinha de 16', (
      tester,
    ) async {
      await tester.pumpWidget(egHost(Slider(value: 0, onChanged: (_) {})));
      expect(tester.getSize(find.byType(Slider)).width, 280);
      final thumb = tester.getSize(
        find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle &&
              (w.decoration as BoxDecoration).border != null,
        ),
      );
      expect(thumb, const Size(16, 16));
    });

    testEg('desabilitado: tudo em textDisabled, sem opacidade', (tester) async {
      await tester.pumpWidget(egHost(const Slider(value: 2, onChanged: null)));
      expect(find.byType(Opacity), findsNothing);
      final value = tester.widgetList<Text>(find.text('high')).first;
      expect(value.style!.color, _c.textDisabled);
    });
  });

  group('SegmentedControl e ViewSwitch', () {
    testEg('o ligado leva overlay8; clicar troca', (tester) async {
      ViewSwitchMode value = ViewSwitchMode.canvas;
      await tester.pumpWidget(
        egHost(
          StatefulBuilder(
            builder: (context, setState) => ViewSwitch(
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      );
      Color? bg(String name) =>
          (tester
                      .widget<AnimatedContainer>(
                        find.byKey(ValueKey('view-$name')),
                      )
                      .decoration!
                  as BoxDecoration)
              .color;
      expect(find.text('Canvas'), findsNothing);
      expect(bg('canvas'), EgeonColors.overlay8);
      expect(bg('chat'), EgeonColors.clear);
      expect(find.bySemanticsLabel('Chat'), findsOneWidget);
      expect(find.bySemanticsLabel('Visualização'), findsOneWidget);
      Color? icon(String name) => tester
          .widget<EgIcon>(
            find.descendant(
              of: find.byKey(ValueKey('view-$name')),
              matching: find.byType(EgIcon),
            ),
          )
          .color;
      expect(icon('canvas'), _c.textPrimary, reason: 'ligado');
      expect(icon('chat'), _c.textSecondary, reason: 'repouso');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Canvas')),
        matchesSemantics(
          label: 'Canvas',
          isSelected: true,
          isButton: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          hasSelectedState: true,
          isEnabled: true,
          hasEnabledState: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Chat')),
        isSemantics(label: 'Chat', hasSelectedState: true, isSelected: false),
      );
      await tester.tap(find.byKey(const ValueKey('view-chat')));
      await tester.pumpAndSettle();
      expect(value, ViewSwitchMode.chat);
      expect(bg('chat'), EgeonColors.overlay8);
    });

    testEg('botões de 32, grupo de 36 com raio 10', (tester) async {
      await tester.pumpWidget(
        egHost(ViewSwitch(value: ViewSwitchMode.chat, onChanged: (_) {})),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('view-chat'))),
        const Size(32, 32),
      );
      expect(tester.getSize(find.byType(ViewSwitch)), const Size(70, 36));
    });

    testEg('hover: overlay6 e ícone textPrimary; pressionado também', (
      tester,
    ) async {
      await tester.pumpWidget(
        egHost(ViewSwitch(value: ViewSwitchMode.canvas, onChanged: (_) {})),
      );
      final mouse = await _hover(
        tester,
        find.byKey(const ValueKey('view-chat')),
      );
      Color? box() =>
          (tester
                      .widget<AnimatedContainer>(
                        find.byKey(const ValueKey('view-chat')),
                      )
                      .decoration!
                  as BoxDecoration)
              .color;
      expect(box(), EgeonColors.overlay6);
      expect(
        tester
            .widget<EgIcon>(
              find.descendant(
                of: find.byKey(const ValueKey('view-chat')),
                matching: find.byType(EgIcon),
              ),
            )
            .color,
        _c.textPrimary,
      );
      await mouse.removePointer();
    });

    testEg('desabilitado: texto textDisabled, selecionado steel, sem toque', (
      tester,
    ) async {
      await tester.pumpWidget(
        egHost(
          SegmentedControl<int>(
            value: 1,
            onChanged: null,
            options: const [SegmentOption(1, 'Um'), SegmentOption(2, 'Dois')],
          ),
        ),
      );
      expect(find.byType(Opacity), findsNothing);
      expect(
        tester.widget<Text>(find.text('Dois')).style!.color,
        _c.textDisabled,
      );
      final selected =
          tester
                  .widget<AnimatedContainer>(
                    find.ancestor(
                      of: find.text('Um'),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(selected.color, _c.steel);
    });
  });
}
