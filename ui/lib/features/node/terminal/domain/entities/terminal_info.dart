/// Um terminal que o core Rust conhece.
class TerminalInfo {
  const TerminalInfo({
    required this.id,
    required this.alive,
    required this.columns,
    required this.rows,
    this.cwd,
    this.pid,
    this.command,
    this.exitCode,
  });

  final String id;
  final bool alive;
  final int columns;
  final int rows;
  final String? cwd;
  final int? pid;
  final String? command;
  final int? exitCode;

  factory TerminalInfo.fromMap(Map<String, Object?> map) => TerminalInfo(
    id: map['id']! as String,
    alive: map['alive']! as bool,
    columns: map['cols']! as int,
    rows: map['rows']! as int,
    cwd: map['cwd'] as String?,
    pid: map['pid'] as int?,
    command: map['command'] as String?,
    exitCode: map['exit_code'] as int?,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'alive': alive,
    'cols': columns,
    'rows': rows,
    if (cwd != null) 'cwd': cwd,
    if (pid != null) 'pid': pid,
    if (command != null) 'command': command,
    if (exitCode != null) 'exit_code': exitCode,
  };
}
