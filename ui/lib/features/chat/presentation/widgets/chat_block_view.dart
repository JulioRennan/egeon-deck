import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/diff_view.dart';
import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/pressable.dart';
import '../../../../commons/widgets/eg/spinner.dart';
import '../../../../commons/widgets/eg/status.dart';
import '../../../../commons/widgets/eg/status_dot.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/chat_block.dart';
import 'chat_palette.dart';
import 'diff_rows.dart';
import 'md_text.dart';
import 'message_frame.dart';

/// O que uma linha da thread pede à tela que a hospeda.
class ChatRowActions {
  const ChatRowActions({
    required this.onToggleStep,
    required this.onCycleGroup,
    required this.onQuote,
    this.onLink,
  });

  final ValueChanged<String> onToggleStep;
  final ValueChanged<String> onCycleGroup;

  /// Clicar na citação: leva até a linha citada, pela `messageKey`.
  final ValueChanged<String> onQuote;
  final ValueChanged<String>? onLink;
}

TextStyle _mono(EgeonColors c, {double size = 12, Color? color}) =>
    EgeonType.monoMeta.copyWith(
      fontSize: size,
      height: size >= 13 ? 20 / 13 : 18 / 12,
      color: color ?? c.textMuted,
      decoration: TextDecoration.none,
    );

String _clock(DateTime at) {
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

/// Uma linha da thread, pelo tipo: a mensagem do usuário numa bolha, a do
/// agente corrida (nome, "hora · custo" e as peças: texto, passos, código,
/// diff), a citação entre agentes numa linha.
class ChatBlockView extends StatelessWidget {
  const ChatBlockView({
    required this.block,
    required this.actions,
    this.mentions = const {},
    this.groupTail = true,
    super.key,
  });

  final ChatBlock block;
  final ChatRowActions actions;

  /// Os ids dos agentes da conversa: ficam na cor deles no texto.
  final Set<String> mentions;

  /// Passo de capa aberta: é o último, o que fecha a caixa cinza do grupo.
  final bool groupTail;

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      PromptBlock() => _prompt(context, block as PromptBlock),
      HeaderBlock() => _header(context, block as HeaderBlock),
      ProseBlock(:final blocks) => _piece(
        MdColumn(blocks: blocks, onLink: actions.onLink, mentions: mentions),
      ),
      CodeBlock(:final code, :final lines) => _piece(
        CodeBox(code: code, lines: lines),
      ),
      StepBlock() => _inGroup(
        StepTile(block: block as StepBlock, onToggle: actions.onToggleStep),
      ),
      GroupBlock() => _piece(
        GroupCover(block: block as GroupBlock, onCycle: actions.onCycleGroup),
      ),
      DiffBlock() => _piece(DiffBox(block: block as DiffBlock)),
      StatusBlock(:final live) => _piece(StatusLine(live: live)),
      TypingBlock(:final from) => _piece(
        StatusLine(live: const LiveWorking(), name: from),
      ),
    };
  }

  /// Uma peça da resposta, colada ao cabeçalho com 8 e às outras com 10; o
  /// passo de uma capa entra um degrau.
  Widget _piece(Widget child) => MessageFrame(
    first: block.first,
    top: _afterHeader ? 8 : null,
    child: Padding(
      padding: EdgeInsets.only(left: block.depth * 18.0),
      child: child,
    ),
  );

  bool get _afterHeader => false;

  /// Um passo da capa aberta: mora DENTRO da caixa cinza do grupo, colado ao
  /// cabeçalho "3 passos · …" (22 por linha), recuado 34; o último fecha a
  /// caixa com o raio de baixo.
  Widget _inGroup(Widget child) => MessageFrame(
    first: false,
    top: 0,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: EgeonColors.overlay2,
        borderRadius: groupTail
            ? const BorderRadius.vertical(bottom: Radius.circular(10))
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(34, 0, 14, groupTail ? 10 : 0),
        child: child,
      ),
    ),
  );

  Widget _prompt(BuildContext context, PromptBlock b) {
    final c = context.eg;
    if (b.fromText != null) return _relay(context, b);
    final mention = b.mention ? '@${b.to.id} ' : '';
    return MessageFrame(
      first: block.first,
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Opacity(
            opacity: b.pending ? 0.6 : 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.carbon,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (b.quote != null)
                      QuoteView(
                        quote: b.quote!,
                        onTap: () => actions.onQuote(b.quote!.targetKey),
                      ),
                    Text.rich(
                      TextSpan(
                        children: [
                          if (mention.isNotEmpty)
                            TextSpan(
                              text: mention,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          TextSpan(text: b.text),
                        ],
                      ),
                      style: mdBase(c),
                    ),
                    if (block.last)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'você · ${_clock(b.at)}',
                          textAlign: TextAlign.end,
                          style: _mono(c),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// O prompt de um agente para outro: "maestro → revisor  texto  hora".
  Widget _relay(BuildContext context, PromptBlock b) {
    final c = context.eg;
    return MessageFrame(
      first: block.first,
      child: Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Row(
          children: [
            Text(
              b.fromText!,
              style: EgeonType.label.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ChatPalette.ofId(c, b.fromText!),
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(width: 10),
            EgIcon(EgIcons.arrowRight, size: 14, color: c.textMuted),
            const SizedBox(width: 10),
            Text(
              b.to.id,
              style: EgeonType.label.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ChatPalette.of(c, b.to),
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                b.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: EgeonType.small.copyWith(
                  color: c.textSecondary,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(_clock(b.at), style: _mono(c)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, HeaderBlock b) {
    final c = context.eg;
    final time = b.at == null ? 'agora' : _clock(b.at!);
    final meta = b.cost == null ? time : '$time · ${b.cost!.text}';
    return MessageFrame(
      first: block.first,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                b.from.id,
                style: EgeonType.label.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ChatPalette.of(c, b.from),
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 10),
              // A v3 põe a hora e o custo colados ao nome, sempre à vista; o
              // modelo da resposta entra aqui quando o bloco o trouxer.
              Flexible(
                child: Text(
                  meta,
                  key: const ValueKey('message-meta'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono(c),
                ),
              ),
            ],
          ),
          if (b.quote != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: QuoteView(
                quote: b.quote!,
                onTap: () => actions.onQuote(b.quote!.targetKey),
              ),
            ),
        ],
      ),
    );
  }
}

/// A mensagem que uma resposta cita (`Quote` do DS): `steel` (hover
/// `steelActive`), raio 8, 8 × 12, até 560; o autor em 12 e o texto em uma
/// linha. Clicar leva até ela.
class QuoteView extends StatelessWidget {
  const QuoteView({required this.quote, required this.onTap, super.key});

  final ChatQuote quote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final author = quote.authorId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Pressable(
            onPressed: onTap,
            semanticLabel: 'Ir à mensagem citada',
            builder: (context, s) => DecoratedBox(
              decoration: BoxDecoration(
                color: s.hovered || s.pressed ? c.steelActive : c.steel,
                borderRadius: BorderRadius.circular(EgeonRadius.md),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: EgeonSpace.s3,
                  vertical: EgeonSpace.s2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      author ?? 'você',
                      style: EgeonType.label.copyWith(
                        fontSize: 12,
                        height: 16 / 12,
                        fontWeight: FontWeight.w600,
                        color: author == null
                            ? c.textSecondary
                            : ChatPalette.ofId(c, author),
                        decoration: TextDecoration.none,
                      ),
                    ),
                    Text(
                      quote.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EgeonType.small.copyWith(
                        height: 18 / 13,
                        color: c.textSecondary,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// O título de um passo como a v3 o escreve: o verbo em `accent` ("$",
/// "criar nó", "aresta"), o resto no cinza da linha e a meta em `textMuted`
/// depois de um "·". Glifo que não é o "$" não aparece: o tofu do `⇄` na fonte
/// mono era o quadrado quebrado, e a v3 não tem ícone.
List<InlineSpan> _stepSpans(EgeonColors c, ChatStep step, bool open) {
  final accent = step.isError ? c.danger : c.accent;
  final words = step.text.split(' ');
  final shell = step.glyph == r'$';
  final verb = shell ? r'$' : words.first;
  final rest = shell ? step.text : words.skip(1).join(' ');
  return [
    TextSpan(
      text: verb,
      style: TextStyle(color: accent),
    ),
    if (rest.isNotEmpty) TextSpan(text: ' $rest'),
    if (!open && step.detail != null)
      TextSpan(
        text: ' · ${step.detail}',
        style: TextStyle(color: c.textMuted),
      ),
  ];
}

/// Um passo do agente (`Step` do DS): o glifo em `accent` e o texto em mono
/// 12/18; aberto, o comando e a saída recuados 34. Só a linha do título
/// responde ao clique — o resto é texto para ler e copiar.
class StepTile extends StatelessWidget {
  const StepTile({required this.block, required this.onToggle, super.key});

  final StepBlock block;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final step = block.step;
    final open = block.expanded && step.isExpandable;
    final title = Padding(
      key: const ValueKey('step-title'),
      // 22 por linha: 18 de texto e 2 de respiro em cima e embaixo.
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(children: _stepSpans(c, step, open)),
        style: _mono(c, color: step.isError ? c.danger : c.textSecondary),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        step.isExpandable
            ? MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onToggle(block.id),
                  child: title,
                ),
              )
            : title,
        if (open)
          Padding(
            key: const ValueKey('step-body'),
            padding: const EdgeInsets.only(left: 20, top: 4, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (step.detail != null)
                  Text(step.detail!, style: _mono(c, color: c.textSecondary)),
                if (step.output != null)
                  Padding(
                    padding: EdgeInsets.only(top: step.detail != null ? 8 : 0),
                    child: Text(step.output!, style: _mono(c)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A capa de uma sequência de passos (`StepGroup` do DS): "3 passos · o último".
/// Clicar avança o nível.
class GroupCover extends StatelessWidget {
  const GroupCover({required this.block, required this.onCycle, super.key});

  final GroupBlock block;
  final ValueChanged<String> onCycle;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final open = block.level != GroupLevel.summary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onCycle(block.id),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: EgeonColors.overlay2,
            // Aberta, a caixa continua nos passos: só o topo é arredondado.
            borderRadius: open
                ? const BorderRadius.vertical(top: Radius.circular(10))
                : BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 140),
                  child: EgIcon(
                    EgIcons.chevronRight,
                    size: 14,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${block.count} ${block.count == 1 ? 'passo' : 'passos'}',
                  style: EgeonType.label.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: c.textSecondary,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '· ${block.lastStep}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EgeonType.small.copyWith(
                      color: c.textMuted,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Um diff (`DiffView` do DS): o arquivo com `+n −n`, lado a lado, com número
/// de linha e o fundo `diff-*`.
class DiffBox extends StatelessWidget {
  const DiffBox({required this.block, super.key});

  final DiffBlock block;

  @override
  Widget build(BuildContext context) {
    final parsed = diffRowsOf(block.lines);
    return DiffView(
      filename: block.file,
      rows: parsed.rows,
      added: parsed.added,
      removed: parsed.removed,
    );
  }
}

/// A linha de status da resposta ao vivo: o spinner e o que o agente faz agora;
/// o ponto laranja que pulsa, e sem spinner, quando é ele quem espera por você.
class StatusLine extends StatelessWidget {
  const StatusLine({required this.live, this.name, super.key});

  final ChatLive live;

  /// Na resposta de "digitando" o agente ainda não tem cabeçalho.
  final ChatWho? name;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final asking = live is LiveAsking;
    final line = Row(
      children: [
        if (asking)
          const StatusDot(Status.attention, animated: true)
        else
          const Spinner(size: 12),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            live.label,
            key: const ValueKey('chat-status'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EgeonType.small.copyWith(
              color: asking ? c.attention : c.textSecondary,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ],
    );
    if (name == null) return line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          name!.id,
          style: EgeonType.label.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: ChatPalette.of(c, name!),
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 6),
        line,
      ],
    );
  }
}
