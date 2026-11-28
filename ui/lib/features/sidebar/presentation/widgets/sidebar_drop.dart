import 'dart:ui';

/// O que se arrasta na árvore. Bancada, projeto e workspace só se reordenam
/// dentro do seu tipo: bancada entre projetos, projeto entre workspaces e a
/// gaveta, workspace entre workspaces.
sealed class DragItem {
  const DragItem();

  String get id;
}

class DragWorkspace extends DragItem {
  const DragWorkspace(this.id);

  @override
  final String id;

  @override
  bool operator ==(Object other) => other is DragWorkspace && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class DragProject extends DragItem {
  const DragProject(this.workspaceId, this.id, {this.stored = false});

  final String workspaceId;

  /// O projeto sai da gaveta: soltá-lo fora dela é `unstore`.
  final bool stored;

  @override
  final String id;

  @override
  bool operator ==(Object other) =>
      other is DragProject &&
      other.workspaceId == workspaceId &&
      other.id == id;

  @override
  int get hashCode => Object.hash(workspaceId, id);
}

class DragBench extends DragItem {
  const DragBench(this.id);

  @override
  final String id;

  @override
  bool operator ==(Object other) => other is DragBench && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Para onde o ponteiro aponta: um pai e uma posição entre os irmãos, já sem
/// contar o próprio item. É só geometria — se o lugar vale, o core diz.
sealed class Drop {
  const Drop();

  /// Como o core conhece este alvo: `kind`, pai e posição do `plan_move` e do
  /// `move`. Soltar sob a tampa da gaveta é `store`; tirar da gaveta é
  /// `unstore`.
  ({String kind, String? parent, int to}) requestFor(DragItem item);

  /// O mesmo alvo, no pai e na posição que o core devolveu em `lands`.
  Drop landingAt({String? parent, required int to});
}

class DropWorkspace extends Drop {
  const DropWorkspace(this.position);

  final int position;

  @override
  ({String kind, String? parent, int to}) requestFor(DragItem item) =>
      (kind: 'workspace', parent: null, to: position);

  @override
  Drop landingAt({String? parent, required int to}) => DropWorkspace(to);

  @override
  bool operator ==(Object other) =>
      other is DropWorkspace && other.position == position;

  @override
  int get hashCode => position.hashCode;

  @override
  String toString() => 'DropWorkspace($position)';
}

class DropProject extends Drop {
  const DropProject(this.workspaceId, this.position, {required this.stored});

  final String workspaceId;
  final int position;

  /// Caiu na gaveta.
  final bool stored;

  @override
  ({String kind, String? parent, int to}) requestFor(DragItem item) {
    final wasStored = item is DragProject && item.stored;
    return (
      kind: stored ? 'store' : (wasStored ? 'unstore' : 'project'),
      parent: workspaceId,
      to: position,
    );
  }

  @override
  Drop landingAt({String? parent, required int to}) =>
      DropProject(parent ?? workspaceId, to, stored: stored);

  @override
  bool operator ==(Object other) =>
      other is DropProject &&
      other.workspaceId == workspaceId &&
      other.position == position &&
      other.stored == stored;

  @override
  int get hashCode => Object.hash(workspaceId, position, stored);

  @override
  String toString() => 'DropProject($workspaceId, $position, stored: $stored)';
}

class DropBench extends Drop {
  const DropBench(this.projectId, this.position);

  final String projectId;
  final int position;

  @override
  ({String kind, String? parent, int to}) requestFor(DragItem item) =>
      (kind: 'workbench', parent: projectId, to: position);

  @override
  Drop landingAt({String? parent, required int to}) =>
      DropBench(parent ?? projectId, to);

  @override
  bool operator ==(Object other) =>
      other is DropBench &&
      other.projectId == projectId &&
      other.position == position;

  @override
  int get hashCode => Object.hash(projectId, position);

  @override
  String toString() => 'DropBench($projectId, $position)';
}

/// Os retângulos de uma linha de bancada visível.
class RowFrame {
  const RowFrame(this.benchId, this.frame);

  final String benchId;
  final Rect frame;
}

/// O ladrilho de um projeto visível, com o cabeçalho e as linhas dele.
class TileFrame {
  const TileFrame({
    required this.projectId,
    required this.frame,
    required this.header,
    this.rows = const [],
  });

  final String projectId;
  final Rect frame;
  final Rect header;

  /// Só as linhas visíveis (projeto recolhido não tem nenhuma).
  final List<RowFrame> rows;
}

/// O card de um workspace visível: a tampa da gaveta e os projetos dos dois
/// lados dela.
class CardFrame {
  const CardFrame({
    required this.workspaceId,
    required this.frame,
    required this.drawer,
    this.projects = const [],
    this.stored = const [],
  });

  final String workspaceId;
  final Rect frame;
  final Rect drawer;
  final List<TileFrame> projects;
  final List<TileFrame> stored;
}

/// A conta do arrasto, sem widget nenhum: dado o que está na tela e um ponto,
/// onde o item cairia e onde desenhar a guia de inserção.
class SidebarDropGeometry {
  const SidebarDropGeometry(
    this.cards, {
    this.cardGap = 8,
    this.cardInset = 6,
    this.listWidth = 0,
  });

  final List<CardFrame> cards;
  final double cardGap;
  final double cardInset;
  final double listWidth;

  Drop? drop(DragItem item, Offset point) => switch (item) {
    DragBench(:final id) => _dropBench(id, point),
    DragProject(:final id) => _dropProject(id, point),
    DragWorkspace(:final id) => _dropWorkspace(id, point),
  };

  Drop? _dropBench(String id, Offset point) {
    final tile = _tileAt(point);
    if (tile == null) return null;
    var position = tile.rows.where((r) => point.dy > r.frame.center.dy).length;
    // Tirar a própria linha da conta: sem isso, arrastar para baixo dentro do
    // mesmo projeto cairia uma posição antes da desejada.
    final mine = tile.rows.indexWhere((r) => r.benchId == id);
    if (mine >= 0 && position > mine) position -= 1;
    return DropBench(tile.projectId, position);
  }

  Drop? _dropProject(String id, Offset point) {
    final card = _cardAt(point);
    if (card == null) return null;
    // Abaixo da tampa da gaveta é dentro dela: é assim que se guarda.
    final stored = point.dy > card.drawer.center.dy;
    final tiles = stored ? card.stored : card.projects;
    var position = tiles.where((t) => point.dy > t.frame.center.dy).length;
    final mine = tiles.indexWhere((t) => t.projectId == id);
    if (mine >= 0 && position > mine) position -= 1;
    return DropProject(card.workspaceId, position, stored: stored);
  }

  Drop _dropWorkspace(String id, Offset point) {
    var position = cards.where((c) => point.dy > c.frame.center.dy).length;
    final mine = cards.indexWhere((c) => c.workspaceId == id);
    if (mine >= 0 && position > mine) position -= 1;
    return DropWorkspace(position);
  }

  TileFrame? _tileAt(Offset point) {
    for (final card in cards) {
      for (final tile in [...card.projects, ...card.stored]) {
        if (_withGap(tile.frame).contains(point)) return tile;
      }
    }
    return null;
  }

  /// A folga entre ladrilhos também é do ladrilho: soltar entre dois não falha.
  Rect _withGap(Rect frame) => Rect.fromLTRB(
    frame.left,
    frame.top - cardGap / 2,
    frame.right,
    frame.bottom + cardGap / 2,
  );

  CardFrame? _cardAt(Offset point) {
    for (final card in cards) {
      if (_withGap(card.frame).contains(point)) return card;
    }
    return null;
  }

  /// O traço de 2 pontos onde o item vai entrar; `null` quando não há onde.
  Rect? guide(Drop target) {
    Rect? between(List<Rect> frames, int position, double x, double width) {
      if (frames.isEmpty) return null;
      final y = position >= frames.length
          ? frames.last.bottom
          : frames[position].top;
      return Rect.fromLTWH(x, y - 1, width, 2);
    }

    switch (target) {
      case DropWorkspace(:final position):
        return between(
          [for (final c in cards) c.frame],
          position,
          8,
          listWidth - 16,
        );
      case DropProject(:final workspaceId, :final position, :final stored):
        final card = cards
            .where((c) => c.workspaceId == workspaceId)
            .firstOrNull;
        if (card == null) return null;
        final tiles = stored ? card.stored : card.projects;
        final x = card.frame.left + cardInset;
        final width = card.frame.width - cardInset * 2;
        return between([for (final t in tiles) t.frame], position, x, width) ??
            // Gaveta fechada ou vazia: a guia encosta na tampa dela.
            Rect.fromLTWH(x, card.drawer.bottom - 1, width, 2);
      case DropBench(:final projectId, :final position):
        TileFrame? tile;
        for (final card in cards) {
          for (final t in card.projects) {
            if (t.projectId == projectId) tile = t;
          }
        }
        if (tile == null) return null;
        final x = tile.frame.left + cardInset;
        final width = tile.frame.width - cardInset * 2;
        return between(
              [for (final r in tile.rows) r.frame],
              position,
              x,
              width,
            ) ??
            // Projeto vazio: a guia vai logo abaixo do cabeçalho dele.
            Rect.fromLTWH(
              tile.header.left + cardInset,
              tile.header.bottom - 1,
              tile.header.width - cardInset * 2,
              2,
            );
    }
  }
}
