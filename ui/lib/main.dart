import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/adapters/egeon_paths.dart';
import 'core/adapters/injector.dart';
import 'core/cubits/connection_cubit.dart';
import 'features/home/presentation/page/home_page.dart';
import 'core/di/injection.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

void main() => runApp(createEgeonDeckApp(Platform.environment));

/// Registra as dependências reais — socket, lançador do core Rust e
/// repositórios — e monta o app. Uma vez por processo.
EgeonDeckApp createEgeonDeckApp(Map<String, String> environment) {
  registerInfrastructure(environment);
  registerDomain();
  return EgeonDeckApp(
    connection: inject<ConnectionCubit>(),
    title: inject<EgeonPaths>().flavor.title,
  );
}

/// Raiz do app: entrega a conexão com o core Rust à `home`. O resto vem do
/// injector.
class EgeonDeckApp extends StatefulWidget {
  const EgeonDeckApp({
    super.key,
    required this.connection,
    this.title = 'Egeon Deck',
  });

  final ConnectionCubit connection;

  /// O nome da janela: o dev se diz dev, para você não falar com o app errado.
  final String title;

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
    return BlocProvider.value(
      value: widget.connection,
      child: WidgetsApp(
        title: widget.title,
        debugShowCheckedModeBanner: false,
        color: AppColors.background,
        textStyle: AppTheme.textStyle,
        builder: (context, _) => HomePage(title: widget.title),
      ),
    );
  }
}
