import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/context_menu.dart';
import '../../../../commons/widgets/count_seal.dart';
import '../../../../commons/widgets/glyphs.dart';
import '../../../../commons/widgets/spinner.dart';
import '../../../../commons/widgets/workspace_badge.dart';
import '../../../../core/domain/entities/activity_summary.dart';
import '../../../../theme/app_colors.dart';
import '../../domain/entities/sidebar_tree.dart';
import '../../../../commons/widgets/press_drag.dart';
import 'drag_hooks.dart';
import 'group_actions.dart';

/// O cabeçalho de um grupo da árvore: workspace, projeto ou a pilha de órfãs.
class SidebarGroupRow extends StatefulWidget {
  const SidebarGroupRow.workspace({
    required SidebarWorkspace this.workspace,
    required GroupActions this.actions,
    this.compact = false,
    this.drag,
    super.key,
  }) : project = null,
       owner = null,
       orphanCount = 0;

  const SidebarGroupRow.project({
    required SidebarWorkspace this.owner,
    required SidebarProject this.project,
    required GroupActions this.actions,
    this.compact = false,
    this.drag,
    super.key,
  }) : workspace = null,
       orphanCount = 0;

  const SidebarGroupRow.orphans({
    required this.orphanCount,
    this.compact = false,
    super.key,
  }) : workspace = null,
       project = null,
       owner = null,
       actions = null,
       drag = null;

  final SidebarWorkspace? workspace;
  final SidebarProject? project;

  /// O workspace de um projeto.
  final SidebarWorkspace? owner;
  final int orphanCount;
  final GroupActions? actions;
  final bool compact;

  /// Sem isto o cabeçalho não se arrasta (o trilho).
  final DragHooks? drag;

  static const height = 44.0;
  static const badgeSide = 28.0;

  @override
  State<SidebarGroupRow> createState() => _SidebarGroupRowState();
}

class _SidebarGroupRowState extends State<SidebarGroupRow> {
  bool _hovering = false;

  SidebarWorkspace? get _ws => widget.workspace;
  SidebarProject? get _pr => widget.project;
  bool get _isOrphans => widget.orphanCount > 0;

  bool get _collapsed => _ws?.collapsed ?? _pr?.collapsed ?? false;

  int get _count => _ws?.projects.length ?? _pr?.benches.length ?? 0;

  bool get _emptyProject => _pr != null && _pr!.benches.isEmpty;

  ActivitySummary get _summary {
    if (_pr != null) return _pr!.activity;
    return _ws?.activity ?? ActivitySummary.none;
  }

  void _toggle() {
    final actions = widget.actions;
    if (actions == null) return;
    if (_emptyProject) return _create(actions);
    if (_ws != null) return actions.onToggleWorkspace(_ws!.id);
    actions.onToggleProject(widget.owner!.id, _pr!.id);
  }

  void _create(GroupActions actions) => actions.onCreateBenchFromWorktree(_pr!);

  void _menu(Offset position) {
    final a = widget.actions;
    if (a == null) return;
    final ws = _ws;
    final pr = _pr;
    final entries = <MenuEntry>[
      if (ws != null) ...[
        MenuEntry('Novo projeto…', () => a.onCreateProject(ws)),
        MenuEntry('Editar workspace…', () => a.onEditWorkspace(ws)),
        const MenuEntry.separator(),
        MenuEntry('Remover workspace…', () => a.onRemoveWorkspace(ws)),
      ],
      if (pr != null) ...[
        if (!pr.isMulti) MenuEntry('Nova bancada…', () => a.onCreateBench(pr)),
        MenuEntry(
          'Nova bancada em worktree…',
          () => a.onCreateBenchFromWorktree(pr),
        ),
        const MenuEntry.separator(),
        MenuEntry(
          pr.stored ? 'Tirar da gaveta' : 'Guardar na gaveta',
          () => a.onSetStored(widget.owner!.id, pr.id, stored: !pr.stored),
        ),
        const MenuEntry.separator(),
        MenuEntry(
          'Tirar projeto do workspace…',
          () => a.onRemoveProject(widget.owner!, pr),
        ),
      ],
    ];
    if (entries.isNotEmpty) {
      showContextMenu(context, position: position, entries: entries);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = _ws;
    final pr = _pr;
    final orphan = _isOrphans;
    final compact = widget.compact;

    final String title;
    final String subtitle;
    Color subtitleColor = AppColors.white(0.42);
    Color titleColor;
    FontWeight weight = FontWeight.w600;
    if (ws != null) {
      title = ws.name;
      subtitle = ws.benchCount == 1 ? '1 bancada' : '${ws.benchCount} bancadas';
      titleColor = AppColors.white(0.92);
      weight = FontWeight.w700;
    } else if (pr != null) {
      title = pr.name;
      subtitle = pr.isMulti
          ? pr.joins.join(' + ')
          : pr.pathExists
          ? pr.path
          : 'caminho não existe — ${pr.path}';
      if (!pr.isMulti && !pr.pathExists) {
        subtitleColor = const Color(0xFFFF453A).withValues(alpha: 0.85);
      }
      titleColor = AppColors.white(0.8);
    } else {
      title = 'Sem projeto';
      subtitle = '${widget.orphanCount} bancada(s) com projeto que não existe';
      titleColor = AppColors.attention.withValues(alpha: 0.9);
      subtitleColor = AppColors.attention.withValues(alpha: 0.6);
    }

    final leading = ws != null
        ? WorkspaceBadge(
            name: ws.name,
            iconPath: ws.icon,
            side: SidebarGroupRow.badgeSide,
            wantsAttention:
                (compact || ws.collapsed) && _summary.wantsAttention,
          )
        : FolderGlyph(
            orphan
                ? FolderKind.missing
                : pr!.stored
                ? FolderKind.stored
                : pr.isMulti
                ? FolderKind.multi
                : FolderKind.plain,
            color: orphan
                ? AppColors.attention.withValues(alpha: 0.7)
                : AppColors.white(pr!.stored ? 0.32 : 0.5),
          );

    final body = Container(
      height: SidebarGroupRow.height,
      decoration: BoxDecoration(
        color: _hovering ? AppColors.white(0.06) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: compact
          ? Center(child: leading)
          : _expanded(
              leading: leading,
              title: title,
              titleColor: titleColor,
              weight: weight,
              subtitle: subtitle,
              subtitleColor: subtitleColor,
              orphan: orphan,
            ),
    );
    final drag = widget.drag;
    return MouseRegion(
      cursor: orphan ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = !compact && !orphan),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: orphan ? null : (d) => _menu(d.globalPosition),
        // A pilha das órfãs é rótulo, não linha: não abre, não fecha, não arrasta.
        child: orphan
            ? body
            : PressDrag(
                onClick: _toggle,
                onBegin: drag == null
                    ? null
                    : (point) => drag.onBegin(drag.item, point),
                onMove: drag?.onMove,
                onEnd: drag == null
                    ? null
                    : (cancelled) => drag.onEnd(cancelled: cancelled),
                child: Opacity(
                  opacity: drag?.dimmed ?? false ? 0.5 : 1,
                  child: body,
                ),
              ),
      ),
    );
  }

  Widget _expanded({
    required Widget leading,
    required String title,
    required Color titleColor,
    required FontWeight weight,
    required String subtitle,
    required Color subtitleColor,
    required bool orphan,
  }) {
    final showSummary = _collapsed;
    final seal = _count > 0 && !orphan;
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 10),
      child: Row(
        children: [
          SizedBox(
            width: _ws != null ? SidebarGroupRow.badgeSide : 18,
            height: SidebarGroupRow.badgeSide,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                leading,
                if (seal)
                  Positioned(
                    right: _ws != null ? -6 : -10,
                    bottom: -4,
                    child: CountSeal(_count),
                  ),
              ],
            ),
          ),
          SizedBox(width: _ws != null ? 10 : 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: weight,
                    color: titleColor,
                    decoration: TextDecoration.none,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: subtitleColor,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          if (showSummary) _GroupStatus(_summary),
          if (_pr != null && widget.actions != null) ...[
            _AddButton(
              onTap: () => _pr!.isMulti
                  ? widget.actions!.onCreateBenchFromWorktree(_pr!)
                  : _addMenu(),
            ),
            const SizedBox(width: 4),
          ],
          if (!orphan && !_emptyProject)
            ChevronGlyph(
              _collapsed ? ChevronDirection.right : ChevronDirection.down,
              color: AppColors.white(0.4),
            ),
        ],
      ),
    );
  }

  void _addMenu() {
    final box = context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(
      Offset(box.size.width - 60, box.size.height),
    );
    final a = widget.actions!;
    final pr = _pr!;
    showContextMenu(
      context,
      position: origin,
      entries: [
        MenuEntry('Nova bancada…', () => a.onCreateBench(pr)),
        MenuEntry(
          'Nova bancada em worktree…',
          () => a.onCreateBenchFromWorktree(pr),
        ),
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 20,
        height: 20,
        child: Center(
          child: Text(
            '+',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.white(0.5),
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    ),
  );
}

/// O resumo de um grupo recolhido: quem está dentro continua se anunciando.
class _GroupStatus extends StatelessWidget {
  const _GroupStatus(this.summary);

  final ActivitySummary summary;

  @override
  Widget build(BuildContext context) {
    final animated = summary.isWorking || summary.background > 0;
    if (!animated) return _text('⠋', '⏳');
    return SpinnerBuilder(
      builder: (_, glyph) => _text(glyph, SpinnerGlyph.hourglass()),
    );
  }

  Widget _text(String glyph, String hourglass) {
    final spans = <InlineSpan>[];
    void add(String mark, int count, Color color) {
      if (count == 0) return;
      if (spans.isNotEmpty) spans.add(const TextSpan(text: ' '));
      spans.add(
        TextSpan(
          text: count > 1 ? '$mark$count' : mark,
          style: TextStyle(color: color),
        ),
      );
    }

    add(glyph, summary.working + summary.starting, AppColors.white(0.45));
    add(hourglass, summary.background, AppColors.white(0.45));
    add('●', summary.attention, AppColors.attention);
    add('●', summary.done, AppColors.done);
    if (spans.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            fontFamily: 'Menlo',
            fontSize: 11,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.none,
          ),
          children: spans,
        ),
        maxLines: 1,
      ),
    );
  }
}
