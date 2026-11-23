import 'dart:ui';

import '../../../../core/domain/entities/workbench_node.dart';
import '../../../node/card/domain/entities/card_activity.dart';

/// Um nó posicionado no canvas. O frame é o que o core grava; o resto é o que
/// o cabeçalho e o corpo do card mostram.
class CanvasCard {
  const CanvasCard({
    required this.id,
    required this.kind,
    required this.frame,
    this.title = '',
    this.address = '',
    this.cliName,
    this.subtitle = '',
    this.screen,
    this.url,
    this.alive = true,
    this.maestro = false,
    this.activity = CardActivity.none,
    this.port = false,
    this.linkable = const [],
  });

  /// Duas linhas no cabeçalho: nome em cima, pasta embaixo.
  static const headerHeight = 46.0;
  static const minSize = Size(280, 180);

  /// Onde mostrar um nó que chegou sem frame. O core dá o frame ao criar e ao
  /// abrir a bancada, então isto é só rede de segurança: não se grava.
  static const fallbackFrame = Rect.fromLTWH(40, 40, 720, 460);

  final String id;
  final NodeKind kind;
  final Rect frame;

  /// O id do nó, como no Swift.
  final String title;

  /// `bancada/nó`, o endereço de dispatch, como o core o monta.
  final String address;

  /// O nome do CLI do agente; nulo em shell, web e fila.
  final String? cliName;

  /// A dica do título, como no Swift: o endereço e, no agente, o CLI.
  String get titleTooltip => switch (cliName) {
    final cli? => '$address · $cli',
    null => address,
  };

  /// A pasta (com `~`) ou, no nó web, o endereço.
  final String subtitle;

  /// O id que se assina em `screen/<id>` para a tela do terminal.
  final String? screen;
  final String? url;
  final bool alive;
  final bool maestro;
  final CardActivity activity;

  /// O card tem a porta de ligação (o `+`), como o core decide: não depende de
  /// haver destino livre.
  final bool port;

  /// Os nós em que dá para soltar a ligação, como o core decide.
  final List<String> linkable;

  /// O nó como o core o manda em `workbench/<id>/nodes`.
  factory CanvasCard.fromNode(Map<String, Object?> map) {
    final f = map['frame'] as Map<String, Object?>?;
    final kind = NodeKind.fromWire(map['type']);
    final id = map['id']! as String;
    return CanvasCard(
      id: id,
      kind: kind,
      title: id,
      address: map['address'] as String? ?? '',
      cliName: map['cli_name'] as String?,
      subtitle: switch (kind) {
        NodeKind.web => map['url'] as String? ?? '',
        // A fila diz quantas tarefas esperam, no lugar da pasta.
        NodeKind.queue => map['subtitle'] as String? ?? '',
        _ => map['dir'] as String? ?? '',
      },
      screen: map['screen'] as String?,
      url: map['url'] as String?,
      alive: map['alive'] as bool? ?? true,
      maestro: map['maestro'] as bool? ?? false,
      activity: CardActivity.fromMap(map['activity'] as Map<String, Object?>?),
      frame: f == null ? fallbackFrame : _rect(f),
      port: map['port'] as bool? ?? false,
      linkable: [
        for (final id in (map['linkable'] as List<Object?>? ?? const []))
          id! as String,
      ],
    );
  }

  static Rect _rect(Map<String, Object?> f) => Rect.fromLTWH(
    (f['x']! as num).toDouble(),
    (f['y']! as num).toDouble(),
    (f['w']! as num).toDouble(),
    (f['h']! as num).toDouble(),
  );

  CanvasCard copyWith({Rect? frame, bool? port, List<String>? linkable}) =>
      CanvasCard(
        id: id,
        kind: kind,
        frame: frame ?? this.frame,
        title: title,
        address: address,
        cliName: cliName,
        subtitle: subtitle,
        screen: screen,
        url: url,
        alive: alive,
        maestro: maestro,
        activity: activity,
        port: port ?? this.port,
        linkable: linkable ?? this.linkable,
      );
}
