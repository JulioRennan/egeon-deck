import 'dart:ui';

import 'package:egeon_deck/features/sidebar/presentation/widgets/sidebar_drop.dart';
import 'package:flutter_test/flutter_test.dart';

// Porte de SidebarDropTests.swift: o alvo calculado a partir de um ponto, com
// os frames de um layout. Arrastar não se dirige de fora; o que se prova é a
// conta que o arrasto usa.
Rect r(double top, double bottom, {double left = 8, double right = 256}) =>
    Rect.fromLTRB(left, top, right, bottom);

/// Dois workspaces: o primeiro com p1 (duas bancadas) e p2 (uma); o segundo
/// com p3 (uma). Com a gaveta do primeiro, opcionalmente com um guardado.
SidebarDropGeometry sample({bool storedProject = false}) {
  final p1 = TileFrame(
    projectId: 'p1',
    frame: r(54, 232),
    header: r(54, 98),
    rows: [RowFrame('um', r(112, 166)), RowFrame('dois', r(172, 226))],
  );
  final p2 = TileFrame(
    projectId: 'p2',
    frame: r(236, 380),
    header: r(236, 280),
    rows: [RowFrame('tres', r(294, 348))],
  );
  final p9 = TileFrame(
    projectId: 'p9',
    frame: r(420, 464),
    header: r(420, 464),
  );
  final p3 = TileFrame(
    projectId: 'p3',
    frame: r(560, 700),
    header: r(560, 604),
    rows: [RowFrame('quatro', r(618, 672))],
  );
  return SidebarDropGeometry([
    CardFrame(
      workspaceId: 'w1',
      frame: r(8, 480),
      drawer: r(386, 412),
      projects: [p1, p2],
      stored: storedProject ? [p9] : const [],
    ),
    CardFrame(
      workspaceId: 'w2',
      frame: r(510, 720),
      drawer: r(706, 732),
      projects: [p3],
    ),
  ], listWidth: 264);
}

Offset at(Rect rect, double dy) => Offset(rect.center.dx, dy);

void main() {
  test('a bancada cai no projeto sob o cursor', () {
    final g = sample();
    const dragged = DragBench('tres');
    // Sobre a primeira linha de p1, vindo de fora: cai antes dela.
    expect(g.drop(dragged, at(r(112, 166), 114)), const DropBench('p1', 0));
    // Abaixo da última linha de p1: cai no fim.
    expect(g.drop(dragged, at(r(172, 226), 224)), const DropBench('p1', 2));
    // Em outro projeto o alvo muda de pai: abaixo da linha que ele já tem,
    // entra depois dela; sobre o topo dela, antes.
    expect(
      g.drop(const DragBench('um'), at(r(294, 348), 346)),
      const DropBench('p2', 1),
    );
    expect(
      g.drop(const DragBench('um'), at(r(294, 348), 296)),
      const DropBench('p2', 0),
    );
  });

  test('para baixo no próprio projeto a linha que sai não conta', () {
    final g = sample();
    final second = r(172, 226);
    expect(
      g.drop(const DragBench('um'), at(second, 224)),
      const DropBench('p1', 1),
    );
    // A mesma queda, vinda de outro projeto, é a posição seguinte.
    expect(
      g.drop(const DragBench('tres'), at(second, 224)),
      const DropBench('p1', 2),
    );
  });

  test('fora de qualquer projeto a bancada não tem onde cair', () {
    expect(sample().drop(const DragBench('um'), const Offset(100, 2)), isNull);
  });

  test('a gaveta: abaixo da tampa guarda; acima dela, tira', () {
    final g = sample(storedProject: true);
    final lid = r(386, 412);
    // Logo abaixo da tampa entra na frente do que já está guardado.
    expect(
      g.drop(const DragProject('w1', 'p1'), at(lid, lid.bottom + 4)),
      const DropProject('w1', 0, stored: true),
    );
    // Mais abaixo do primeiro guardado, atrás dele.
    expect(
      g.drop(const DragProject('w1', 'p1'), at(lid, 462)),
      const DropProject('w1', 1, stored: true),
    );
    // Acima da tampa, entre os em uso.
    expect(
      g.drop(const DragProject('w1', 'p9'), at(lid, 56)),
      const DropProject('w1', 0, stored: false),
    );
  });

  test(
    'a gaveta existe mesmo vazia ou fechada: é o alvo do primeiro guardado',
    () {
      final g = sample();
      final lid = r(386, 412);
      expect(
        g.drop(const DragProject('w1', 'p1'), at(lid, lid.bottom - 2)),
        const DropProject('w1', 0, stored: true),
      );
    },
  );

  test('projeto solto sobre outro workspace entra nele', () {
    final g = sample();
    final p3 = r(560, 700);
    // Abaixo do que ele já tem, na segunda posição.
    expect(
      g.drop(const DragProject('w1', 'p1'), at(p3, 698)),
      const DropProject('w2', 1, stored: false),
    );
    expect(
      g.drop(const DragProject('w1', 'p1'), at(p3, 562)),
      const DropProject('w2', 0, stored: false),
    );
    // Sobre o topo do próprio workspace, vai para a primeira posição.
    expect(
      g.drop(const DragProject('w1', 'p2'), at(r(54, 232), 56)),
      const DropProject('w1', 0, stored: false),
    );
  });

  test('o workspace passa pela metade do card vizinho para trocar', () {
    final g = sample();
    final w2 = r(510, 720);
    final w1 = r(8, 480);
    expect(
      g.drop(const DragWorkspace('w1'), at(w2, 718)),
      const DropWorkspace(1),
    );
    expect(
      g.drop(const DragWorkspace('w2'), at(w1, 10)),
      const DropWorkspace(0),
    );
    // Antes da metade, fica onde estava.
    expect(
      g.drop(const DragWorkspace('w1'), at(w2, 520)),
      const DropWorkspace(0),
    );
  });

  test('a guia aparece entre os irmãos e some quando não há onde', () {
    final g = sample();
    // Antes da primeira linha de p1: logo acima dela, com 2 de altura.
    final first = g.guide(const DropBench('p1', 0))!;
    expect(first.top, 112 - 1);
    expect(first.height, 2);
    expect(first.left, 8 + 6, reason: 'recuada pelo recuo do ladrilho');
    // No fim: logo abaixo da última.
    expect(g.guide(const DropBench('p1', 2))!.top, 226 - 1);
    // Projeto sem linhas: logo abaixo do cabeçalho dele.
    final empty = SidebarDropGeometry([
      CardFrame(
        workspaceId: 'w',
        frame: r(0, 200),
        drawer: r(150, 176),
        projects: [
          TileFrame(projectId: 'v', frame: r(10, 54), header: r(10, 54)),
        ],
      ),
    ]);
    expect(empty.guide(const DropBench('v', 0))!.top, 54 - 1);
    expect(sample().guide(const DropBench('inexistente', 0)), isNull);
  });

  test('a guia do projeto na gaveta vazia encosta na tampa', () {
    final g = sample();
    final guide = g.guide(const DropProject('w1', 0, stored: true))!;
    expect(guide.top, 412 - 1);
  });

  test('a guia do workspace corre a largura da lista', () {
    final g = sample();
    final guide = g.guide(const DropWorkspace(1))!;
    expect(guide.top, 510 - 1);
    expect(guide.left, 8);
    expect(guide.width, 264 - 16);
  });
}
