import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/attention_ring.dart';
import '../../../../commons/widgets/context_menu.dart';
import '../../../../commons/widgets/spinner.dart';
import '../../../../commons/widgets/workspace_badge.dart';
import '../../../../core/domain/entities/activity_summary.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/workbench_palette.dart';
import '../../domain/entities/sidebar_bench.dart';
import '../../../../commons/widgets/press_drag.dart';
import '../../../workbench/presentation/widgets/clock_text.dart';
import 'bench_actions.dart';
import 'drag_hooks.dart';

/// A linha de uma bancada. Expandida é um card de três linhas (quatro na aba
/// Ativas, que diz de onde a bancada vem); no trilho vira a pastilha da inicial
/// com o badge embaixo.
class SidebarBenchRow extends StatefulWidget {
  const SidebarBenchRow({
    required this.bench,
    required this.actions,
    this.compact = false,
    this.drag,
    super.key,
  });

  final SidebarBench bench;
  final BenchActions actions;
  final bool compact;

  /// Sem isto a linha não se arrasta (a aba Ativas e o trilho).
  final DragHooks? drag;

  static const height = 54.0;
  static const heightWithOwner = 66.0;
  static const compactHeight = 44.0;
  static const radius = 9.0;

  @override
  State<SidebarBenchRow> createState() => _SidebarBenchRowState();
}

class _SidebarBenchRowState extends State<SidebarBenchRow> {
  bool _hovering = false;

  SidebarBench get _bench => widget.bench;

  void _menu(Offset position) {
    final a = widget.actions;
    final bench = _bench;
    showContextMenu(
      context,
      position: position,
      entries: [
        MenuEntry('Renomear…', () => a.onRename(bench)),
        MenuEntry(
          'Duplicar em nova worktree…',
          () => a.onDuplicateAsWorktree(bench),
        ),
        MenuEntry('Regras da bancada…', () => a.onEditRules(bench)),
        MenuEntry(
          'Cor da bancada…',
          () => a.onRecolor(bench),
          leading: _bench.color == null
              ? null
              : _Dot(WorkbenchPalette.of(_bench.color)),
        ),
        const MenuEntry.separator(),
        MenuEntry('Limpar a bancada…', () => a.onClear(bench)),
        const MenuEntry.separator(),
        MenuEntry('Remover bancada…', () => a.onRemove(bench)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = WorkbenchPalette.of(_bench.color);
    final drag = widget.drag;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (d) => _menu(d.globalPosition),
        child: PressDrag(
          onClick: () => widget.actions.onSelect(_bench.id),
          onBegin: drag == null ? null : (p) => drag.onBegin(drag.item, p),
          onMove: drag?.onMove,
          onEnd: drag == null
              ? null
              : (cancelled) => drag.onEnd(cancelled: cancelled),
          child: Opacity(
            opacity: drag?.dimmed ?? false ? 0.5 : 1,
            child: widget.compact
                ? _Compact(bench: _bench, accent: accent)
                : _Expanded(bench: _bench, accent: accent, hovering: _hovering),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _Expanded extends StatelessWidget {
  const _Expanded({
    required this.bench,
    required this.accent,
    required this.hovering,
  });

  final SidebarBench bench;
  final Color accent;
  final bool hovering;

  @override
  Widget build(BuildContext context) {
    final removing = bench.removing;
    final owner = bench.owner;
    final tone = bench.selected
        ? AttentionTone.focus
        : AttentionTone.of(bench.activity);
    final nameColor = removing
        ? AppColors.white(0.35)
        : bench.selected
        ? const Color(0xFFFFFFFF)
        : AppColors.white(0.72);
    return AttentionRing(
      tone: tone,
      focusColor: accent,
      radius: SidebarBenchRow.radius,
      child: Container(
        height: owner == null
            ? SidebarBenchRow.height
            : SidebarBenchRow.heightWithOwner,
        decoration: BoxDecoration(
          color: bench.selected
              ? accent.withValues(alpha: 0.16)
              : AppColors.white(hovering ? 0.07 : 0.045),
          borderRadius: BorderRadius.circular(SidebarBenchRow.radius),
          border: bench.selected
              ? null
              : Border.all(color: AppColors.white(0.08)),
        ),
        child: Stack(
          children: [
            if (owner == null)
              Positioned(
                left: 13,
                top: 12,
                child: _Dot(bench.live ? accent : AppColors.white(0.22)),
              )
            else
              Positioned(
                left: 9,
                top: 0,
                bottom: 0,
                child: Center(
                  child: WorkspaceBadge(
                    name: owner.name,
                    iconPath: owner.icon,
                    selected: bench.selected,
                  ),
                ),
              ),
            Positioned(
              left: owner == null ? 32 : 46,
              right: 8,
              top: 8,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      bench.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: nameColor,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  _StatusText(
                    summary: bench.activity,
                    removing: removing,
                    compact: false,
                  ),
                ],
              ),
            ),
            if (owner != null)
              Positioned(
                left: 46,
                right: 8,
                top: 26,
                child: Text(
                  bench.project ?? 'sem projeto',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.white(0.55),
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            Positioned(
              left: owner == null ? 32 : 46,
              right: 8,
              top: owner == null ? 30 : 45,
              child: !bench.pathExists
                  ? Text(
                      'caminho não existe — ${bench.path}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: const Color(0xFFFF453A).withValues(alpha: 0.85),
                        decoration: TextDecoration.none,
                      ),
                    )
                  // Pasta que existe: a linha é do cronômetro.
                  : bench.clock == null
                  ? const SizedBox(height: 13)
                  : ClockText(bench.clock!, size: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _Compact extends StatelessWidget {
  const _Compact({required this.bench, required this.accent});

  final SidebarBench bench;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final tone = AttentionTone.of(bench.activity);
    final liveRing = bench.live && tone == null;
    return SizedBox(
      height: SidebarBenchRow.compactHeight,
      child: Column(
        children: [
          const SizedBox(height: 2),
          AttentionRing(
            tone: tone,
            radius: 7,
            lineWidth: 2,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bench.selected
                    ? accent.withValues(alpha: 0.85)
                    : AppColors.white(0.10),
                borderRadius: BorderRadius.circular(7),
                border: liveRing
                    ? Border.all(
                        color: accent.withValues(alpha: 0.75),
                        width: 2,
                      )
                    : null,
              ),
              child: Text(
                bench.initial,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: bench.selected
                      ? const Color(0xFFFFFFFF)
                      : AppColors.white(0.7),
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 14,
            child: _StatusText(
              summary: bench.activity,
              removing: bench.removing,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Os avisos da linha, na ordem fixa do ciclo — rodando, parou perguntando,
/// parou pronto —, porque ordenar por urgência faria a bolinha trocar de lugar.
class _StatusText extends StatelessWidget {
  const _StatusText({
    required this.summary,
    required this.removing,
    required this.compact,
  });

  final ActivitySummary summary;
  final bool removing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final animated = removing || summary.isWorking || summary.background > 0;
    if (!animated) return _text('⠋', '⏳');
    return SpinnerBuilder(
      builder: (_, glyph) => _text(glyph, SpinnerGlyph.hourglass()),
    );
  }

  Widget _text(String glyph, String hourglass) {
    final style = TextStyle(
      fontFamily: 'Menlo',
      fontSize: compact ? 10 : 12,
      fontWeight: compact ? FontWeight.w600 : FontWeight.w500,
      decoration: TextDecoration.none,
    );
    if (removing) {
      return Text(
        compact ? glyph : '$glyph removendo…',
        maxLines: 1,
        style: style.copyWith(
          fontSize: compact ? 10 : 10,
          color: const Color(0xFFFF453A).withValues(alpha: 0.8),
        ),
      );
    }
    if (summary.isPreparing && !compact) {
      return Text(
        '$glyph preparando…',
        maxLines: 1,
        style: style.copyWith(fontSize: 10, color: AppColors.white(0.35)),
      );
    }
    final spans = <InlineSpan>[];
    void add(String mark, int count, Color color) {
      if (count == 0) return;
      if (spans.isNotEmpty && !compact) spans.add(const TextSpan(text: ' '));
      spans.add(
        TextSpan(
          text: count > 1 ? '$mark$count' : mark,
          style: TextStyle(color: color),
        ),
      );
    }

    add(glyph, summary.starting, AppColors.white(compact ? 0.4 : 0.25));
    add(glyph, summary.working, AppColors.white(compact ? 0.75 : 0.45));
    add(hourglass, summary.background, AppColors.white(compact ? 0.75 : 0.45));
    add('●', summary.attention, AppColors.attention);
    add('●', summary.done, AppColors.done);
    if (spans.isEmpty) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 1,
      textAlign: compact ? TextAlign.center : TextAlign.right,
    );
  }
}
