import 'package:flutter/widgets.dart';

import '../../domain/entities/chat_block.dart';
import 'chat_block_view.dart';
import 'chat_scroll.dart';

/// A lista de linhas da thread, só o que está na tela. Fica no fim enquanto
/// você está no fim; ao subir para ler, não mexe; [sends] sobe a cada mensagem
/// sua e leva ao fim de onde quer que esteja; chegar ao começo pede mais
/// histórico.
class ChatThreadView extends StatefulWidget {
  const ChatThreadView({
    required this.blocks,
    required this.actions,
    required this.sends,
    required this.onTop,
    super.key,
  });

  final List<ChatBlock> blocks;
  final ChatRowActions actions;
  final int sends;

  /// O começo da lista foi alcançado: a janela de histórico pode crescer. Se
  /// o pedido falhar, a lista pode pedir de novo.
  final Future<void> Function() onTop;

  @override
  State<ChatThreadView> createState() => ChatThreadViewState();
}

class ChatThreadViewState extends State<ChatThreadView> {
  final scroll = ChatScroll();
  final _keys = <String, GlobalKey>{};
  var _builds = 0;

  /// Quantas vezes a lista foi montada: o composer crescer não a remonta.
  int get builds => _builds;

  GlobalKey _key(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    scroll.controller.addListener(_onScroll);
    // A primeira entrega nasce no fim, como a conversa de um mensageiro.
    _settleAtBottom();
  }

  @override
  void didUpdateWidget(ChatThreadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = !identical(widget.blocks, oldWidget.blocks);
    if (widget.blocks.length != oldWidget.blocks.length) _loadingMore = false;
    if (widget.sends != oldWidget.sends) {
      _settleAtBottom();
    } else if (changed && scroll.isAtBottom) {
      // No fim: a lista cresce e continua no fim.
      _settleAtBottom();
    } else if (changed) {
      // No meio, lendo: a primeira linha visível fica onde estava.
      _holdAnchor(oldWidget.blocks);
    }
    // Linhas que saíram não precisam mais de chave.
    final ids = {for (final b in widget.blocks) b.id};
    _keys.removeWhere((id, _) => !ids.contains(id));
  }

  /// Desce depois do quadro em que a lista cresce, e de novo no seguinte, porque
  /// linhas fora da tela ganham altura ao entrar.
  void _settleAtBottom() {
    var rounds = 0;
    void step() {
      if (!mounted) return;
      if (!scroll.isAtVeryBottom) scroll.scrollToBottom();
      if (++rounds < 3) {
        WidgetsBinding.instance.addPostFrameCallback((_) => step());
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => step());
  }

  /// O topo de uma linha, em relação ao topo da área visível; `null` se ela não
  /// está montada.
  double? _topOf(String id) {
    final box = _keys[id]?.currentContext?.findRenderObject() as RenderBox?;
    final viewport = scroll.controller.hasClients
        ? scroll.controller.position.context.storageContext.findRenderObject()
              as RenderBox?
        : null;
    if (box == null || !box.attached || viewport == null) return null;
    return box.localToGlobal(Offset.zero, ancestor: viewport).dy;
  }

  /// Guarda a primeira linha visível (id e deslocamento) e a devolve ao mesmo
  /// ponto depois da atualização: carregar histórico por cima não pode tirar
  /// do lugar quem está lendo.
  void _holdAnchor(List<ChatBlock> before) {
    String? anchor;
    double? offset;
    var index = 0;
    for (final (i, block) in before.indexed) {
      final top = _topOf(block.id);
      // O tamanho vem do render object do quadro anterior: o `size` do elemento
      // não pode ser lido enquanto se constrói.
      final box = _keys[block.id]?.currentContext?.findRenderObject();
      final height = box is RenderBox && box.hasSize ? box.size.height : 0.0;
      if (top != null && top + height > 0) {
        anchor = block.id;
        offset = top;
        index = i;
        break;
      }
    }
    if (anchor == null || offset == null) return;
    final id = anchor;
    final wanted = offset;
    var rounds = 0;
    void restore() {
      if (!mounted || !scroll.controller.hasClients) return;
      final position = scroll.controller.position;
      final at = widget.blocks.indexWhere((b) => b.id == id);
      if (at < 0) return;
      final top = _topOf(id);
      double target;
      if (top != null) {
        target = position.pixels + (top - wanted);
      } else {
        // A linha ainda não foi montada (veio de longe, empurrada por cima):
        // estima pela altura média e deixa o quadro seguinte afinar.
        final average =
            (position.maxScrollExtent + position.viewportDimension) /
            widget.blocks.length.clamp(1, 1 << 30);
        target = position.pixels + (at - index) * average;
      }
      target = target.clamp(0.0, position.maxScrollExtent);
      final moved = (target - position.pixels).abs() > 0.5;
      if (moved) scroll.controller.jumpTo(target);
      if ((moved || top == null) && ++rounds < 5) {
        WidgetsBinding.instance.addPostFrameCallback((_) => restore());
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => restore());
  }

  /// Já pediu mais histórico e a lista ainda não cresceu.
  var _loadingMore = false;

  /// Perto do topo (a menos de 300 pt), sem descida animada e sem carga em
  /// curso: pede mais histórico uma vez só.
  void _onScroll() {
    if (!scroll.controller.hasClients) return;
    final nearTop = scroll.controller.position.pixels < 300;
    if (!nearTop || scroll.scrollingToBottom || _loadingMore) return;
    if (widget.blocks.isEmpty) return;
    _loadingMore = true;
    // Falhou: libera o próximo pedido em vez de esperar a lista mudar.
    widget.onTop().catchError((Object _) {
      if (mounted) _loadingMore = false;
    });
  }

  /// Leva até a linha de [messageKey] (o alvo de uma citação).
  void revealMessage(String messageKey) {
    final target = widget.blocks.where((b) => b.messageKey == messageKey);
    if (target.isEmpty) return;
    final context = _keys[target.first.id]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 250),
      alignment: 0.1,
    );
  }

  @override
  void dispose() {
    scroll.controller.removeListener(_onScroll);
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _builds++;
    return NotificationListener<ScrollStartNotification>(
      // Pegar a thread na mão cancela a descida animada.
      onNotification: (n) {
        if (n.dragDetails != null) scroll.stopScrolling();
        return false;
      },
      child: ListView.builder(
        controller: scroll.controller,
        padding: const EdgeInsets.only(top: 18),
        itemCount: widget.blocks.length,
        findChildIndexCallback: (key) {
          final id = (key as ValueKey<String>).value;
          final at = widget.blocks.indexWhere((b) => b.id == id);
          return at < 0 ? null : at;
        },
        itemBuilder: (context, index) {
          final block = widget.blocks[index];
          return KeyedSubtree(
            key: ValueKey(block.id),
            child: Container(
              key: _key(block.id),
              child: ChatBlockView(block: block, actions: widget.actions),
            ),
          );
        },
      ),
    );
  }
}
