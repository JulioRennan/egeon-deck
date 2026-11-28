/// Deixa a conexão falsa e os streams andarem um pouco.
Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));
