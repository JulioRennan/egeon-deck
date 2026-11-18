import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/widgets/app_dialog.dart';
import '../../../../commons/widgets/standard_dialogs.dart';
import '../../domain/entities/app_effect.dart';
import '../../domain/repository/app_repository.dart';
import '../../domain/usecase/answer_app.dart';
import '../../domain/usecase/watch_app.dart';
import '../cubit/update_cubit.dart';
import 'update_prompt_body.dart';

/// Hospeda o cubit do app e desenha o que o core pede: o aviso de versão nova
/// (uma folha por vez; enquanto está aberta, os terminais seguem desenhando),
/// a mensagem de uma linha, o encerrar do app e a abertura de Processos.
///
/// Fica abaixo de um `Overlay` — [dialogContext] devolve o contexto que o tem,
/// quando o do próprio widget não serve.
class UpdateHost extends StatefulWidget {
  const UpdateHost({
    required this.child,
    this.onShowProcesses,
    this.onTerminate,
    this.dialogContext,
    super.key,
  });

  final Widget child;

  /// O core pediu a janela "Processos".
  final VoidCallback? onShowProcesses;

  /// A troca está agendada. Sem ouvinte, o app encerra.
  final VoidCallback? onTerminate;

  final BuildContext Function()? dialogContext;

  @override
  State<UpdateHost> createState() => _UpdateHostState();
}

class _UpdateHostState extends State<UpdateHost> {
  late final UpdateCubit _cubit;
  StreamSubscription<AppEffect>? _effects;
  var _prompting = false;

  @override
  void initState() {
    super.initState();
    final repository = context.read<AppRepository>();
    _cubit = UpdateCubit(
      watch: WatchApp(repository),
      answer: AnswerApp(repository),
    );
    _effects = _cubit.effects.listen(_onEffect);
  }

  @override
  void dispose() {
    unawaited(_effects?.cancel());
    unawaited(_cubit.close());
    super.dispose();
  }

  BuildContext get _dialogs => widget.dialogContext?.call() ?? context;

  void _onEffect(AppEffect effect) {
    switch (effect) {
      case UpdatePrompt():
        unawaited(_prompt(effect));
      case UpdateMessage(:final title, :final text):
        unawaited(messageDialog(_dialogs, title: title, message: text));
      case Terminate():
        (widget.onTerminate ?? _exit)();
      case ShowProcesses():
        widget.onShowProcesses?.call();
    }
  }

  Future<void> _prompt(UpdatePrompt prompt) async {
    // Uma folha por vez: um segundo aviso não empilha.
    if (_prompting || !mounted) return;
    _prompting = true;
    final choice = await showAppDialog<UpdateChoice>(
      _dialogs,
      width: 500,
      builder: (_, close) => UpdatePromptBody(prompt: prompt, close: close),
    );
    _prompting = false;
    // Esc e o clique fora são "Depois", com a caixa como o core a mandou.
    final answer = choice ?? (accept: false, auto: prompt.auto);
    _cubit.answer(
      version: prompt.version,
      accept: answer.accept,
      auto: answer.auto,
    );
  }

  /// `cancelable`: a saída passa pelo `onExitRequested` da casca, que fecha a
  /// conexão e o core com calma; `required` o pularia.
  static void _exit() => unawaited(
    ServicesBinding.instance.exitApplication(ui.AppExitType.cancelable),
  );

  @override
  Widget build(BuildContext context) =>
      BlocProvider<UpdateCubit>.value(value: _cubit, child: widget.child);
}
