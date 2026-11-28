import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart' show Theme;

import 'core/adapters/app_windows.dart';
import 'core/adapters/egeon_paths.dart';
import 'core/adapters/injector.dart';
import 'core/cubits/connection_cubit.dart';
import 'features/home/presentation/page/home_page.dart';
import 'core/di/injection.dart';
import 'core/domain/usecase/join_core.dart';
import 'features/processes/presentation/widgets/processes_panel.dart';
import 'theme/egeon_colors.dart';
import 'features/home/presentation/page/design_sample_page.dart';
import 'theme/egeon_theme.dart';
import 'theme/egeon_type.dart';

void main(List<String> args) {
  final window = WindowArguments.fromEntrypoint(args);
  runApp(
    window == null
        ? createEgeonDeckApp(Platform.environment)
        : createSecondaryWindow(Platform.environment, window),
  );
}

/// Registra as dependências reais — socket, lançador do core Rust e
/// repositórios — e monta o app. Uma vez por processo.
EgeonDeckApp createEgeonDeckApp(Map<String, String> environment) {
  registerInfrastructure(environment);
  registerDomain();
  return EgeonDeckApp(
    connection: inject<ConnectionCubit>(),
    title: inject<EgeonPaths>().flavor.title,
    showSample:
        inject<EgeonPaths>().flavor == EgeonFlavor.dev &&
        environment['EGEON_DESIGN_SAMPLE'] == '1',
  );
}

/// Raiz do app: entrega a conexão com o core Rust à `home`. O resto vem do
/// injector.
class EgeonDeckApp extends StatefulWidget {
  const EgeonDeckApp({
    super.key,
    required this.connection,
    this.title = 'Egeon Deck',
    this.showSample = false,
  });

  final ConnectionCubit connection;

  /// O nome da janela: o dev se diz dev, para você não falar com o app errado.
  final String title;

  /// Só no dev: abre a amostra do design system no lugar da `home`.
  final bool showSample;

  @override
  State<EgeonDeckApp> createState() => _EgeonDeckAppState();
}

class _EgeonDeckAppState extends State<EgeonDeckApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Ao sair, o core lançado por esta UI sai junto.
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.connection.close();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const colors = EgeonColors.dark;
    return BlocProvider.value(
      value: widget.connection,
      child: WidgetsApp(
        title: widget.title,
        debugShowCheckedModeBanner: false,
        color: colors.obsidian,
        textStyle: EgeonType.body.copyWith(
          color: colors.textPrimary,
          decoration: TextDecoration.none,
        ),
        builder: (context, _) => Theme(
          data: EgeonTheme.dark(),
          child: widget.showSample
              ? const DesignSamplePage()
              : HomePage(title: widget.title),
        ),
      ),
    );
  }
}

/// Uma janela secundária (decisão 51): motor próprio, as mesmas dependências
/// reais, mas só conecta ao core que a principal subiu.
SecondaryWindowApp createSecondaryWindow(
  Map<String, String> environment,
  WindowArguments arguments,
) {
  registerInfrastructure(environment);
  registerDomain();
  inject<JoinCore>()();
  return SecondaryWindowApp(arguments: arguments, window: inject());
}

class SecondaryWindowApp extends StatefulWidget {
  const SecondaryWindowApp({
    required this.arguments,
    required this.window,
    super.key,
  });

  final WindowArguments arguments;
  final CurrentWindow window;

  @override
  State<SecondaryWindowApp> createState() => _SecondaryWindowAppState();
}

class _SecondaryWindowAppState extends State<SecondaryWindowApp> {
  @override
  void initState() {
    super.initState();
    // Mostra só depois do primeiro quadro: antes disso a janela seria um
    // retângulo vazio.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(
        widget.window.present(
          title: widget.arguments.title,
          size: switch (widget.arguments.kind) {
            WindowKind.processes => ProcessesWindowPage.size,
          },
          minSize: switch (widget.arguments.kind) {
            WindowKind.processes => ProcessesWindowPage.minSize,
          },
          autosave: widget.arguments.kind.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const colors = EgeonColors.dark;
    return WidgetsApp(
      title: widget.arguments.title,
      debugShowCheckedModeBanner: false,
      color: colors.obsidian,
      textStyle: EgeonType.body.copyWith(
        color: colors.textPrimary,
        decoration: TextDecoration.none,
      ),
      builder: (context, _) => Theme(
        data: EgeonTheme.dark(),
        // O Overlay é das confirmações da janela (encerrar órfãos).
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (_) => switch (widget.arguments.kind) {
                WindowKind.processes => ProcessesWindowPage(
                  onClose: () => unawaited(widget.window.close()),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}
