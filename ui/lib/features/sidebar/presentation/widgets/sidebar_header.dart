import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/editable.dart';
import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/motion.dart';
import '../../../../commons/widgets/eg/pressable.dart';
import '../../../../commons/widgets/eg/status.dart';
import '../../../../commons/widgets/eg/status_dot.dart';
import '../../../../commons/widgets/eg/tooltip.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/sidebar_tab.dart';
import '../../../../commons/utils/app_shortcut.dart';

/// O cabeçalho da gaveta, numa linha só (a v3, `Sidebar`): as abas Todas N |
/// Ativas N com o sublinhado que desliza (e o ponto de atenção na Ativas
/// quando alguém espera), e à direita buscar (⌘K), filtrar, novo e recolher a
/// gaveta. Buscar troca as abas pelo campo, na mesma linha; fecha com Esc ou
/// com o ✕. Um fio embaixo, de borda a borda.
class SidebarHeader extends StatelessWidget {
  const SidebarHeader({
    required this.tab,
    required this.onTab,
    required this.allCount,
    required this.activeCount,
    required this.wantsAttention,
    required this.searching,
    required this.onToggleSearch,
    required this.query,
    required this.onQuery,
    required this.onNew,
    required this.onFilters,
    this.filterCount = 0,
    this.searchFocus,
    this.onCollapse,
    this.onAppMenu,
    super.key,
  });

  final SidebarTab tab;
  final ValueChanged<SidebarTab> onTab;
  final int allCount;
  final int activeCount;
  final bool wantsAttention;
  final bool searching;
  final VoidCallback onToggleSearch;
  final TextEditingController query;
  final ValueChanged<String> onQuery;
  final FocusNode? searchFocus;

  /// O botão de filtros: a âncora para o popover e quantos estão ligados.
  final ValueChanged<Rect> onFilters;
  final int filterCount;

  /// "Novo": a âncora do botão, para abrir o menu embaixo dele.
  final ValueChanged<Rect> onNew;

  /// Recolher a gaveta (`Recolher barra lateral`); sem ele o botão não
  /// aparece (a barra fora da gaveta).
  final VoidCallback? onCollapse;

  /// O menu ☰ do app, fora do macOS (decisão 55): a âncora do botão, para o
  /// menu abrir embaixo dele. Sem ele o botão não aparece.
  final ValueChanged<Rect>? onAppMenu;

  /// A altura da linha das abas e dos botões.
  static const tabHeight = 36.0;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final newKey = GlobalKey();
    final filterKey = GlobalKey();
    final menuKey = GlobalKey();
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.lineSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          EgeonSpace.s2,
          EgeonSpace.s2,
          10,
          EgeonSpace.s2,
        ),
        child: Row(
          children: [
            Expanded(
              child: searching
                  ? _SearchField(
                      query: query,
                      focus: searchFocus,
                      onQuery: onQuery,
                      onClose: onToggleSearch,
                    )
                  : _Tabs(
                      tab: tab,
                      onTab: onTab,
                      allCount: allCount,
                      activeCount: activeCount,
                      wantsAttention: wantsAttention,
                    ),
            ),
            const SizedBox(width: EgeonSpace.s1),
            if (!searching) ...[
              _HeaderButton(
                icon: EgIcons.search,
                tooltip: 'Buscar bancada ou projeto',
                shortcut: appShortcutLabel('K'),
                onPressed: onToggleSearch,
              ),
              const SizedBox(width: EgeonSpace.s1),
            ],
            KeyedSubtree(
              key: filterKey,
              child: _HeaderButton(
                icon: EgIcons.filter,
                tooltip: filterCount == 0
                    ? 'Filtros'
                    : filterCount == 1
                    ? 'Filtros · 1 ligado'
                    : 'Filtros · $filterCount ligados',
                selected: filterCount > 0,
                badge: filterCount > 0 ? _FilterBadge(filterCount) : null,
                onPressed: () {
                  final box =
                      filterKey.currentContext!.findRenderObject()!
                          as RenderBox;
                  onFilters(box.localToGlobal(Offset.zero) & box.size);
                },
              ),
            ),
            const SizedBox(width: EgeonSpace.s1),
            KeyedSubtree(
              key: newKey,
              child: _HeaderButton(
                icon: EgIcons.plus,
                iconSize: 14,
                tooltip: 'Novo',
                onPressed: () {
                  final box =
                      newKey.currentContext!.findRenderObject()! as RenderBox;
                  onNew(box.localToGlobal(Offset.zero) & box.size);
                },
              ),
            ),
            if (onAppMenu != null) ...[
              const SizedBox(width: EgeonSpace.s1),
              KeyedSubtree(
                key: menuKey,
                child: _HeaderButton(
                  icon: _menuIcon,
                  tooltip: 'Menu do app',
                  onPressed: () {
                    final box =
                        menuKey.currentContext!.findRenderObject()!
                            as RenderBox;
                    onAppMenu!(box.localToGlobal(Offset.zero) & box.size);
                  },
                ),
              ),
            ],
            if (onCollapse != null) ...[
              const SizedBox(width: EgeonSpace.s1),
              _HeaderButton(
                icon: EgIcons.sidebar,
                tooltip: 'Recolher barra lateral',
                onPressed: onCollapse,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Os três traços do ☰. Fica aqui e não em `EgIcons`, que espelha os nomes do
/// DS: o ☰ só existe fora do macOS.
const _menuIcon = EgIconData('menu', [EgPath('M3 4.5h10M3 8h10M3 11.5h10')]);

/// Um botão da linha (`.sb-ib`): 30, raio 8, ícone de 16 em `textSecondary`;
/// no hover `overlay6` e `textPrimary`; ligado, `accentSoft` e `accent`.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.shortcut,
    this.selected = false,
    this.iconSize = 16,
    this.badge,
  });

  final EgIconData icon;
  final String tooltip;
  final String? shortcut;
  final VoidCallback? onPressed;
  final bool selected;
  final double iconSize;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Tooltip(
      message: tooltip,
      shortcut: shortcut,
      child: Pressable(
        onPressed: onPressed,
        semanticLabel: tooltip,
        builder: (context, s) {
          final hot = s.hovered || s.pressed;
          final background = selected
              ? c.accentSoft
              : hot
              ? EgeonColors.overlay6
              : EgeonColors.clear;
          final foreground = selected
              ? c.accent
              : hot
              ? c.textPrimary
              : c.textSecondary;
          return SizedBox(
            width: 30,
            height: 30,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(EgeonRadius.md),
                      border: Border.all(
                        color: s.focused ? c.accent : EgeonColors.clear,
                        width: EgeonBorder.focus,
                      ),
                    ),
                    child: Center(
                      child: EgIcon(icon, size: iconSize, color: foreground),
                    ),
                  ),
                ),
                if (badge != null)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: IgnorePointer(child: badge!),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// As duas abas (`.tab`): 92 × 36, texto 13 w500 em `textSecondary` (hover
/// `textPrimary`, ligada `accent`), a contagem em mono 11, e embaixo o
/// sublinhado de 64 × 2 que desliza de uma para a outra.
class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.tab,
    required this.onTab,
    required this.allCount,
    required this.activeCount,
    required this.wantsAttention,
  });

  final SidebarTab tab;
  final ValueChanged<SidebarTab> onTab;
  final int allCount;
  final int activeCount;
  final bool wantsAttention;

  static const tabWidth = 92.0;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Semantics(
      container: true,
      label: 'Visão das bancadas',
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: tabWidth * 2,
            height: SidebarHeader.tabHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Sobre o fio de baixo do cabeçalho (8 de respiro + 1 de fio).
                AnimatedPositioned(
                  key: const ValueKey('tab-indicator'),
                  duration: egDuration(context, EgeonMotion.base),
                  curve: EgeonMotion.easeStandard,
                  left: 14 + (tab == SidebarTab.active ? tabWidth : 0),
                  top: SidebarHeader.tabHeight + 7,
                  width: 64,
                  height: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    _Tab(
                      key: const ValueKey('tab-all'),
                      label: 'Todas',
                      count: allCount,
                      selected: tab == SidebarTab.all,
                      onPressed: () => onTab(SidebarTab.all),
                    ),
                    _Tab(
                      key: const ValueKey('tab-active'),
                      label: 'Ativas',
                      count: activeCount,
                      selected: tab == SidebarTab.active,
                      attention: wantsAttention,
                      onPressed: () => onTab(SidebarTab.active),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onPressed,
    this.attention = false,
    super.key,
  });

  final String label;
  final int count;
  final bool selected;
  final bool attention;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Semantics(
      selected: selected,
      child: Pressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, s) {
          final color = selected
              ? c.accent
              : s.hovered
              ? c.textPrimary
              : c.textSecondary;
          return SizedBox(
            width: _Tabs.tabWidth,
            height: SidebarHeader.tabHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: EgeonType.small.copyWith(
                            fontWeight: FontWeight.w500,
                            color: color,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$count',
                          style: EgeonType.monoMeta.copyWith(
                            fontSize: 11,
                            color: c.textMuted,
                            fontWeight: FontWeight.w400,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (attention)
                  const Positioned(
                    top: 7,
                    right: 8,
                    child: StatusDot(
                      Status.attention,
                      size: StatusDotSize.sm,
                      animated: true,
                      label: 'Alguma precisa de você',
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// O campo de busca no lugar das abas (`.sq`): 32, raio 8, fundo `overlay4`,
/// lupa à esquerda e ✕ à direita; o foco ganha borda `accent`.
class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.query,
    required this.onQuery,
    required this.onClose,
    this.focus,
  });

  final TextEditingController query;
  final ValueChanged<String> onQuery;
  final VoidCallback onClose;
  final FocusNode? focus;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  FocusNode? _own;
  bool _hovered = false;

  FocusNode get _focus => widget.focus ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_refresh);
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final style = EgeonType.small.copyWith(
      color: c.textPrimary,
      decoration: TextDecoration.none,
    );
    return Semantics(
      label: 'Buscar bancada ou projeto',
      textField: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: SizedBox(
          height: 32,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _hovered ? EgeonColors.overlay6 : EgeonColors.overlay4,
              borderRadius: BorderRadius.circular(EgeonRadius.md),
              border: Border.all(
                color: _focus.hasFocus ? c.accent : EgeonColors.clear,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 10),
                EgIcon(EgIcons.search, color: c.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  // Esc fecha só a busca: o evento não sobe até a gaveta.
                  child: Focus(
                    canRequestFocus: false,
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.escape) {
                        widget.onClose();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        ListenableBuilder(
                          listenable: widget.query,
                          builder: (context, _) => widget.query.text.isEmpty
                              ? IgnorePointer(
                                  child: Text(
                                    'Buscar bancada ou projeto',
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: style.copyWith(color: c.textMuted),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        Editable(
                          controller: widget.query,
                          focusNode: _focus,
                          style: style,
                          cursorColor: c.accent,
                          selectionColor: c.accentSoft,
                          onChanged: widget.onQuery,
                        ),
                      ],
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Fechar a busca',
                  shortcut: 'Esc',
                  child: Pressable(
                    onPressed: widget.onClose,
                    semanticLabel: 'Fechar a busca',
                    builder: (context, s) => SizedBox(
                      width: 28,
                      height: 28,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: s.hovered || s.pressed
                              ? EgeonColors.overlay6
                              : EgeonColors.clear,
                          borderRadius: BorderRadius.circular(EgeonRadius.sm),
                        ),
                        child: Center(
                          child: EgIcon(
                            EgIcons.x,
                            size: 14,
                            color: s.hovered || s.pressed
                                ? c.textPrimary
                                : c.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// O selo de filtros ligados: 14, `accent`, número em mono 10 w600.
class _FilterBadge extends StatelessWidget {
  const _FilterBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: SizedBox(
        height: 14,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 14),
          child: Center(
            widthFactor: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(
                '$count',
                style: EgeonType.monoMeta.copyWith(
                  color: c.obsidian,
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
    );
  }
}
