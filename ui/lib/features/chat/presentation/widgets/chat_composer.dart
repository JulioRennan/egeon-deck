import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/glass_surface.dart';
import '../../../../commons/widgets/eg/icon_button.dart' as eg;
import '../../../../commons/widgets/eg/menu.dart';
import '../../../../commons/widgets/eg/pressable.dart';
import '../../../../commons/widgets/eg/tooltip.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/chat_block.dart';
import '../../domain/entities/chat_completion.dart';
import '../../domain/entities/chat_participant.dart';
import '../../../../theme/egeon_colors.dart';
import 'chat_palette.dart';
import 'completion_menu.dart';

/// A caixa de mensagem: para quem vai (os agentes da conversa), o texto e,
/// se houver, a linha que está sendo citada. Enter manda; Shift+Enter quebra
/// a linha. O estado do texto é só daqui: digitar não refaz a thread.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    required this.target,
    required this.onSend,
    this.onNextTarget,
    this.onComplete,
    this.quote,
    this.onClearQuote,
    this.focusNode,
    this.above = const [],
    this.autofocus = true,
    this.margin = const EdgeInsets.fromLTRB(20, 0, 20, 20),
    this.participants = const [],
    this.onPickTarget,
    this.traits,
    super.key,
  });

  /// "modelo · esforço" do destinatário, ao lado do enviar; vem de fora porque
  /// o estado do agente é de outra feature.
  final Widget? traits;

  /// Para quem vai a mensagem: o participante em foco. Sem ninguém, não manda.
  final ChatParticipantInfo? target;

  /// Manda o texto ao destino.
  final ValueChanged<String> onSend;

  /// Tab alterna o destino entre os agentes.
  final VoidCallback? onNextTarget;

  /// Pergunta ao core as sugestões para o texto e o cursor.
  final Future<ChatCompletion> Function(String text, int caret)? onComplete;
  final ChatBlock? quote;
  final VoidCallback? onClearQuote;

  /// O teclado do campo: entrar no chat e escolher um participante o trazem
  /// para cá.
  final FocusNode? focusNode;

  /// O teclado vai ao campo ao montar: no chat sim; no canvas não, para não
  /// tirar o foco do terminal.
  final bool autofocus;

  /// O respiro em volta do cartão.
  final EdgeInsets margin;

  /// O que mora dentro do composer, acima do campo: os pedidos de permissão.
  final List<Widget> above;

  /// Quem pode receber, para o menu do destinatário; escolher um é focá-lo.
  final List<ChatParticipantInfo> participants;
  final ValueChanged<String>? onPickTarget;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _text = TextEditingController();

  /// As sugestões de agora, a escolhida e a pergunta mais nova: resposta de
  /// pergunta velha, que chega depois, não vale.
  ChatCompletion _completion = const ChatCompletion();
  var _picked = 0;
  var _asked = 0;
  String _lastAsked = '';

  @override
  void initState() {
    super.initState();
    _text.addListener(_onEdit);
  }

  /// Texto ou cursor mudaram: pergunta ao core se há o que sugerir.
  void _onEdit() {
    final complete = widget.onComplete;
    if (complete == null) return;
    final text = _text.text;
    final caret = _text.selection.baseOffset;
    if (caret < 0) return;
    final signature = '$caret|$text';
    if (signature == _lastAsked) return;
    _lastAsked = signature;
    final question = ++_asked;
    complete(text, caret).then((result) {
      if (!mounted || question != _asked) return;
      setState(() {
        _completion = result;
        _picked = 0;
      });
    });
  }

  bool get _menuOpen => !_completion.isEmpty;

  void _close() => setState(() => _completion = const ChatCompletion());

  /// Troca o trecho digitado pela sugestão e põe o cursor depois dela.
  void _insert(CompletionItem item) {
    final applied = _completion.apply(_text.text, item);
    _completion = const ChatCompletion();
    _text.value = TextEditingValue(
      text: applied.text,
      selection: TextSelection.collapsed(offset: applied.caret),
    );
  }

  void _send() {
    final typed = _text.text.trim();
    if (typed.isEmpty || widget.target == null) return;
    widget.onSend(typed);
    _text.clear();
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_menuOpen) {
      final key = event.logicalKey;
      final count = _completion.items.length;
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() => _picked = (_picked + 1) % count);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() => _picked = (_picked - 1 + count) % count);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.tab) {
        _insert(_completion.items[_picked]);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _close();
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        widget.onNextTarget != null) {
      widget.onNextTarget!();
      return KeyEventResult.handled;
    }
    final enter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!enter) return KeyEventResult.ignored;
    // Shift+Enter quebra a linha; Enter sozinho manda. Em composição (IME) o
    // Enter confirma o texto, e esse evento nem chega aqui como Enter.
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    _send();
    return KeyEventResult.handled;
  }

  final _recipientKey = GlobalKey();

  /// Insere [char] onde está o cursor: o botão de "/" e de "@" só digitam, e o
  /// core responde com as sugestões como em qualquer digitação.
  void _type(String char) {
    final value = _text.value;
    final sel = value.selection;
    final at = sel.isValid ? sel.start : value.text.length;
    final end = sel.isValid ? sel.end : value.text.length;
    _text.value = TextEditingValue(
      text: value.text.replaceRange(at, end, char),
      selection: TextSelection.collapsed(offset: at + char.length),
    );
    widget.focusNode?.requestFocus();
  }

  void _pickRecipient() {
    final onPick = widget.onPickTarget;
    if (onPick == null) return;
    final box = _recipientKey.currentContext!.findRenderObject()! as RenderBox;
    final alive = [
      for (final p in widget.participants)
        if (!p.isDead) p,
    ];
    showMenu(
      context,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      width: 240,
      items: [
        const MenuHeader('Mandar para'),
        for (final p in alive)
          MenuItem(
            p.id,
            checked: p.id == widget.target?.id,
            onSelected: () => onPick(p.id),
            leading: null,
            desc: p.address,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final target = widget.target;
    final canSend = target != null;
    final style = EgeonType.body.copyWith(
      fontSize: 14,
      height: 22 / 14,
      color: c.textPrimary,
      decoration: TextDecoration.none,
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720 + 40),
        child: Padding(
          padding: widget.margin,
          child: GlassSurface(
            radius: 16,
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final tray in widget.above)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: tray,
                  ),
                if (_menuOpen)
                  CompletionMenu(
                    items: _completion.items,
                    selected: _picked,
                    targetName: target?.id,
                    onPick: (item) => setState(() => _insert(item)),
                  ),
                if (widget.quote != null) _quote(widget.quote!),
                _field(style, canSend),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, box) {
                    final roomy = box.maxWidth >= 460;
                    final wide = box.maxWidth >= 300;
                    return Row(
                      spacing: 4,
                      children: [
                        _SlashButton(onTap: canSend ? () => _type('/') : null),
                        eg.IconButton(
                          key: const ValueKey('composer-at'),
                          icon: EgIcons.at,
                          tooltip: 'Mencionar agente (@)',
                          compact: true,
                          onPressed: canSend ? () => _type('@') : null,
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, room) => Row(
                              children: [
                                // O destinatário toma até 60% do vão; o resto é
                                // do "modelo · esforço", colado à direita.
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: room.maxWidth * 0.6,
                                  ),
                                  child: target == null
                                      ? const SizedBox.shrink()
                                      : _recipient(c, target, label: wide),
                                ),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: widget.traits != null && roomy
                                        ? widget.traits
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        ListenableBuilder(
                          listenable: _text,
                          builder: (context, _) => _SendButton(
                            enabled: _text.text.trim().isNotEmpty && canSend,
                            onTap: _send,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// O campo, sem borda nem fundo: o vidro do composer é o fundo dele.
  Widget _field(TextStyle style, bool canSend) {
    final c = context.eg;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => _onKey(event),
      child: Stack(
        children: [
          ListenableBuilder(
            listenable: _text,
            builder: (context, _) => _text.text.isEmpty
                ? IgnorePointer(
                    child: Text(
                      canSend
                          ? 'Peça algo ao time… / para comandos, @ para '
                                'mencionar'
                          : 'Ninguém na conversa ainda',
                      style: style.copyWith(color: c.textMuted),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          KeyedSubtree(
            key: const ValueKey('composer-field'),
            child: EditableText(
              controller: _text,
              focusNode: widget.focusNode ?? (_ownFocus ??= FocusNode()),
              autofocus: widget.autofocus,
              style: style,
              cursorColor: c.accent,
              backgroundCursorColor: c.steelActive,
              selectionColor: c.accentSoft,
              maxLines: 8,
              minLines: 2,
              keyboardType: TextInputType.multiline,
            ),
          ),
        ],
      ),
    );
  }

  FocusNode? _ownFocus;

  @override
  void dispose() {
    _ownFocus?.dispose();
    _text.dispose();
    super.dispose();
  }

  Widget _quote(ChatBlock block) {
    final c = context.eg;
    final text = switch (block) {
      PromptBlock(:final text) => text,
      _ => block.messageKey,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
              decoration: BoxDecoration(
                color: c.obsidian,
                borderRadius: BorderRadius.circular(6),
                border: Border(left: BorderSide(color: c.accent, width: 2)),
              ),
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: EgeonType.caption.copyWith(
                  color: c.textSecondary,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
          eg.IconButton(
            key: const ValueKey('quote-clear'),
            icon: EgIcons.x,
            tooltip: 'Tirar a citação',
            compact: true,
            onPressed: widget.onClearQuote,
          ),
        ],
      ),
    );
  }

  /// "Para agente ▾": quem recebe; Tab troca, o clique abre a lista.
  Widget _recipient(
    EgeonColors c,
    ChatParticipantInfo target, {
    bool label = true,
  }) {
    final color = target.isAgent
        ? ChatPalette.of(
            c,
            ChatWho(id: target.id, address: target.address, isAgent: true),
          )
        : c.textPrimary;
    return Pressable(
      key: _recipientKey,
      onPressed: widget.onPickTarget == null ? null : _pickRecipient,
      semanticLabel: 'Destinatário: ${target.id}',
      builder: (context, s) => DecoratedBox(
        decoration: BoxDecoration(
          color: s.hovered ? c.steel : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SizedBox(
          height: 28,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label) ...[
                  Text(
                    'Para',
                    style: EgeonType.caption.copyWith(
                      color: c.textSecondary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    target.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    key: const ValueKey('composer-target'),
                    style: EgeonType.label.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                EgIcon(EgIcons.chevronDown, size: 12, color: c.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "/" num quadrado de linha: o botão de comandos (a v3 o distingue do "@").
class _SlashButton extends StatelessWidget {
  const _SlashButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Tooltip(
      message: 'Comandos (/)',
      child: Pressable(
        key: const ValueKey('composer-slash'),
        onPressed: onTap,
        semanticLabel: 'Comandos',
        builder: (context, s) {
          final color = onTap == null
              ? c.textDisabled
              : s.hovered
              ? c.textPrimary
              : c.textSecondary;
          return SizedBox(
            width: EgeonSize.controlSm,
            height: EgeonSize.controlSm,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: color),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: Center(
                    child: EgIcon(EgIcons.slash, size: 10, color: color),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Enviar (↵): `primary`, 32; sem texto fica a 40%.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Pressable(
      key: const ValueKey('composer-send'),
      onPressed: enabled ? onTap : null,
      semanticLabel: 'Enviar',
      builder: (context, s) => Opacity(
        opacity: enabled ? 1 : EgeonOpacity.disabled,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: s.pressed
                ? c.primaryPressed
                : s.hovered
                ? c.primaryHover
                : c.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Center(
              child: EgIcon(EgIcons.send, size: 16, color: c.onPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
