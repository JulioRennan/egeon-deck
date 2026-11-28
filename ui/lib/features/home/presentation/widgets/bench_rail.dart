import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/widgets.dart';

import '../../../../commons/utils/bench_identity.dart';
import '../../../../commons/widgets/eg/attention_ring.dart';
import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/glass_surface.dart';
import '../../../../commons/widgets/eg/menu.dart';
import '../../../../commons/widgets/eg/pressable.dart';
import '../../../../commons/widgets/eg/spinner.dart';
import '../../../../commons/widgets/eg/tool_button.dart';
import '../../../../commons/widgets/eg/tooltip.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import '../../../tabs/domain/entities/workbench_tab.dart';
import 'drawer_hover.dart';
import '../../../../commons/utils/app_shortcut.dart';

/// O trilho de bancadas à esquerda: duas pastilhas de vidro, uma com "Nova
/// bancada" e outra com "Todas as bancadas" (abre a gaveta, com o total de
/// pedidos que esperam você) e uma tecla por bancada aberta. Cada tecla traz
/// as iniciais na cor da bancada, o fundo tingido e o traço de 2px na atual e
/// o estado de quem trabalha, terminou ou espera você.
class BenchRail extends StatelessWidget {
  const BenchRail({
    required this.tabs,
    required this.drawerOpen,
    required this.onPick,
    required this.onNew,
    required this.onToggleDrawer,
    this.onClose,
    this.onReorder,
    this.drawerGroup,
    this.drawerHover,
    super.key,
  });

  final List<WorkbenchTab> tabs;
  final bool drawerOpen;
  final ValueChanged<String> onPick;
  final VoidCallback onNew;
  final VoidCallback onToggleDrawer;

  /// "Fechar bancada" no menu do botão direito (a bancada segue rodando).
  final ValueChanged<String>? onClose;

  /// Soltar uma tecla noutro lugar: a nova ordem, só com os ids.
  final ValueChanged<List<String>>? onReorder;

  /// O grupo da gaveta: clicar na tecla dela não conta como clique fora.
  final Object? drawerGroup;

  /// Passar o mouse no botão da gaveta a abre.
  final DrawerHover? drawerHover;

  /// A coluna do trilho: 4 de respiro e uma tecla de 36.
  static const width = 44.0;
  static const left = 24.0;

  /// As iniciais da bancada: a primeira letra em maiúscula e a segunda como
  /// está.
  static String initials(String name) {
    final letters = name.trim().characters.take(2).toList();
    if (letters.isEmpty) return '?';
    return [letters.first.toUpperCase(), ...letters.skip(1)].join();
  }

  /// Quantos pedidos esperam você, somando as bancadas.
  int get _attention => tabs.fold(0, (sum, t) => sum + t.summary.attention);

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    // A faixa inteira à esquerda da moldura, da borda da janela até ela e de
    // cima a baixo, abre a gaveta com o mouse.
    return DrawerHoverRegion(
      hover: drawerHover,
      opens: true,
      child: Padding(
        padding: const EdgeInsets.only(left: left),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassSurface(
                  padding: const EdgeInsets.all(EgeonSpace.s1),
                  child: ToolButton(
                    icon: EgIcons.plus,
                    tooltip: 'Nova bancada',
                    onPressed: onNew,
                  ),
                ),
                const SizedBox(height: EgeonSpace.s3),
                Flexible(
                  child: GlassSurface(
                    padding: const EdgeInsets.all(EgeonSpace.s1),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TapRegion(
                          groupId: drawerGroup,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ToolButton(
                                icon: EgIcons.sidebar,
                                tooltip: 'Todas as bancadas',
                                shortcut: appShortcutLabel('/'),
                                selected: drawerOpen,
                                onPressed: onToggleDrawer,
                              ),
                              if (_attention > 0)
                                Positioned(
                                  right: 1,
                                  top: 1,
                                  child: IgnorePointer(
                                    child: AttentionRing(
                                      round: true,
                                      ring: false,
                                      child: _NeedsCount(_attention),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: EgeonSpace.s1,
                          ),
                          child: SizedBox(
                            width: 20,
                            height: 1,
                            child: ColoredBox(color: c.line),
                          ),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            child: _RailList(
                              tabs: tabs,
                              onPick: onPick,
                              onClose: onClose,
                              onReorder: onReorder,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// As teclas das bancadas, na ordem do core. Arrastar uma na vertical a muda de
/// lugar (a ordem nova só vai ao core ao soltar) e o botão direito abre o menu
/// com "Fechar bancada".
class _RailList extends StatefulWidget {
  const _RailList({
    required this.tabs,
    required this.onPick,
    required this.onClose,
    required this.onReorder,
  });

  final List<WorkbenchTab> tabs;
  final ValueChanged<String> onPick;
  final ValueChanged<String>? onClose;
  final ValueChanged<List<String>>? onReorder;

  @override
  State<_RailList> createState() => _RailListState();
}

class _RailListState extends State<_RailList> {
  static const _pitch = EgeonSize.controlMd + EgeonSpace.s1;

  List<String>? _order;
  String? _dragging;
  double _dy = 0;
  int _from = 0;

  List<String> get _ids => _order ?? [for (final t in widget.tabs) t.id];

  void _start(String id) {
    final ids = _ids;
    setState(() {
      _order = [...ids];
      _dragging = id;
      _dy = 0;
      _from = ids.indexOf(id);
    });
  }

  void _update(double delta) {
    final id = _dragging;
    final order = _order;
    if (id == null || order == null) return;
    _dy += delta;
    final target = (_from + (_dy / _pitch).round()).clamp(0, order.length - 1);
    setState(() {
      if (order.indexOf(id) != target) {
        order
          ..remove(id)
          ..insert(target, id);
      }
    });
  }

  void _end() {
    final order = _order;
    final changed =
        order != null &&
        !_sameOrder(order, [for (final t in widget.tabs) t.id]);
    setState(() {
      _order = null;
      _dragging = null;
      _dy = 0;
    });
    if (changed) widget.onReorder?.call(order);
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final t in widget.tabs) t.id: t};
    final ids = [
      for (final id in _ids)
        if (byId.containsKey(id)) id,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final id in ids) ...[
          _tile(context, byId[id]!, ids.indexOf(id)),
          if (id != ids.last) const SizedBox(height: EgeonSpace.s1),
        ],
      ],
    );
  }

  Widget _tile(BuildContext context, WorkbenchTab tab, int index) {
    final dragging = _dragging == tab.id;
    // A tecla arrastada segue o dedo: o quanto ela já andou menos o que o
    // lugar novo já cobre.
    final shift = dragging ? _dy - (index - _from) * _pitch : 0.0;
    return Transform.translate(
      key: ValueKey('rail-${tab.id}'),
      offset: Offset(0, shift),
      child: GestureDetector(
        // O arrasto conta desde o toque: a folga de 18px não some do caminho.
        dragStartBehavior: DragStartBehavior.down,
        onVerticalDragStart: widget.onReorder == null
            ? null
            : (_) => _start(tab.id),
        onVerticalDragUpdate: widget.onReorder == null
            ? null
            : (d) => _update(d.delta.dy),
        onVerticalDragEnd: widget.onReorder == null ? null : (_) => _end(),
        onVerticalDragCancel: widget.onReorder == null ? null : _end,
        child: RailBench(
          tab: tab,
          onPressed: () => widget.onPick(tab.id),
          onClose: widget.onClose == null
              ? null
              : () => widget.onClose!(tab.id),
        ),
      ),
    );
  }
}

/// O que a tecla da bancada mostra no canto.
enum RailBadge { none, attention, done, working }

/// Uma bancada no trilho. O estado que aparece é um só: pedido esperando você
/// primeiro, depois "terminou" e por fim o trabalho.
class RailBench extends StatelessWidget {
  const RailBench({
    required this.tab,
    required this.onPressed,
    this.onClose,
    super.key,
  });

  final WorkbenchTab tab;
  final VoidCallback onPressed;

  /// Ligado, o botão direito abre o menu "Fechar bancada".
  final VoidCallback? onClose;

  RailBadge get badge {
    final s = tab.summary;
    if (s.attention > 0) return RailBadge.attention;
    if (s.done > 0) return RailBadge.done;
    if (s.isWorking) return RailBadge.working;
    return RailBadge.none;
  }

  /// "2 esperando você", "terminou", "1 em trabalho" ou "parada".
  String get status => switch (badge) {
    RailBadge.attention => '${tab.summary.attention} esperando você',
    RailBadge.done => 'terminou',
    RailBadge.working =>
      '${tab.summary.working + tab.summary.starting} em trabalho',
    RailBadge.none => 'parada',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final color = BenchIdentity.of(tab.color).color(c);
    final label = '${tab.name} · $status';
    return Tooltip(
      message: label,
      child: Pressable(
        onPressed: onPressed,
        onSecondaryPressed: onClose == null
            ? null
            : () {
                final box = context.findRenderObject()! as RenderBox;
                showMenu(
                  context,
                  anchor:
                      Offset(
                        box.localToGlobal(Offset.zero).dx + box.size.width + 6,
                        box.localToGlobal(Offset.zero).dy,
                      ) &
                      Size.zero,
                  items: [
                    MenuItem(
                      'Fechar bancada',
                      icon: EgIcons.x,
                      shortcut: appShortcutLabel('W'),
                      onSelected: onClose,
                    ),
                  ],
                );
              },
        semanticLabel: label,
        builder: (context, s) => Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: tab.isActive
                    ? color.withValues(alpha: 0.14)
                    : (s.hovered ? c.steel : EgeonColors.overlay4),
                borderRadius: BorderRadius.circular(EgeonRadius.md),
                border: s.focused
                    ? Border.all(color: c.accent, width: EgeonBorder.focus)
                    : null,
              ),
              child: SizedBox(
                width: EgeonSize.controlMd,
                height: EgeonSize.controlMd,
                child: Center(
                  child: Text(
                    BenchRail.initials(tab.name),
                    style: EgeonType.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                      height: 1,
                      color: color,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
            if (tab.isActive)
              Positioned(
                left: -4,
                top: 6,
                bottom: 6,
                width: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            if (badge != RailBadge.none)
              Positioned(right: -2, top: -2, child: _BadgeDot(badge)),
          ],
        ),
      ),
    );
  }
}

/// O selo de pedidos no botão da gaveta (a v3): pílula laranja de 15, mono 10
/// w600 em `onAttention`.
class _NeedsCount extends StatelessWidget {
  const _NeedsCount(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Semantics(
      label: '$count esperando você',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.attention,
          borderRadius: BorderRadius.circular(EgeonRadius.full),
        ),
        child: SizedBox(
          height: 15,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 15),
            child: Center(
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '$count',
                  style: EgeonType.monoMeta.copyWith(
                    color: c.onAttention,
                    fontSize: 10,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgeDot extends StatelessWidget {
  const _BadgeDot(this.badge);

  final RailBadge badge;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    Widget dot(Color color) => DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        // O anel de 2px na cor da pastilha recorta o ponto da tecla.
        boxShadow: [BoxShadow(color: c.graphite, spreadRadius: 2)],
      ),
      child: const SizedBox(width: 8, height: 8),
    );
    return switch (badge) {
      RailBadge.attention => AttentionRing(
        round: true,
        ring: false,
        child: dot(c.attention),
      ),
      // O "terminou" pulsa como o `.pulse-g` da v3: o mesmo halo do "precisa
      // de você", em verde.
      RailBadge.done => AttentionRing(
        round: true,
        ring: false,
        color: c.success,
        child: dot(c.success),
      ),
      RailBadge.working => DecoratedBox(
        decoration: BoxDecoration(color: c.graphite, shape: BoxShape.circle),
        child: const Padding(
          padding: EdgeInsets.all(1),
          child: Spinner(size: 10),
        ),
      ),
      RailBadge.none => const SizedBox.shrink(),
    };
  }
}
