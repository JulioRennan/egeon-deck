import 'package:egeon_deck/commons/widgets/eg/toast.dart';
import 'package:egeon_deck/commons/widgets/shell_layers.dart';
import 'package:egeon_deck/theme/egeon_tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';

Widget _box(String key, double w, double h) =>
    SizedBox(key: ValueKey(key), width: w, height: h);

void main() {
  testEg('cada camada no seu lugar, sem cobrir a outra', (tester) async {
    await tester.pumpWidget(
      egHost(
        fill: true,
        ShellLayers(
          actions: _box('acoes', 360, 48),
          corner: _box('consumo', 120, 36),
          permissions: _box('permissao', 560, 96),
          composer: _box('composer', 720, 120),
        ),
      ),
    );
    Rect r(String k) => tester.getRect(find.byKey(ValueKey(k)));
    final window = const Offset(0, 0) & const Size(1000, 800);
    final acoes = r('acoes');
    final consumo = r('consumo');
    final permissao = r('permissao');
    final composer = r('composer');

    expect(
      acoes.center.dx,
      closeTo(500, 0.5),
      reason: 'barra de ações no centro',
    );
    expect(acoes.top, ShellLayers.margin);
    expect(consumo.right, 1000 - ShellLayers.margin, reason: 'chip no canto');
    expect(consumo.top, ShellLayers.margin);
    expect(composer.bottom, 800 - ShellLayers.bottomMargin);
    expect(composer.center.dx, closeTo(500, 0.5));
    expect(
      permissao.bottom + ShellLayers.gap,
      composer.top,
      reason: 'permissão logo acima do composer',
    );
    for (final rect in [acoes, consumo, permissao, composer]) {
      expect(
        window.contains(rect.topLeft) && window.contains(rect.bottomRight),
        isTrue,
      );
    }
    final all = {
      'acoes': acoes,
      'consumo': consumo,
      'permissao': permissao,
      'composer': composer,
    };
    for (final a in all.entries) {
      for (final b in all.entries) {
        if (a.key.compareTo(b.key) >= 0) continue;
        expect(
          a.value.overlaps(b.value),
          isFalse,
          reason: '${a.key} × ${b.key}',
        );
      }
    }
  });

  testEg('o aviso sobe por cima do composer e dos pedidos', (tester) async {
    await tester.pumpWidget(
      egHost(
        fill: true,
        Builder(
          builder: (context) => Stack(
            children: [
              ShellLayers(
                permissions: _box('permissao', 560, 96),
                composer: _box('composer', 720, 120),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showToast(context, title: 'Pronto'),
                  child: const SizedBox(width: 40, height: 40),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      toastBottomInset.value,
      96 + ShellLayers.gap + 120 + ShellLayers.bottomMargin,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 300));
    final toast = tester.getRect(find.text('Pronto'));
    final composer = tester.getRect(find.byKey(const ValueKey('composer')));
    final permissao = tester.getRect(find.byKey(const ValueKey('permissao')));
    expect(toast.bottom, lessThan(permissao.top));
    expect(toast.overlaps(composer), isFalse);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    expect(toastBottomInset.value, 0, reason: 'sai com a casca');
    expect(EgeonSpace.s4, ShellLayers.margin);
  });

  testEg('só o que existe ocupa lugar', (tester) async {
    await tester.pumpWidget(
      egHost(fill: true, ShellLayers(composer: _box('composer', 720, 120))),
    );
    await tester.pump();
    expect(toastBottomInset.value, 120 + ShellLayers.bottomMargin);
    expect(ShellLayers.bottomMargin, EgeonSpace.s5);
    await tester.pumpWidget(egHost(fill: true, const ShellLayers()));
    await tester.pump();
    expect(toastBottomInset.value, 0);
  });
}
