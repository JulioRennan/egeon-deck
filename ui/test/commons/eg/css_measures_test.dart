import 'package:egeon_deck/commons/widgets/eg/badge.dart';
import 'package:egeon_deck/commons/widgets/eg/banner.dart';
import 'package:egeon_deck/commons/widgets/eg/button.dart';
import 'package:egeon_deck/commons/widgets/eg/counter.dart';
import 'package:egeon_deck/commons/widgets/eg/info_pill.dart';
import 'package:egeon_deck/commons/widgets/eg/kbd.dart';
import 'package:egeon_deck/commons/widgets/eg/status.dart';
import 'package:egeon_deck/commons/widgets/eg/toast.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:egeon_deck/theme/egeon_tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';

const _c = EgeonColors.dark;

// Medidas e cores conferidas contra o bundle.css do DS.
void main() {
  testEg(
    'Kbd: fio de 1px line, sem fundo, mono 11/16 em textMuted, respiro de 4',
    (tester) async {
      await tester.pumpWidget(egHost(const Kbd('⌘3')));
      final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, isNull);
      expect((decoration.border! as Border).top.color, _c.line);
      expect(decoration.borderRadius, BorderRadius.circular(EgeonRadius.xs));
      final text = tester.widget<Text>(find.text('⌘3'));
      expect(text.style!.fontSize, 11);
      expect(text.style!.color, _c.textMuted);
      expect(tester.getSize(find.byType(Kbd)).height, closeTo(16, 0.01));
    },
  );

  testEg('Counter: 20×20 no mínimo, neutro em steelActive', (tester) async {
    await tester.pumpWidget(egHost(const Counter(1)));
    final size = tester.getSize(find.byType(Counter));
    expect(size.width, greaterThanOrEqualTo(20));
    expect(size.height, 20);
    expect(tester.widget<Text>(find.text('1')).style!.fontSize, 11);
    expect(
      tester.widget<Text>(find.text('1')).style!.fontWeight,
      FontWeight.w600,
    );
  });

  testEg(
    'Badge: 24 de altura; neutro e contorno sem fundo, com fio lineStrong',
    (tester) async {
      await tester.pumpWidget(
        egHost(Badge('Falhou', tone: BadgeTone.status(Status.danger))),
      );
      expect(tester.getSize(find.byType(Badge)).height, 24);
      await tester.pumpWidget(egHost(const Badge('neutro')));
      final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, isNull);
      expect((decoration.border! as Border).top.color, _c.lineStrong);
      expect(
        tester.widget<Text>(find.text('neutro')).style!.fontFamily,
        'JetBrains Mono',
      );
    },
  );

  testEg('InfoPill: 30 de altura; normal em carbon com fio, ghost sem nada', (
    tester,
  ) async {
    await tester.pumpWidget(egHost(const InfoPill('medium')));
    expect(tester.getSize(find.byType(InfoPill)).height, 30);
    BoxDecoration decoration() =>
        tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration
            as BoxDecoration;
    expect(decoration().color, _c.carbon);
    expect((decoration().border! as Border).top.color, _c.line);
    await tester.pumpWidget(
      egHost(const InfoPill('medium', tone: InfoPillTone.ghost)),
    );
    expect(decoration().color, isNull);
    expect((decoration().border! as Border).top.color, const Color(0x00000000));
  });

  testEg('Button: respiro e corpo por tamanho do DS', (tester) async {
    expect(
      ButtonSize.values.map((s) => (s.padding, s.fontSize, s.radius)).toList(),
      [(12.0, 13.0, 7.0), (14.0, 14.0, 8.0), (18.0, 15.0, 10.0)],
    );
    await tester.pumpWidget(
      egHost(Button(label: 'Salvar', size: ButtonSize.lg, onPressed: () {})),
    );
    expect(tester.widget<Text>(find.text('Salvar')).style!.fontSize, 15);
  });

  testEg('Banner: 48 no mínimo; danger e attention sem fio, info com line', (
    tester,
  ) async {
    await tester.pumpWidget(
      egHost(const SizedBox(width: 400, child: NoticeBanner(child: Text('x')))),
    );
    expect(
      tester.getSize(find.byType(NoticeBanner)).height,
      greaterThanOrEqualTo(48),
    );
    BoxDecoration decoration() =>
        tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration
            as BoxDecoration;
    expect((decoration().border! as Border).top.color, _c.line);
    await tester.pumpWidget(
      egHost(
        const SizedBox(
          width: 400,
          child: NoticeBanner(tone: BannerTone.danger, child: Text('x')),
        ),
      ),
    );
    expect(decoration().color, _c.dangerSoft);
    expect((decoration().border! as Border).top.color, const Color(0x00000000));
  });

  testEg('Toast: 360 de largura', (tester) async {
    await tester.pumpWidget(egHost(const Toast(title: 'x')));
    expect(tester.getSize(find.byType(Toast)).width, 360);
  });
}
