import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/spinner.dart';
import '../../../../theme/app_colors.dart';
import '../../domain/entities/chat_block.dart';
import 'chat_bubble.dart';
import 'chat_palette.dart';
import 'md_text.dart';

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

/// Uma linha da thread, pelo tipo.
class ChatBlockView extends StatelessWidget {
  const ChatBlockView({required this.block, required this.actions, super.key});

  final ChatBlock block;
  final ChatRowActions actions;

  static const _time = TextStyle(
    fontSize: 10.5,
    color: Color(0xFF737373),
    decoration: TextDecoration.none,
  );

  @override
  Widget build(BuildContext context) => switch (block) {
    PromptBlock() => _prompt(block as PromptBlock),
    HeaderBlock() => _header(block as HeaderBlock),
    ProseBlock(:final blocks, :final from) => _agent(
      from,
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: MdColumn(blocks: blocks, onLink: actions.onLink),
      ),
    ),
    CodeBlock(:final code, :final from, :final lines) => _agent(
      from,
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CodeBox(code: code, lines: lines),
      ),
    ),
    StepBlock() => _agent(
      (block as StepBlock).from,
      _boxed(
        StepTile(block: block as StepBlock, onToggle: actions.onToggleStep),
      ),
    ),
    GroupBlock() => _agent(
      (block as GroupBlock).from,
      _boxed(
        GroupCover(block: block as GroupBlock, onCycle: actions.onCycleGroup),
      ),
    ),
    DiffBlock() => _agent(
      (block as DiffBlock).from,
      _boxed(DiffBox(block: block as DiffBlock)),
    ),
    StatusBlock(:final from, :final live) => _agent(
      from,
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: StatusLine(live: live),
      ),
    ),
    TypingBlock(:final from) => _agent(
      from,
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: StatusLine(live: const LiveWorking(), name: from),
      ),
    ),
  };

  /// A caixa de um passo, de um diff ou de uma capa: recuada pela profundidade.
  Widget _boxed(Widget child) => Padding(
    padding: EdgeInsets.only(
      top: block.depth > 0 ? 6 : 12,
      left: block.depth * 18.0,
    ),
    child: child,
  );

  Widget _agent(ChatWho from, Widget child) => ChatBubble(
    first: block.first,
    last: block.last,
    accent: ChatPalette.of(from),
    child: child,
  );

  Widget _prompt(PromptBlock b) {
    final you = b.fromText == null;
    final mention = b.mention ? '@${b.to.id} ' : '';
    return ChatBubble(
      first: block.first,
      last: block.last,
      you: you,
      maxWidth: ChatBubble.promptMaxWidth,
      dimmed: b.pending,
      accent: you ? null : ChatPalette.of(b.to),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (b.fromText != null)
            Text(
              '✦ ${b.fromText}',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.white(0.55),
                decoration: TextDecoration.none,
              ),
            ),
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
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                TextSpan(text: b.text),
              ],
            ),
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.35,
              color: Color(0xFFFFFFFF),
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(HeaderBlock b) {
    final time = b.at == null ? 'agora' : _clock(b.at!);
    final label = b.cost == null ? time : '${b.cost!.text} · $time';
    return ChatBubble(
      first: block.first,
      last: block.last,
      accent: ChatPalette.of(b.from),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '✦ ${b.from.id}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ChatPalette.of(b.from),
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                b.from.address,
                style: const TextStyle(
                  fontFamily: 'Menlo',
                  fontSize: 10.5,
                  color: Color(0xFF737373),
                  decoration: TextDecoration.none,
                ),
              ),
              const Spacer(),
              Text(label, style: _time),
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

  static String _clock(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }
}

/// A mensagem que uma resposta cita; clicar leva até ela.
class QuoteView extends StatelessWidget {
  const QuoteView({required this.quote, required this.onTap, super.key});

  final ChatQuote quote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final author = quote.authorId;
    final color = author == null
        ? const Color(0xFF2F7FF6)
        : ChatPalette.of(ChatWho(id: author, address: author, isAgent: true));
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          decoration: BoxDecoration(
            color: AppColors.black(0.2),
            borderRadius: BorderRadius.circular(6),
            border: Border(left: BorderSide(color: color, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                author == null ? 'você' : '✦ $author',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  decoration: TextDecoration.none,
                ),
              ),
              Text(
                quote.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.white(0.7),
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A caixa de um passo. Recolhido é só o título; aberto, o comando e a saída.
/// Só a faixa do título responde ao clique — o resto é texto para ler e copiar.
class StepTile extends StatefulWidget {
  const StepTile({required this.block, required this.onToggle, super.key});

  final StepBlock block;
  final ValueChanged<String> onToggle;

  @override
  State<StepTile> createState() => _StepTileState();
}

class _StepTileState extends State<StepTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final step = widget.block.step;
    final open = widget.block.expanded && step.isExpandable;
    final title = Text(
      '${step.glyph} ${step.text}',
      style: TextStyle(
        fontFamily: 'Menlo',
        fontSize: 12,
        height: 1.3,
        color: step.isError ? const Color(0xFFFF6B6B) : AppColors.white(0.85),
        decoration: TextDecoration.none,
      ),
    );
    final strip = Container(
      key: const ValueKey('step-title'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: open || _hovering
          ? (_hovering ? ChatPalette.titleHover : ChatPalette.titleFill)
          : null,
      child: title,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ChatPalette.boxFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ChatPalette.boxBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            step.isExpandable
                ? MouseRegion(
                    cursor: SystemMouseCursors.click,
                    onEnter: (_) => setState(() => _hovering = true),
                    onExit: (_) => setState(() => _hovering = false),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onToggle(widget.block.id),
                      child: strip,
                    ),
                  )
                : strip,
            if (open)
              Container(
                key: const ValueKey('step-body'),
                color: ChatPalette.contentFill,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (step.detail != null) _mono(step.detail!, 0.85),
                    if (step.output != null)
                      Padding(
                        padding: EdgeInsets.only(
                          top: step.detail != null ? 8 : 0,
                        ),
                        child: _mono(step.output!, 0.6),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mono(String text, double alpha) => Text(
    text,
    style: TextStyle(
      fontFamily: 'Menlo',
      fontSize: 11.5,
      height: 1.35,
      color: AppColors.white(alpha),
      decoration: TextDecoration.none,
    ),
  );
}

/// A capa de uma sequência de passos: "3 passos · echo três". Clicar avança o
/// nível.
class GroupCover extends StatelessWidget {
  const GroupCover({required this.block, required this.onCycle, super.key});

  final GroupBlock block;
  final ValueChanged<String> onCycle;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onCycle(block.id),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ChatPalette.boxFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ChatPalette.boxBorder),
        ),
        child: Text(
          '${block.count} ${block.count == 1 ? 'passo' : 'passos'} · '
          '${block.lastStep}',
          style: TextStyle(
            fontFamily: 'Menlo',
            fontSize: 12,
            color: AppColors.white(0.7),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
  );
}

/// Um diff: o arquivo em cima e as linhas coloridas — verde entra, vermelho
/// sai, azul é a posição.
class DiffBox extends StatelessWidget {
  const DiffBox({required this.block, super.key});

  final DiffBlock block;

  static Color colorOf(String line) {
    if (line.startsWith('@@')) return const Color(0xFF6EA8FF);
    if (line.startsWith('+')) return const Color(0xFF6CCB7A);
    if (line.startsWith('-')) return const Color(0xFFFF7B7B);
    return const Color(0xFFBFBFBF);
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: ChatPalette.boxFill,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: ChatPalette.boxBorder),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: ChatPalette.titleFill,
            child: Text(
              '± ${block.file}',
              style: TextStyle(
                fontFamily: 'Menlo',
                fontSize: 12,
                color: AppColors.white(0.85),
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: ChatPalette.contentFill,
            child: Text.rich(
              TextSpan(
                children: [
                  for (final (i, line) in block.lines.indexed)
                    TextSpan(
                      text: i == block.lines.length - 1 ? line : '$line\n',
                      style: TextStyle(color: colorOf(line)),
                    ),
                ],
              ),
              style: const TextStyle(
                fontFamily: 'Menlo',
                fontSize: 11.5,
                height: 1.35,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A linha de status da bolha ao vivo: o spinner e o que o agente faz agora; em
/// laranja e sem spinner quando é ele quem espera por você.
class StatusLine extends StatelessWidget {
  const StatusLine({required this.live, this.name, super.key});

  final ChatLive live;

  /// Na bolha de "digitando" o agente ainda não tem cabeçalho.
  final ChatWho? name;

  @override
  Widget build(BuildContext context) {
    final asking = live is LiveAsking;
    Widget text(String glyph) => Text(
      '${asking ? '●' : glyph} ${live.label}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'Menlo',
        fontSize: 11.5,
        color: asking ? AppColors.attention : AppColors.white(0.5),
        decoration: TextDecoration.none,
      ),
    );
    final line = asking
        ? text('●')
        : SpinnerBuilder(builder: (_, glyph) => text(glyph));
    if (name == null) return line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '✦ ${name!.id}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: ChatPalette.of(name!),
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 6),
        line,
      ],
    );
  }
}
