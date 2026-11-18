enum ConnectionPhase { starting, connected, failed }

class CoreStatus {
  const CoreStatus(this.phase, {this.error});

  final ConnectionPhase phase;
  final String? error;
}
