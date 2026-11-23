import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'eg_icon.dart';
import 'identity.dart';
import 'kbd.dart';
import 'layer.dart';
import 'popover.dart';
import 'pressable.dart';

/// Uma linha do menu: [MenuItem], [MenuSeparator] ou [MenuHeader].
sealed class MenuElement {
  const MenuElement();
}

class MenuItem extends MenuElement {
  const MenuItem(
    this.label, {
    this.onSelected,
    this.icon,
    this.leading,
    this.shortcut,
    this.desc,
    this.checked,
    this.submenu = false,
    this.identity,
    this.danger = false,
  });

  final String label;

  /// Nulo desabilita a linha.
  final VoidCallback? onSelected;
  final EgIconData? icon;

  /// Marca à esquerda no lugar do ícone (a bolinha de cor da bancada…).
  final Widget? leading;

  /// À direita, em chip (ex.: `⌘N`).
  final String? shortcut;

  /// Texto de apoio à direita do rótulo, em `textMuted`.
  final String? desc;

  /// Não nulo reserva a coluna de check (14) do menu inteiro; `true` marca.
  final bool? checked;

  /// Abre outro menu: chevron à direita.
  final bool submenu;

  /// Escreve o rótulo na cor da identidade (agente, bancada).
  final Identity? identity;

  /// Ação destrutiva: texto `danger`, hover `dangerSoft`.
  final bool danger;
}

class MenuSeparator extends MenuElement {
  const MenuSeparator();
}

/// Título de grupo: `caption` em `textMuted`.
class MenuHeader extends MenuElement {
  const MenuHeader(this.title);

  final String title;
}

/// Abre um menu ancorado em [anchor] (ver [showPopover]). Escolher uma linha
/// fecha o menu e chama `onSelected`; setas movem o foco entre as linhas.
Layer showMenu(
  BuildContext context, {
  required Rect anchor,
  required List<MenuElement> items,
  PopoverPlacement placement = PopoverPlacement.bottomStart,
  double width = 224,
  VoidCallback? onClosed,
}) {
  return showPopover(
    context,
    anchor: anchor,
    placement: placement,
    padding: const EdgeInsets.all(6),
    width: width,
    onClosed: onClosed,
    builder: (context, close) => Menu(items: items, onSelected: close),
  );
}

/// A lista do menu: linhas de 32, separador de 1px, atalho à direita.
class Menu extends StatelessWidget {
  const Menu({required this.items, this.onSelected, super.key});

  final List<MenuElement> items;

  /// Chamado ao escolher uma linha (o menu aberto por [showMenu] fecha aqui).
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final scope = FocusScope.of(context);
    final hasCheck = items.any((i) => i is MenuItem && i.checked != null);
    var first = true;
    final children = <Widget>[];
    for (final item in items) {
      switch (item) {
        case MenuSeparator():
          children.add(const _Separator());
        case MenuHeader(:final title):
          children.add(_Header(title));
        case MenuItem():
          children.add(
            _Row(
              item: item,
              hasCheck: hasCheck,
              autofocus: first && item.onSelected != null,
              onSelected: onSelected,
            ),
          );
          if (item.onSelected != null) first = false;
      }
    }
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
      },
      child: Actions(
        actions: {
          NextFocusIntent: CallbackAction<NextFocusIntent>(
            onInvoke: (_) => scope.nextFocus(),
          ),
          PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
            onInvoke: (_) => scope.previousFocus(),
          ),
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  /// O fio vai de borda a borda do menu (margem de 6 em cima e embaixo, e -6
  /// dos lados, que anula o respiro do menu): é pintado para fora da caixa.
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 12 + EgeonBorder.hairline,
    width: double.infinity,
    child: CustomPaint(painter: _LinePainter(context.eg.line)),
  );
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(-6, 6, size.width + 12, EgeonBorder.hairline),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.color != color;
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      EgeonSpace.s2,
      6,
      EgeonSpace.s2,
      EgeonSpace.s1,
    ),
    child: Text(
      title,
      style: EgeonType.caption.copyWith(
        letterSpacing: 0,
        color: context.eg.textMuted,
        decoration: TextDecoration.none,
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.hasCheck,
    required this.autofocus,
    required this.onSelected,
  });

  final MenuItem item;
  final bool hasCheck;
  final bool autofocus;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final action = item.onSelected;
    return Pressable(
      autofocus: autofocus,
      showsFocus: true,
      semanticLabel: item.label,
      onPressed: action == null
          ? null
          : () {
              onSelected?.call();
              action();
            },
      builder: (context, s) {
        final active = s.hovered || s.focused;
        final background = s.pressed || active
            ? (item.danger ? c.dangerSoft : c.steelActive)
            : EgeonColors.clear;
        final foreground = !s.enabled
            ? c.textDisabled
            : item.danger
            ? c.danger
            : c.textPrimary;
        final style = EgeonType.small.copyWith(
          color: foreground,
          decoration: TextDecoration.none,
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(EgeonRadius.sm),
          ),
          child: SizedBox(
            height: EgeonSize.row,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  if (hasCheck) ...[
                    SizedBox(
                      width: 16,
                      child: item.checked == true
                          ? EgIcon(
                              EgIcons.check,
                              size: EgeonSize.iconSm,
                              color: s.enabled ? c.accent : c.textDisabled,
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (item.leading != null) ...[
                    item.leading!,
                    const SizedBox(width: 10),
                  ] else if (item.icon != null) ...[
                    EgIcon(
                      item.icon!,
                      color: !s.enabled
                          ? c.textDisabled
                          : item.danger
                          ? c.danger
                          : active
                          ? c.textSecondary
                          : c.textMuted,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      item.label,
                      style: item.identity == null
                          ? style
                          : style.copyWith(
                              color: s.enabled
                                  ? identityColor(c, item.identity)
                                  : c.textDisabled,
                              fontWeight: FontWeight.w600,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (item.desc != null) ...[
                    const SizedBox(width: EgeonSpace.s3),
                    Text(
                      item.desc!,
                      style: EgeonType.caption.copyWith(
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                        color: c.textMuted,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                  if (item.shortcut != null) ...[
                    const SizedBox(width: EgeonSpace.s4),
                    Kbd(item.shortcut!),
                  ],
                  if (item.submenu) ...[
                    const SizedBox(width: EgeonSpace.s2),
                    EgIcon(
                      EgIcons.chevronRight,
                      size: EgeonSize.iconSm,
                      color: c.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
