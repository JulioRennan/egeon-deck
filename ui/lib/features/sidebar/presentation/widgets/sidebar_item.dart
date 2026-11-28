import 'package:flutter/widgets.dart';

import '../../../../commons/utils/bench_identity.dart';
import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/icon_button.dart';
import '../../../../commons/widgets/eg/motion.dart';
import '../../../../commons/widgets/eg/pressable.dart';
import '../../../../commons/widgets/eg/spinner.dart';
import '../../../../commons/widgets/eg/status_dot.dart';
import '../../../../commons/widgets/eg/status.dart';
import '../../../../commons/widgets/eg/tooltip.dart';
import '../../../../commons/widgets/press_drag.dart';
import '../../../../core/domain/entities/activity_summary.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/sidebar_bench.dart';
import '../../domain/entities/sidebar_tree.dart';
import 'bench_cost_label.dart';
import '../../../../commons/widgets/workspace_mark.dart';
import 'drag_hooks.dart';
import 'stack_badges.dart';

/// O que um item pede quando o ⋯ ou o botão direito abrem o menu: a âncora em
/// coordenadas globais (o botão, ou o ponto do clique).
typedef ItemMenu = void Function(Rect anchor);

/// A linha da barra lateral (DS `SidebarItem`) nos três níveis — workspace,
/// projeto e bancada —, com o mesmo corpo: hover `steel`, selecionada com o
/// fundo da cor da bancada, `⋯` que aparece no hover, clique, botão direito e
/// arrasto. Só o miolo muda de nível.
class SidebarItem extends StatefulWidget {
  /// Workspace: 36 de altura, a inicial em quadrado (ou a foto), o nome e
  /// "N bancadas"; o ponto laranja diz que algo precisa de você.
  const SidebarItem.workspace({
    required SidebarWorkspace this.workspace,
    required this.onPressed,
    required this.onMenu,
    this.drag,
    super.key,
  }) : project = null,
       bench = null,
       owner = null,
       onAdd = null,
       showOrigin = false,
       kind = SidebarItemKind.workspace;

  /// Projeto: 32 de altura, a pasta, o nome e a contagem; o `+` cria bancada
  /// ali.
  const SidebarItem.project({
    required SidebarProject this.project,
    required SidebarWorkspace this.owner,
    required this.onPressed,
    required this.onMenu,
    required VoidCallback this.onAdd,
    this.drag,
    super.key,
  }) : workspace = null,
       bench = null,
       showOrigin = false,
       kind = SidebarItemKind.project;

  /// Bancada: o nome na cor dela (até duas linhas), embaixo os estados e, à
  /// direita, o custo. Na visão Ativas [showOrigin] põe a inicial do workspace
  /// e o projeto entre o nome e os estados.
  const SidebarItem.bench({
    required SidebarBench this.bench,
    required this.onPressed,
    required this.onMenu,
    this.showOrigin = false,
    this.drag,
    super.key,
  }) : workspace = null,
       project = null,
       owner = null,
       onAdd = null,
       kind = SidebarItemKind.bench;

  final SidebarItemKind kind;
  final SidebarWorkspace? workspace;
  final SidebarProject? project;
  final SidebarWorkspace? owner;
  final SidebarBench? bench;
  final bool showOrigin;
  final VoidCallback onPressed;
  final ItemMenu onMenu;
  final VoidCallback? onAdd;

  /// Sem isto a linha não se arrasta.
  final DragHooks? drag;

  static const workspaceHeight = 44.0;

  @override
  State<SidebarItem> createState() => _SidebarItemState();
}

enum SidebarItemKind { workspace, project, bench }

class _SidebarItemState extends State<SidebarItem> {
  bool _hovered = false;
  bool _menuOpen = false;
  final _moreKey = GlobalKey();

  void _openMenu() {
    final box = _moreKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    setState(() => _menuOpen = true);
    widget.onMenu(box.localToGlobal(Offset.zero) & box.size);
    // O menu não avisa que fechou; o ⋯ some quando o cursor sai.
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _menuOpen = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final drag = widget.drag;
    final shown = _hovered || _menuOpen;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (d) => widget.onMenu(
          Rect.fromLTWH(d.globalPosition.dx, d.globalPosition.dy, 0, 0),
        ),
        child: Stack(
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: PressDrag(
                onClick: widget.onPressed,
                onBegin: drag == null
                    ? null
                    : (p) => drag.onBegin(drag.item, p),
                onMove: drag?.onMove,
                onEnd: drag == null
                    ? null
                    : (cancelled) => drag.onEnd(cancelled: cancelled),
                child: _Lifted(
                  lifted: drag?.dimmed ?? false,
                  child: switch (widget.kind) {
                    SidebarItemKind.workspace => _WorkspaceBody(
                      workspace: widget.workspace!,
                      hovered: _hovered,
                    ),
                    SidebarItemKind.project => _ProjectBody(
                      project: widget.project!,
                      hovered: _hovered,
                      showActions: shown,
                    ),
                    SidebarItemKind.bench => _BenchBody(
                      bench: widget.bench!,
                      hovered: _hovered,
                      showOrigin: widget.showOrigin,
                    ),
                  },
                ),
              ),
            ),
            if (widget.kind == SidebarItemKind.project)
              Positioned(
                // O vão de 14 que o projeto reserva depois da contagem.
                right: 28,
                top: 1,
                child: _Reveal(
                  shown: shown,
                  child: IconButton(
                    icon: EgIcons.plus,
                    tooltip: 'Nova bancada neste projeto',
                    compact: true,
                    onPressed: widget.onAdd,
                  ),
                ),
              ),
            Positioned(
              right: 4,
              top: widget.kind == SidebarItemKind.bench ? 8 : 3,
              child: KeyedSubtree(
                key: _moreKey,
                child: _Reveal(
                  shown: shown,
                  child: IconButton(
                    icon: EgIcons.more,
                    tooltip: 'Mais ações',
                    compact: true,
                    onPressed: _openMenu,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// O item que está na mão: esmaecido e com a sombra de arrasto.
class _Lifted extends StatelessWidget {
  const _Lifted({required this.lifted, required this.child});

  final bool lifted;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: lifted ? 0.5 : 1,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: lifted ? EgeonShadow.drag : null,
      ),
      child: child,
    ),
  );
}

/// O botão que só aparece no hover (e fica quando o menu dele está aberto).
class _Reveal extends StatelessWidget {
  const _Reveal({required this.shown, required this.child});

  final bool shown;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: shown ? 1 : EgeonOpacity.hoverReveal,
    duration: egDuration(context, EgeonMotion.instant),
    child: IgnorePointer(ignoring: !shown, child: child),
  );
}

TextStyle _text(TextStyle base, Color color, {FontWeight? weight}) =>
    base.copyWith(
      color: color,
      fontWeight: weight,
      decoration: TextDecoration.none,
    );

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({required this.workspace, required this.hovered});

  final SidebarWorkspace workspace;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final ws = workspace;
    final count = ws.benchCount;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hovered ? EgeonColors.overlay4 : null,
        borderRadius: BorderRadius.circular(EgeonRadius.sm),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: SidebarItem.workspaceHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(EgeonSpace.s2, 6, 36, 6),
          child: Row(
            children: [
              _Chevron(open: !ws.collapsed),
              const SizedBox(width: EgeonSpace.s2),
              WorkspaceMark(name: ws.name, iconPath: ws.icon),
              const SizedBox(width: EgeonSpace.s2),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ws.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _text(
                        EgeonType.small,
                        c.textPrimary,
                        weight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      count == 1 ? '1 bancada' : '$count bancadas',
                      maxLines: 1,
                      style: _text(
                        EgeonType.caption,
                        c.textMuted,
                        weight: FontWeight.w400,
                      ).copyWith(letterSpacing: 0),
                    ),
                  ],
                ),
              ),
              if (ws.activity.wantsAttention) ...[
                const SizedBox(width: EgeonSpace.s2),
                const StatusDot(Status.attention, size: StatusDotSize.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: open ? 0.25 : 0,
    duration: egDuration(context, EgeonMotion.fast),
    child: EgIcon(EgIcons.chevronRight, size: 12, color: context.eg.textMuted),
  );
}

class _ProjectBody extends StatelessWidget {
  const _ProjectBody({
    required this.project,
    required this.hovered,
    required this.showActions,
  });

  final SidebarProject project;
  final bool hovered;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final p = project;
    final empty = p.benches.isEmpty;
    final missing = !p.isMulti && !p.pathExists;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hovered ? EgeonColors.overlay4 : null,
        borderRadius: BorderRadius.circular(EgeonRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 36, 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    if (empty)
                      const SizedBox(width: 12)
                    else
                      _Chevron(open: !p.collapsed),
                    const SizedBox(width: EgeonSpace.s2),
                    EgIcon(
                      p.stored ? EgIcons.archive : EgIcons.folder,
                      size: 14,
                      color: hovered ? c.textPrimary : c.textSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: EgeonSpace.s2),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: missing
                          ? 'caminho não existe — ${p.path}'
                          : p.isMulti
                          ? p.joins.join(' + ')
                          : p.path,
                      child: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _text(
                          EgeonType.small,
                          missing ? c.danger : c.textPrimary,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ),
                    StackBadges(p.stacks),
                  ],
                ),
              ),
              const SizedBox(width: EgeonSpace.s2),
              if (missing)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: EgIcon(
                    EgIcons.alert,
                    size: EgeonSize.iconSm,
                    color: c.danger,
                  ),
                )
              else if (p.benches.isNotEmpty)
                Text(
                  '${p.benches.length}',
                  style: _text(
                    EgeonType.monoMeta,
                    c.textMuted,
                  ).copyWith(fontWeight: FontWeight.w400),
                ),
              // O vão do `+` (14), que aparece no hover por cima dele.
              const SizedBox(width: EgeonSpace.s2 + 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _BenchBody extends StatelessWidget {
  const _BenchBody({
    required this.bench,
    required this.hovered,
    required this.showOrigin,
  });

  final SidebarBench bench;
  final bool hovered;
  final bool showOrigin;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final color = BenchIdentity.of(bench.color).color(c);
    final selected = bench.selected;
    final lit = selected || hovered;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // O fundo da cor dela a 12% (selecionada ou sob o mouse), raio 6.
        DecoratedBox(
          decoration: BoxDecoration(
            color: lit ? color.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(EgeonRadius.sm),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 26),
                  child: Text(
                    bench.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _text(
                      EgeonType.label,
                      bench.removing ? c.textDisabled : color,
                      weight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (showOrigin && bench.project != null) ...[
                  const SizedBox(height: EgeonSpace.s2),
                  _Origin(owner: bench.owner, project: bench.project!),
                ],
                const SizedBox(height: EgeonSpace.s2),
                BenchStatusLine(bench: bench),
              ],
            ),
          ),
        ),
        // O traço sobre o fio da árvore, 11 à esquerda do cartão: curto e a
        // 60% em repouso; no hover e na selecionada, de ponta a ponta e a 100%.
        Positioned(
          left: -11,
          top: lit ? 0 : 12,
          bottom: lit ? 0 : 12,
          width: 2,
          child: IgnorePointer(
            child: DecoratedBox(
              key: const ValueKey('bench-bar'),
              decoration: BoxDecoration(
                color: color.withValues(alpha: lit ? 1 : 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// De onde a bancada vem, na visão Ativas: a inicial do workspace (14, raio 4)
/// e o nome do projeto.
class _Origin extends StatelessWidget {
  const _Origin({required this.owner, required this.project});

  final BenchOwner? owner;
  final String project;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Row(
      children: [
        if (owner != null) ...[
          SizedBox(
            width: 14,
            height: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.steelActive,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  owner!.initial,
                  key: const ValueKey('bench-origin-initial'),
                  style: TextStyle(
                    fontFamily: EgeonType.sans,
                    fontFamilyFallback: EgeonType.sansFallback,
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            project,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _text(
              EgeonType.caption,
              c.textSecondary,
              weight: FontWeight.w400,
            ).copyWith(letterSpacing: 0),
          ),
        ),
      ],
    );
  }
}

/// A linha de baixo da bancada: os estados que ela tem, todos de uma vez
/// ("1 terminou", "2 em trabalho"…), e o custo na ponta. Pedido esperando você
/// em laranja, "terminou" em verde,
/// trabalhando com o giro, e "Parada" só quando nada disso se aplica.
class BenchStatusLine extends StatelessWidget {
  const BenchStatusLine({required this.bench, super.key});

  final SidebarBench bench;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final a = bench.activity;
    final small = _text(
      EgeonType.caption,
      c.textSecondary,
      weight: FontWeight.w400,
    ).copyWith(letterSpacing: 0);
    Widget status(
      Widget glyph,
      String text,
      Color color, {
      FontWeight? weight,
      Key? key,
    }) => Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 12, height: 12, child: Center(child: glyph)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: small.copyWith(color: color, fontWeight: weight),
          ),
        ),
      ],
    );

    final working = a.working + a.starting + a.background;
    final done = a.done;
    final states = <Widget>[];
    if (!bench.pathExists) {
      states.add(
        Text(
          'caminho não existe — ${bench.path}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: small.copyWith(color: c.danger),
        ),
      );
    } else if (bench.removing) {
      states.add(status(const Spinner(size: 12), 'removendo…', c.danger));
    } else {
      if (a.attention > 0) {
        states.add(
          status(
            const StatusDot(
              Status.attention,
              size: StatusDotSize.sm,
              animated: true,
            ),
            '${a.attention} esperando você',
            c.attention,
            weight: FontWeight.w500,
            key: const ValueKey('state-needs'),
          ),
        );
      }
      if (done > 0) {
        states.add(
          status(
            const StatusDot(Status.success, size: StatusDotSize.sm),
            done == 1 ? '1 terminou' : '$done terminaram',
            c.success,
            weight: FontWeight.w500,
            key: const ValueKey('state-done'),
          ),
        );
      }
      if (a.isPreparing) {
        states.add(
          status(
            const Spinner(size: 12),
            'preparando…',
            c.textMuted,
            key: const ValueKey('state-preparing'),
          ),
        );
      } else if (working > 0) {
        states.add(
          status(
            const Spinner(size: 12),
            '$working em trabalho',
            c.textPrimary,
            key: const ValueKey('state-work'),
          ),
        );
      }
      if (states.isEmpty) {
        states.add(
          status(
            const StatusDot(Status.idle, size: StatusDotSize.sm),
            'Parada',
            c.textSecondary,
            key: const ValueKey('state-idle'),
          ),
        );
      }
    }
    // O título, os estados e o preço são três linhas: o preço fica sempre
    // embaixo, numa linha só dele, mesmo quando cabia ao lado dos estados
    // (pedido do Julio).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: EgeonSpace.s1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: states,
        ),
        BenchCostLabel(workbenchId: bench.id, gap: EgeonSpace.s1),
      ],
    );
  }
}

/// A gaveta dos guardados: aparece sempre, mesmo vazia, porque é o alvo para
/// onde se arrasta o primeiro projeto.
class DrawerRow extends StatelessWidget {
  const DrawerRow({
    required this.count,
    required this.open,
    required this.onToggle,
    super.key,
  });

  final int count;
  final bool open;
  final VoidCallback onToggle;

  static const height = 28.0;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final label = count == 0 ? 'Gaveta vazia' : 'Gaveta · $count';
    // Vazia não abre nada: fica ali como alvo de queda.
    return Pressable(
      onPressed: count > 0 ? onToggle : null,
      semanticLabel: count == 0
          ? 'Gaveta de projetos guardados, vazia'
          : 'Gaveta de projetos guardados, $count',
      builder: (context, s) {
        final color = (s.hovered || s.pressed) && count > 0
            ? c.textSecondary
            : c.textMuted;
        return SizedBox(
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: (s.hovered || s.pressed) && count > 0
                  ? EgeonColors.overlay2
                  : null,
              borderRadius: BorderRadius.circular(EgeonRadius.sm),
            ),
            child: Row(
              children: [
                // O ícone fica 30 à direita da borda (alinhado ao nome do
                // projeto); com projetos guardados, a seta cabe no recuo.
                if (count > 0) ...[
                  const SizedBox(width: 10),
                  _Chevron(open: open),
                  const SizedBox(width: EgeonSpace.s2),
                ] else
                  const SizedBox(width: 30),
                EgIcon(EgIcons.archive, size: 14, color: color),
                const SizedBox(width: EgeonSpace.s2),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _text(
                      EgeonType.caption,
                      color,
                      weight: FontWeight.w500,
                    ).copyWith(letterSpacing: 0),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Resumo de atividade de um grupo, para quem precisa de um texto curto.
String activityLabel(ActivitySummary a) {
  if (a.attention > 0) return '${a.attention} esperando você';
  if (a.isWorking) return '${a.working + a.starting} em trabalho';
  if (a.done > 0) return a.done == 1 ? '1 terminou' : '${a.done} terminaram';
  return 'Parada';
}
