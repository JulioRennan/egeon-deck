import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/pressable.dart';
import '../../../../commons/widgets/hand_cursor.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/chat_block.dart';
import 'chat_block_view.dart';
import 'chat_scroll.dart';

/// A lista de linhas da thread, só o que está na tela. Fica no fim enquanto
/// você está no fim; ao subir para ler, não mexe; [ChatThreadViewState.jumpToEnd]
/// (cada mensagem sua) leva ao fim de onde quer que esteja; chegar ao começo
/// pede mais histórico. Subiu para ler, a setinha no canto leva de volta ao fim; clicar
/// numa linha leva à mensagem que ela cita, acesa um instante.
class ChatThreadView extends StatefulWidget {
  const ChatThreadView({
    required this.blocks,
    required this.actions,
    required this.onTop,
    this.bottomInset = 0,
    this.mentions = const {},
    super.key,
  });

  final List<ChatBlock> blocks;

  /// Os ids dos agentes da conversa, para pintar a menção no texto.
  final Set<String> mentions;
  final ChatRowActions actions;

  /// O espaço embaixo da última mensagem, para o composer flutuante não a cobrir.
  final double bottomInset;

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

  /// A setinha "ir ao fim": aparece quando você subiu para ler. Fora do
  /// estado da lista, para rolar não a remontar.
  final _away = ValueNotifier(false);

  /// A mensagem sob o ponteiro: a hora e o custo aparecem só nela.

  /// A mensagem acesa depois de chegar nela por uma citação.
  final _flash = ValueNotifier<String?>(null);
  Timer? _flashTimer;

  void _updateArrow() =>
      _away.value = widget.blocks.isNotEmpty && !scroll.isAtBottom;

  @override
  void initState() {
    super.initState();
    scroll.controller.addListener(_onScroll);
    scroll.controller.addListener(_updateArrow);
    // A primeira entrega nasce no fim, como a conversa de um mensageiro.
    _settleAtBottom();
  }

  @override
  void didUpdateWidget(ChatThreadView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = !identical(widget.blocks, oldWidget.blocks);
    if (widget.bottomInset != oldWidget.bottomInset && scroll.isAtBottom) {
      _settleAtBottom();
    }
    if (widget.blocks.length != oldWidget.blocks.length) _loadingMore = false;
    if (changed && scroll.isAtBottom) {
      // No fim: a lista cresce e continua no fim.
      _settleAtBottom();
    } else if (changed) {
      // No meio, lendo: a primeira linha visível fica onde estava.
      _holdAnchor(oldWidget.blocks);
    }
    // Linhas que saíram não precisam mais de chave.
    final ids = {for (final b in widget.blocks) b.id};
    _keys.removeWhere((id, _) => !ids.contains(id));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateArrow();
    });
  }

  /// Uma mensagem sua: a lista desce até o fim, de onde quer que esteja.
  void jumpToEnd() => _settleAtBottom();

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

  /// Leva até a linha de [messageKey] (o alvo de uma citação) e a acende um
  /// instante. A linha pode não estar montada (longe, fora da tela): salta
  /// pela altura média e afina nos quadros seguintes, até ela aparecer.
  void revealMessage(String messageKey) {
    final at = widget.blocks.indexWhere((b) => b.messageKey == messageKey);
    if (at < 0) return;
    final id = widget.blocks[at].id;
    _flashTimer?.cancel();
    _flash.value = messageKey;
    _flashTimer = Timer(const Duration(milliseconds: 900), () {
      _flash.value = null;
    });
    var rounds = 0;
    void seek() {
      if (!mounted || !scroll.controller.hasClients) return;
      final context = _keys[id]?.currentContext;
      if (context != null) {
        unawaited(
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 250),
            alignment: 0.1,
          ),
        );
        return;
      }
      final position = scroll.controller.position;
      final average =
          (position.maxScrollExtent + position.viewportDimension) /
          widget.blocks.length.clamp(1, 1 << 30);
      scroll.controller.jumpTo(
        (at * average).clamp(0.0, position.maxScrollExtent),
      );
      if (++rounds < 5) {
        WidgetsBinding.instance.addPostFrameCallback((_) => seek());
      }
    }

    seek();
  }

  /// O clique numa linha: o prompt leva ao que ele cita; a resposta, ao
  /// prompt que ela responde, como no WhatsApp.
  void _rowClicked(ChatBlock block) {
    final target = switch (block) {
      PromptBlock(:final quote) => quote?.targetKey,
      _ when block.messageKey.length > 2 =>
        'p|${block.messageKey.substring(2)}',
      _ => null,
    };
    if (target != null) revealMessage(target);
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _flash.dispose();
    _away.dispose();
    scroll.controller.removeListener(_updateArrow);
    scroll.controller.removeListener(_onScroll);
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _builds++;
    if (widget.blocks.isEmpty) return const _EmptyThread();
    return Stack(
      children: [
        NotificationListener<ScrollStartNotification>(
          // Pegar a thread na mão cancela a descida animada.
          onNotification: (n) {
            if (n.dragDetails != null) scroll.stopScrolling();
            return false;
          },
          child: ListView.builder(
            controller: scroll.controller,
            padding: EdgeInsets.only(bottom: 24 + widget.bottomInset),
            itemCount: widget.blocks.length,
            findChildIndexCallback: (key) {
              final id = (key as ValueKey<String>).value;
              final at = widget.blocks.indexWhere((b) => b.id == id);
              return at < 0 ? null : at;
            },
            itemBuilder: (context, index) {
              final block = widget.blocks[index];
              final day = dayStartingAt(widget.blocks, index);
              final row = KeyedSubtree(
                key: ValueKey(block.id),
                // A linha toda leva à mensagem citada; sobre o texto, o I-beam
                // de quem seleciona fica por cima da mão.
                child: HandCursor(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _rowClicked(block),
                    child: ValueListenableBuilder<String?>(
                      valueListenable: _flash,
                      builder: (context, flash, child) => AnimatedContainer(
                        key: _key(block.id),
                        duration: const Duration(milliseconds: 200),
                        color: flash == block.messageKey
                            ? context.eg.accentSoft
                            : EgeonColors.clear,
                        child: child,
                      ),
                      child: ChatBlockView(
                        block: block,
                        actions: widget.actions,
                        mentions: widget.mentions,
                        // O último passo de uma capa aberta fecha a caixa.
                        groupTail: !_continuesGroup(widget.blocks, index),
                      ),
                    ),
                  ),
                ),
              );
              if (day == null) return row;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DaySeparator(day: day),
                  row,
                ],
              );
            },
          ),
        ),
        Positioned(
          right: 18,
          bottom: 12 + widget.bottomInset,
          child: ValueListenableBuilder<bool>(
            valueListenable: _away,
            builder: (context, away, _) => away
                ? _ToBottom(onTap: () => scroll.scrollToBottom(animated: true))
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

/// O bloco seguinte ainda é passo da capa aberta (o recuo diz): a caixa cinza
/// do grupo continua nele.
bool _continuesGroup(List<ChatBlock> blocks, int index) {
  if (index + 1 >= blocks.length) return false;
  final next = blocks[index + 1];
  return next is StepBlock && next.depth > 0;
}

/// O instante do bloco no relógio da máquina: o core manda UTC, e o dia que
/// o usuário vê é o dele.
DateTime? _stamp(ChatBlock b) => switch (b) {
  PromptBlock(:final at) => at.toLocal(),
  HeaderBlock(:final at) => at?.toLocal(),
  _ => null,
};

/// O dia que abre aqui, se o bloco [index] é datado e o dia dele não é o do
/// último bloco datado antes dele (ou não há nenhum): é onde o separador entra.

DateTime? dayStartingAt(List<ChatBlock> blocks, int index) {
  final at = _stamp(blocks[index]);
  if (at == null) return null;
  for (var i = index - 1; i >= 0; i--) {
    final before = _stamp(blocks[i]);
    if (before == null) continue;
    final same =
        before.year == at.year &&
        before.month == at.month &&
        before.day == at.day;
    return same ? null : at;
  }
  return at;
}

/// "Hoje" (ou "Ontem", ou a data) centrado no topo da conversa, em `caption`
/// muted, como na v3.
class DaySeparator extends StatelessWidget {
  const DaySeparator({required this.day, this.now, super.key});

  final DateTime day;

  /// O instante de referência; só o teste o passa.
  final DateTime? now;

  String get label {
    final today = (now ?? DateTime.now()).toLocal();
    final local = day.toLocal();
    final days = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime(local.year, local.month, local.day)).inDays;
    if (days == 0) return 'Hoje';
    if (days == 1) return 'Ontem';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 12),
    child: Center(
      child: Text(
        label,
        key: const ValueKey('chat-day'),
        style: EgeonType.caption.copyWith(
          color: context.eg.textMuted,
          decoration: TextDecoration.none,
        ),
      ),
    ),
  );
}

/// A conversa sem nenhuma mensagem: o convite em `display`, que o DS reserva
/// aos estados vazios.
class _EmptyThread extends StatelessWidget {
  const _EmptyThread();

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Peça algo ao time',
              key: const ValueKey('chat-empty'),
              textAlign: TextAlign.center,
              style: EgeonType.display.copyWith(
                color: c.textPrimary,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Escreva embaixo. Use / para comandos e @ para mencionar.',
              textAlign: TextAlign.center,
              style: EgeonType.body.copyWith(
                color: c.textMuted,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A setinha redonda do canto: leva ao fim, com movimento.
class _ToBottom extends StatelessWidget {
  const _ToBottom({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Pressable(
      key: const ValueKey('chat-to-bottom'),
      onPressed: onTap,
      semanticLabel: 'Ir ao fim da conversa',
      builder: (context, s) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: s.hovered ? c.steel : c.carbon,
          border: Border.all(color: c.line),
          boxShadow: EgeonShadow.float,
        ),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: EgIcon(EgIcons.chevronDown, size: 16, color: c.textPrimary),
          ),
        ),
      ),
    );
  }
}
