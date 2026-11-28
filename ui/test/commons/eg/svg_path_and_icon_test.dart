import 'package:egeon_deck/commons/widgets/eg/eg_icon.dart';

import 'dart:convert';
import 'dart:io';

import 'package:egeon_deck/commons/widgets/eg/svg_path.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';

void main() {
  group('parseSvgPath', () {
    test('relativos e absolutos chegam no mesmo ponto', () {
      final a = parseSvgPath('M2 2L6 2L6 6z').getBounds();
      final b = parseSvgPath('M2 2h4v4z').getBounds();
      expect(a, b);
      expect(a.width, 4);
    });

    test('H e V, números colados e sinal como separador', () {
      final bounds = parseSvgPath('M3.5 8h9M8 3.5v9').getBounds();
      expect(bounds.left, 3.5);
      expect(bounds.right, 12.5);
      expect(bounds.top, 3.5);
      expect(bounds.bottom, 12.5);
      expect(parseSvgPath('M3 8.5l3 3 6-6.5').getBounds().right, 12);
    });

    test('arco chega no ponto final e fecha uma meia-volta', () {
      final bounds = parseSvgPath('M2 8a6 6 0 0 1 12 0').getBounds();
      expect(bounds.left, closeTo(2, 1e-6));
      expect(bounds.right, closeTo(14, 1e-6));
      expect(bounds.top, closeTo(2, 1e-3));
    });

    test('comando repetido sem letra (M com pares seguintes é linha)', () {
      final bounds = parseSvgPath('M1 1 5 1 5 5').getBounds();
      expect(bounds.right, 5);
      expect(bounds.bottom, 5);
    });

    test('a rotação do arco é em graus, como o SVG', () {
      // Corda horizontal de 8: com raios 8×3 o arco sobe pouco; girado em 90°
      // o raio de 8 passa a ser o vertical e o arco sobe muito mais.
      final flat = parseSvgPath('M2 8a8 3 0 0 1 8 0').getBounds();
      final turned = parseSvgPath('M2 8a8 3 90 0 1 8 0').getBounds();
      expect(turned.height, greaterThan(flat.height + 2));
    });

    test('comando desconhecido é erro', () {
      expect(() => parseSvgPath('M1 1X'), throwsFormatException);
    });
  });

  group('EgIcons', () {
    test('todos os nomes do `Icon` do DS existem, com o mesmo caminho', () {
      final ds = (jsonDecode(
        File('test/fixtures/design_icons.json').readAsStringSync(),
      ) as Map<String, dynamic>).cast<String, String>();
      expect(ds.length, 55);
      for (final entry in ds.entries) {
        final icon = EgIcons.byName(entry.key);
        expect(icon, isNotNull, reason: 'falta ${entry.key}');
        if (EgIcons.v3Overrides.contains(entry.key)) continue;
        expect(icon!.shapes.length, 1, reason: entry.key);
        expect(
          (icon.shapes.single as EgPath).d,
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('as exceções da v3 são nomes do DS', () {
      final ds = (jsonDecode(
        File('test/fixtures/design_icons.json').readAsStringSync(),
      ) as Map<String, dynamic>).keys.toSet();
      expect(ds.containsAll(EgIcons.v3Overrides), isTrue);
    });

    test('more tem traço 2.5 e play é preenchido; os outros, 1.5', () {
      expect(EgIcons.more.strokeWidth, 2.5);
      expect(EgIcons.play.filled, isTrue);
      expect(EgIcons.plus.strokeWidth, egIconStroke);
      expect(egIconStroke, 1.5);
    });

    test('todos têm nome único e formas', () {
      final names = EgIcons.all.map((i) => i.name).toList();
      expect(names.toSet().length, names.length);
      for (final icon in EgIcons.all) {
        expect(icon.shapes, isNotEmpty, reason: icon.name);
      }
    });

    test('todo caminho dos ícones lê e cabe na grade de 16', () {
      for (final icon in EgIcons.all) {
        for (final shape in icon.shapes.whereType<EgPath>()) {
          final b = parseSvgPath(shape.d).getBounds();
          expect(b.left, greaterThanOrEqualTo(-2), reason: icon.name);
          expect(b.top, greaterThanOrEqualTo(-2), reason: icon.name);
          expect(b.right, lessThanOrEqualTo(18), reason: icon.name);
          expect(b.bottom, lessThanOrEqualTo(18), reason: icon.name);
        }
      }
    });

    testWidgets('EgIcon desenha todos nos três tamanhos sem erro', (
      tester,
    ) async {
      for (final size in [16.0, 14.0, 12.0]) {
        await tester.pumpWidget(
          egHost(
            Wrap(
              children: [for (final i in EgIcons.all) EgIcon(i, size: size)],
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
      expect(tester.getSize(find.byType(EgIcon).first), const Size(12, 12));
    });
  });
}
