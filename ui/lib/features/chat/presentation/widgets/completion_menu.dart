import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/hand_cursor.dart';
import '../../domain/entities/chat_completion.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_type.dart';

/// O menu de @menção e /slash acima da caixa de mensagem, com um título que diz
/// o que é. A linha escolhida (setas) vai com Enter ou Tab e fica sempre à
/// vista; o clique também escolhe.
class CompletionMenu extends StatefulWidget {
  const CompletionMenu({
    required this.items,
    required this.selected,
    required this.onPick,
    this.targetName,
    super.key,
  });

  final List<CompletionItem> items;
  final int selected;
  final ValueChanged<CompletionItem> onPick;

  /// De quem são os /comandos: vai no título.
  final String? targetName;

  static const rowHeight = 34.0;

  /// Quantas linhas a lista de comandos mostra de uma vez; o resto rola.
  static const slashRows = 10;

  @override
  State<CompletionMenu> createState() => _CompletionMenuState();
}

class _CompletionMenuState extends State<CompletionMenu> {
  final _scroll = ScrollController();

  bool get _slash => widget.items.any((i) => i.isSlash);

  int get _rows => _slash
      ? math.min(widget.items.length, CompletionMenu.slashRows)
      : widget.items.length;

  @override
  void didUpdateWidget(CompletionMenu old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _follow();
  }

  /// Setas além da janela: a lista rola o mínimo para a escolhida aparecer.
  void _follow() {
    if (!_scroll.hasClients) return;
    const h = CompletionMenu.rowHeight;
    final top = widget.selected * h;
    final view = _rows * h;
    final at = _scroll.offset;
    if (top < at) {
      _scroll.jumpTo(top);
    } else if (top + h > at + view) {
      _scroll.jumpTo(top + h - view);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String get _title {
    if (!_slash) return 'MENCIONAR — o nome entra no prompt';
    final count = widget.items.length;
    final more = count > CompletionMenu.slashRows
        ? ' · $count, role ou busque'
        : '';
    final who = (widget.targetName ?? '').toUpperCase();
    return 'COMANDOS DE $who — Tab ou Enter completa$more';
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // A lista de comandos traz a descrição: na largura da menção ela não
      // passava de três palavras.
      final width = _slash
          ? math.min(620.0, box.maxWidth - 20)
          : math.min(320.0, box.maxWidth);
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          key: const ValueKey('completion-menu'),
          width: width,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          decoration: BoxDecoration(
            color: context.eg.carbon,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.eg.lineStrong),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                child: Text(
                  _title,
                  key: const ValueKey('completion-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EgeonType.caption.copyWith(
                    fontWeight: FontWeight.w500,
                    color: context.eg.textMuted,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              SizedBox(
                height: _rows * CompletionMenu.rowHeight,
                child: ListView.builder(
                  controller: _scroll,
                  itemExtent: CompletionMenu.rowHeight,
                  itemCount: widget.items.length,
                  itemBuilder: (context, i) => _row(i, widget.items[i]),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _row(int i, CompletionItem item) {
    final (glyph, color) = _glyph(context.eg, item.kind);
    return HandCursor(
      child: GestureDetector(
        key: ValueKey('completion-$i'),
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onPick(item),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: i == widget.selected ? context.eg.accentSoft : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  glyph,
                  style: TextStyle(
                    fontSize: 13,
                    color: color,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                item.label,
                style: EgeonType.small.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.eg.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 10),
              if (item.detail case final detail?)
                Expanded(
                  child: Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EgeonType.caption.copyWith(
                      color: context.eg.textMuted,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// O glifo diz de onde vem o comando, como na lista do Swift.
  static (String, Color) _glyph(EgeonColors c, String kind) => switch (kind) {
    'agent' => ('✦', c.accent),
    'builtin' => ('/', c.textSecondary),
    'bundled' => ('✦', c.attention),
    'user' => ('★', c.idSand),
    'project' => ('◆', c.idSky),
    _ => ('⬢', c.idOrchid),
  };
}
