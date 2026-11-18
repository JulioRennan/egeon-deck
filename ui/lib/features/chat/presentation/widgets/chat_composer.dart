import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/app_text_field.dart';
import '../../../../theme/app_colors.dart';
import '../../domain/entities/chat_block.dart';
import '../../domain/entities/chat_completion.dart';
import '../../domain/entities/chat_participant.dart';
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
    super.key,
  });

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

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
    decoration: BoxDecoration(
      color: const Color(0xFF161616),
      border: Border(top: BorderSide(color: AppColors.white(0.09))),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_menuOpen)
          CompletionMenu(
            items: _completion.items,
            selected: _picked,
            onPick: (item) => setState(() => _insert(item)),
          ),
        if (widget.quote != null) _quote(widget.quote!),
        if (widget.target != null) _recipient(widget.target!),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AppTextField(
                key: const ValueKey('composer-field'),
                controller: _text,
                placeholder: widget.target == null
                    ? 'Ninguém na conversa ainda'
                    : 'Mensagem',
                maxLines: 8,
                minLines: 1,
                onKeyEvent: _onKey,
              ),
            ),
            const SizedBox(width: 8),
            ListenableBuilder(
              listenable: _text,
              builder: (context, _) => _SendButton(
                enabled: _text.text.trim().isNotEmpty && widget.target != null,
                onTap: _send,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _quote(ChatBlock block) {
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
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              decoration: BoxDecoration(
                color: AppColors.black(0.2),
                borderRadius: BorderRadius.circular(6),
                border: const Border(
                  left: BorderSide(color: Color(0xFF2F7FF6), width: 3),
                ),
              ),
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.white(0.7),
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClearQuote,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  '✕',
                  key: const ValueKey('quote-clear'),
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.white(0.5),
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

  Widget _recipient(ChatParticipantInfo target) {
    final color = ChatPalette.of(
      ChatWho(id: target.id, address: target.address, isAgent: target.isAgent),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'para ',
                style: TextStyle(color: AppColors.white(0.45)),
              ),
              TextSpan(
                text: '${target.isAgent ? '✦' : '❯'} ${target.id}',
                style: TextStyle(color: color, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          key: const ValueKey('composer-target'),
          style: const TextStyle(fontSize: 11, decoration: TextDecoration.none),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
    child: GestureDetector(
      key: const ValueKey('composer-send'),
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? AppColors.accent : AppColors.white(0.1),
          shape: BoxShape.circle,
        ),
        child: Text(
          '↑',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.white(enabled ? 1 : 0.35),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
  );
}
