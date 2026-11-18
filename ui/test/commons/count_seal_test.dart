import 'dart:ui' as ui;

import 'package:egeon_deck/commons/widgets/count_seal.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Porte de testCountSealCentersTheDigit (SidebarDropTests.swift): o dígito
// fica no meio do selo, medido no pixel — que é onde o olho reclamou.
void main() {
  for (final value in [1, 5, 12]) {
    testWidgets('o dígito $value fica no centro do selo', (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(key: key, child: CountSeal(value)),
          ),
        ),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final size = boundary.size;
      const scale = 4.0;
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: scale);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return (data!, image.width, image.height);
      });
      final (data, width, height) = bytes!;

      // As linhas e colunas onde o dígito (claro) aparece, sem o anel escuro.
      var top = height, bottom = -1, left = width, right = -1;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final i = (y * width + x) * 4;
          final alpha = data.getUint8(i + 3);
          final bright = data.getUint8(i) > 140;
          if (alpha > 128 && bright) {
            top = y < top ? y : top;
            bottom = y > bottom ? y : bottom;
            left = x < left ? x : left;
            right = x > right ? x : right;
          }
        }
      }
      expect(bottom, greaterThan(-1), reason: 'não achou o dígito');
      final centerY = (top + bottom) / 2 / scale;
      final centerX = (left + right) / 2 / scale;
      expect(centerY, closeTo(size.height / 2, 1), reason: 'vertical');
      expect(centerX, closeTo(size.width / 2, 1), reason: 'horizontal');
    });
  }
}
