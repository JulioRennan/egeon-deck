import 'package:flutter/widgets.dart';

import '../../../../../commons/widgets/context_menu.dart';
import '../../../../../commons/widgets/hand_cursor.dart';
import '../../../../../theme/app_colors.dart';
import '../../domain/entities/queue_item.dart';
import 'queue_text_field.dart';
import 'status_dot.dart';
import 'thread_view.dart';

/// Uma tarefa da fila. Fechada é uma linha de texto com a bolinha; aberta vira
/// o editor, com os prints, o botão de mandar e a conversa embaixo — como no
/// Things, sem separar título de corpo.
class QueueRow extends StatefulWidget {
  const QueueRow({
    required this.item,
    required this.expanded,
    required this.onExpand,
    required this.onToggleDone,
    required this.onSend,
    required this.onReopen,
    required this.onRemove,
    required this.onMove,
    required this.onEdit,
    required this.onDetach,
    required this.onReply,
    required this.onCommit,
    required this.onCollapse,
    this.destinationLabel,
    super.key,
  });

  final QueueItem item;
  final bool expanded;

  /// Para quem a tarefa foi (ou vai), em nome de gente.
  final String? destinationLabel;
  final VoidCallback onExpand;
  final VoidCallback onToggleDone;
  final VoidCallback onSend;
  final VoidCallback onReopen;
  final VoidCallback onRemove;
  final ValueChanged<int> onMove;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onDetach;
  final ValueChanged<String> onReply;

  /// Enter no editor.
  final VoidCallback onCommit;
  final VoidCallback onCollapse;

  @override
  State<QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends State<QueueRow> {
  final _editorFocus = FocusNode(debugLabel: 'queue-editor');
  var _reply = '';
  var _replyKey = 0;

  @override
  void didUpdateWidget(QueueRow old) {
    super.didUpdateWidget(old);
    if (widget.expanded && !old.expanded && !widget.item.locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editorFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _editorFocus.dispose();
    super.dispose();
  }

  void _menu(Offset position) {
    final item = widget.item;
    showContextMenu(
      context,
      position: position,
      entries: [
        if (item.status == ItemStatus.pending && !item.empty)
          MenuEntry('Enviar agora', widget.onSend),
        if (item.status != ItemStatus.pending)
          MenuEntry('Reabrir', widget.onReopen),
        MenuEntry('Subir', () => widget.onMove(-1)),
        MenuEntry('Descer', () => widget.onMove(1)),
        const MenuEntry.separator(),
        MenuEntry('Remover', widget.onRemove),
      ],
    );
  }

  String get _meta {
    final item = widget.item;
    final parts = <String>[
      if (item.status == ItemStatus.sent)
        'enviada${item.sentTo == null ? '' : ' para ${widget.destinationLabel ?? item.sentTo}'}',
      if (item.status == ItemStatus.done) 'feita',
      if (item.awaiting) 'o agente perguntou',
      if (item.images.isNotEmpty)
        '${item.images.length} print${item.images.length == 1 ? '' : 's'}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (d) => _menu(d.globalPosition),
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: widget.expanded ? 6 : 0,
        ),
        padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
        decoration: widget.expanded
            ? BoxDecoration(
                color: AppColors.white(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.white(0.10)),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusDot(item: item, onTap: widget.onToggleDone),
            const SizedBox(width: 6),
            Expanded(child: widget.expanded ? _open(item) : _closed(item)),
          ],
        ),
      ),
    );
  }

  Widget _closed(QueueItem item) => HandCursor(
    child: GestureDetector(
      key: const ValueKey('queue-row'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onExpand,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.empty ? 'Nova tarefa' : item.text.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.white(
                  item.status == ItemStatus.done ? 0.4 : 0.88,
                ),
                decoration: item.status == ItemStatus.done
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                decorationColor: AppColors.white(0.4),
                fontSize: 13,
                height: 1.3,
              ),
            ),
            if (_meta.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  _meta,
                  style: TextStyle(
                    color: item.awaiting
                        ? AppColors.attention
                        : AppColors.white(0.4),
                    fontSize: 10,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _open(QueueItem item) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: QueueTextField(
          key: ValueKey('editor-${item.id}'),
          text: item.text,
          hint: 'Nova tarefa',
          // Já enviada: o texto é o registro do que foi pedido, e a conversa
          // segue pela thread.
          readOnly: item.locked,
          focusNode: _editorFocus,
          autofocus: !item.locked,
          onChanged: widget.onEdit,
          onSubmit: widget.onCommit,
          onEscape: widget.onCollapse,
        ),
      ),
      if (item.images.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final image in item.images)
                _Thumb(
                  name: image,
                  removable: !item.locked,
                  onRemove: () => widget.onDetach(image),
                ),
            ],
          ),
        ),
      if (item.thread.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: ThreadView(messages: item.thread),
        ),
      if (item.locked)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.white(0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: QueueTextField(
              key: ValueKey('reply-${item.id}-$_replyKey'),
              text: '',
              hint: item.awaiting ? 'Responder ao agente' : 'Comentar',
              fontSize: 12,
              onChanged: (text) => _reply = text,
              onSubmit: () {
                final text = _reply.trim();
                if (text.isEmpty) return;
                widget.onReply(text);
                setState(() {
                  _reply = '';
                  _replyKey++;
                });
              },
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            if (_meta.isNotEmpty)
              Text(
                _meta,
                style: TextStyle(
                  color: AppColors.white(0.4),
                  fontSize: 10,
                  decoration: TextDecoration.none,
                ),
              ),
            const Spacer(),
            if (!item.locked && !item.empty) _SendButton(onTap: widget.onSend),
          ],
        ),
      ),
    ],
  );
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HandCursor(
    child: GestureDetector(
      key: const ValueKey('send-item'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          'Enviar',
          style: TextStyle(
            color: AppColors.accent,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
  );
}

/// O print: o arquivo mora na pasta da fila, e a miniatura ainda não vem do
/// core — mostra o nome. O X tira o print da tarefa (só antes de enviar).
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.name,
    required this.removable,
    required this.onRemove,
  });

  final String name;
  final bool removable;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
    decoration: BoxDecoration(
      color: AppColors.white(0.08),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          style: TextStyle(
            color: AppColors.white(0.7),
            fontSize: 10,
            decoration: TextDecoration.none,
          ),
        ),
        if (removable)
          HandCursor(
            child: GestureDetector(
              key: ValueKey('detach-$name'),
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '✕',
                  style: TextStyle(
                    color: AppColors.white(0.6),
                    fontSize: 10,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
