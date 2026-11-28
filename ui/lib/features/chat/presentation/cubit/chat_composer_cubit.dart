import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/chat_block.dart';
import '../../domain/entities/chat_completion.dart';
import '../../domain/entities/chat_participant.dart';
import '../../domain/entities/chat_thread.dart';
import '../../domain/errors/chat_error.dart';
import '../../domain/usecase/chat_actions.dart';

part 'chat_composer_state.dart';

/// O composer do chat: para quem ele manda e o que está citando. O foco e a
/// citação são o que a pessoa escolheu; o destino é derivado deles e de quem
/// ainda vive na conversa, que chega pela thread da [ChatConversationCubit].
class ChatComposerCubit extends Cubit<ChatComposerState> {
  ChatComposerCubit({
    required this.workbenchId,
    required Stream<ChatThread> threads,
    required this._actions,
  }) : super(const ComposerNobody()) {
    _subscription = threads.listen((thread) {
      _participants = thread.participants;
      _derive();
    });
  }

  final String workbenchId;
  final ChatActions _actions;
  StreamSubscription<ChatThread>? _subscription;
  final _sent = StreamController<void>.broadcast();

  var _participants = const <ChatParticipantInfo>[];
  String? _focus;
  ChatBlock? _quote;

  /// Cada mensagem que o usuário mandou: a thread desce até o fim, mesmo
  /// vindo de um ponto acima dele.
  Stream<void> get sent => _sent.stream;

  /// Quem ainda roda: terminal fechado continua na coluna, mas não recebe.
  Iterable<ChatParticipantInfo> get _alive =>
      _participants.where((p) => !p.isDead);

  /// Quem o Tab percorre: só agentes vivos. Shell entra por clique — ciclar
  /// por ele no meio de uma conversa entre agentes é parada que não se quer.
  List<ChatParticipantInfo> get _cycleable => [
    for (final p in _alive)
      if (p.isAgent) p,
  ];

  /// O destino: o que está em foco, se ainda vive; senão o primeiro agente
  /// vivo e, sem agente, o primeiro que vive.
  ChatParticipantInfo? get _target =>
      _alive.where((p) => p.id == _focus).firstOrNull ??
      _cycleable.firstOrNull ??
      _alive.firstOrNull;

  /// A fila nova liga a um agente: o que está em foco, e na falta dele o
  /// primeiro. Terminal em foco não vale — fila só fala com agente.
  String? get _queueAgent {
    final agents = _participants.where((p) => p.isAgent);
    return (agents.where((a) => a.id == _focus).firstOrNull ??
            agents.firstOrNull)
        ?.id;
  }

  void _derive() {
    if (isClosed) return;
    final queueAgent = _queueAgent;
    emit(switch (_target) {
      null => ComposerNobody(queueAgent: queueAgent),
      final agent when agent.isAgent => ComposerToAgent(
        agent,
        quote: _quote,
        queueAgent: queueAgent,
      ),
      final shell => ComposerToShell(
        shell,
        quote: _quote,
        queueAgent: queueAgent,
      ),
    });
  }

  /// Clicar num participante o põe em foco: é para ele que o composer manda.
  void focusOn(String id) {
    _focus = id;
    _derive();
  }

  /// Tab no composer alterna entre os agentes vivos; de um shell em foco, vai
  /// ao primeiro.
  void focusNext() {
    final agents = _cycleable;
    if (agents.isEmpty) return;
    final at = agents.indexWhere((a) => a.id == _target?.id);
    focusOn(agents[(at + 1) % agents.length].id);
  }

  void quote(ChatBlock block) {
    _quote = block;
    _derive();
  }

  void clearQuote() {
    _quote = null;
    _derive();
  }

  /// As sugestões do menu do composer para o texto e o cursor; falha vira
  /// "sem sugestões" — o menu é conforto, não pode atrapalhar quem digita.
  Future<ChatCompletion> complete(String text, int caret, {String? search}) =>
      _actions
          .complete(
            workbenchId,
            text,
            caret,
            to: state.target?.id,
            search: search,
          )
          .catchError(
            (_) => ChatCompletion.none(caret),
            test: (error) => error is ChatError,
          );

  /// Manda a mensagem. Texto vazio não vai; a citação sai junto e se esvazia.
  void send(String text) {
    final typed = text.trim();
    final target = state.target;
    if (typed.isEmpty || target == null) return;
    unawaited(
      _actions
          .send(
            workbenchId,
            to: [target.id],
            text: typed,
            quoteKey: _quote?.messageKey,
          )
          .catchError((_) {}, test: (error) => error is ChatError),
    );
    _quote = null;
    _derive();
    _sent.add(null);
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    await _sent.close();
    return super.close();
  }
}
