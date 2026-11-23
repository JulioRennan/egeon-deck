/// Os estados de um agente (DS `Status`). Cada um tem cor e forma, para nunca
/// depender só da cor.
enum Status {
  attention('Precisa de você'),
  running('Trabalhando'),
  success('Terminou'),
  background('Em segundo plano'),
  waiting('Aguardando vizinho'),
  retrying('Tentando de novo'),
  danger('Falhou'),
  idle('Parado'),
  dead('Encerrado');

  const Status(this.label);

  /// O texto do estado, para leitor de tela e rótulo.
  final String label;
}
