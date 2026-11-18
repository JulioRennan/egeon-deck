import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/cubits/connection_cubit.dart';
import '../../../../core/domain/errors/core_error.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_theme.dart';

/// Sem bancada aberta, como no Swift: o canvas fica de fora e a barra lateral
/// explica o +. Aqui só o aviso de conexão com o core Rust.
class HomeContent extends StatelessWidget {
  const HomeContent({super.key});

  @override
  Widget build(BuildContext context) {
    return switch (context.watch<ConnectionCubit>().state) {
      CoreFailed(error: CoreLaunchFailed(:final message)) => HomeNotice(
        message,
      ),
      CoreConnecting() => const HomeNotice('Conectando ao core…'),
      CoreConnected() => const SizedBox.expand(),
    };
  }
}

class HomeNotice extends StatelessWidget {
  const HomeNotice(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: AppTheme.textStyle.copyWith(color: AppColors.textMuted),
        ),
      ),
    );
  }
}
