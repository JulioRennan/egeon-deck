import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../../../../commons/widgets/context_menu.dart';
import '../../../../../commons/widgets/hand_cursor.dart';
import '../../../../../commons/widgets/pasted_image.dart';
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
    required this.onOpenImage,
    required this.onReply,
    required this.onCommit,
    required this.onCollapse,
    required this.onPaste,
    this.destinationLabel,
    this.imagesDir = '',
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

  /// O clique na miniatura abre o print.
  final ValueChanged<String> onOpenImage;

  /// A pasta dos prints, de onde a miniatura se lê.
  final String imagesDir;
  final ValueChanged<String> onReply;

  /// Enter no editor.
  final VoidCallback onCommit;
  final VoidCallback onCollapse;

  /// ⌘V no editor ou na resposta: o print vai para esta tarefa. Devolve se
  /// havia imagem que servisse.
  final bool Function(PastedClipboard pasted) onPaste;

  @override
  State<QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends State<QueueRow> {
  final _editorFocus = FocusNode(debugLabel: 'queue-editor');
  final _replyFocus = FocusNode(debugLabel: 'queue-reply');
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
    _replyFocus.dispose();
    super.dispose();
  }

  /// Aberta, o clique em qualquer parte do cartão é escrever, nunca fechar:
  /// a tarefa, ou a resposta quando ela já foi enviada.
  void _focusEditor() =>
      (widget.item.locked ? _replyFocus : _editorFocus).requestFocus();

  void _menu(Offset position) {
    final item = widget.item;
    showContextMenu(
      context,
      position: position,
      // Tarefa travada (já enviada) não volta nem vai de novo; e a que está
      // com o agente não se apaga por aqui.
      entries: [
        if (!item.locked) ...[
          if (item.status == ItemStatus.pending)
            MenuEntry('Enviar agora', widget.onSend)
          else
            MenuEntry('Voltar para pendente', widget.onReopen),
          const MenuEntry.separator(),
        ],
        MenuEntry('Mover para cima', () => widget.onMove(-1)),
        MenuEntry('Mover para baixo', () => widget.onMove(1)),
        if (item.status != ItemStatus.sent) ...[
          const MenuEntry.separator(),
          MenuEntry('Apagar', widget.onRemove),
        ],
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
      // No `mouseDown`, como o Swift; e sem mão, que ali o clique é escrever.
      // Ter o toque aqui é o que impede o vazio da lista de fechar a tarefa.
      onTapDown: widget.expanded ? (_) => _focusEditor() : null,
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
          onPasteImage: widget.onPaste,
        ),
      ),
      if (item.images.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final image in item.images)
                _Thumb(
                  name: image,
                  path: '${widget.imagesDir}/$image',
                  removable: !item.locked,
                  onOpen: () => widget.onOpenImage(image),
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
      // Pendente também: o comentário vai junto quando a tarefa for enviada.
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
            hint: item.awaiting
                ? 'Responder a pergunta…'
                : item.sentTo != null
                ? 'Responder ao ${item.sentTo}…'
                : 'Comentar — vai junto quando enviar',
            fontSize: 12,
            focusNode: _replyFocus,
            onChanged: (text) => _reply = text,
            onPasteImage: widget.onPaste,
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

/// O print, na altura padrão e na largura da proporção dele; o clique o abre.
/// O X no canto tira o print da tarefa (só antes de enviar). Arquivo que
/// sumiu da pasta mostra o nome no lugar.
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.name,
    required this.path,
    required this.removable,
    required this.onOpen,
    required this.onRemove,
  });

  final String name;
  final String path;
  final bool removable;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  static const height = 200.0;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      HandCursor(
        child: GestureDetector(
          key: ValueKey('thumb-$name'),
          behavior: HitTestBehavior.opaque,
          onTap: onOpen,
          child: Container(
            // Antes de a imagem carregar ela não tem largura: o mínimo deixa
            // o X do canto dentro da caixa, onde o clique chega.
            constraints: const BoxConstraints(
              minWidth: 64,
              minHeight: 38,
              maxHeight: height,
            ),
            clipBehavior: Clip.antiAlias,
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.white(0.14)),
            ),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
            child: Image.file(
              File(path),
              height: height,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _name(),
            ),
          ),
        ),
      ),
      if (removable)
        Positioned(
          top: 6,
          right: 6,
          child: HandCursor(
            child: GestureDetector(
              key: ValueKey('detach-$name'),
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xB3000000),
                ),
                child: const Text(
                  '✕',
                  style: TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 12,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );

  // Alto o bastante para o X do canto caber dentro (e receber o clique).
  Widget _name() => Container(
    height: 38,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.fromLTRB(8, 0, 40, 0),
    color: AppColors.white(0.08),
    child: Text(
      name,
      style: TextStyle(
        color: AppColors.white(0.7),
        fontSize: 10,
        decoration: TextDecoration.none,
      ),
    ),
  );
}
