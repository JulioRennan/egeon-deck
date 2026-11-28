import 'package:egeon_deck/features/processes/domain/entities/processes_view.dart';
import 'package:egeon_deck/features/processes/domain/repository/processes_repository.dart';

/// Os processos de mentira: o teste decide a lista e lê o que a UI pediu.
class FakeProcessesRepository implements ProcessesRepository {
  FakeProcessesRepository(this.rows);

  List<ProcessRow> rows;
  var lists = 0;
  var reaps = 0;
  final kills = <List<int>>[];

  String get summary {
    final orphans = rows.where((r) => r.orphan).length;
    return '${rows.length - orphans} no app · $orphans órfão${orphans == 1 ? '' : 's'}';
  }

  ProcessesView get _view => ProcessesView(
    rows: List.of(rows),
    summary: summary,
    orphans: rows.where((r) => r.orphan).length,
  );

  /// As perguntas que o core escreveria (o texto do NSAlert do Swift).
  @override
  Future<ProcessConfirm> confirmReap() async {
    final n = rows.where((r) => r.orphan).length;
    return ProcessConfirm(
      title: 'Encerrar $n ${n == 1 ? 'processo órfão' : 'processos órfãos'}?',
      detail: 'Recebem SIGTERM — o mesmo que fechar o terminal deles.',
    );
  }

  @override
  Future<ProcessConfirm> confirmKill(List<int> pids) async {
    final live = rows.where((r) => pids.contains(r.pid) && !r.orphan).length;
    final n = pids.length;
    return ProcessConfirm(
      title:
          'Encerrar $n ${n == 1 ? 'processo' : 'processos'}?'
          '${live > 0 ? ' $live ainda são de terminal aberto.' : ''}',
      detail: 'Recebem SIGTERM — o mesmo que fechar o terminal deles.',
    );
  }

  @override
  Future<ProcessesView> list() async {
    lists++;
    return _view;
  }

  @override
  Future<ProcessesView> reap() async {
    reaps++;
    rows = [
      for (final r in rows)
        if (!r.orphan) r,
    ];
    return _view;
  }

  @override
  Future<ProcessesView> kill(List<int> pids) async {
    kills.add(pids);
    rows = [
      for (final r in rows)
        if (!pids.contains(r.pid)) r,
    ];
    return _view;
  }
}

List<ProcessRow> sampleProcesses() => const [
  ProcessRow(pid: 100, node: 'claude', age: '2 h', command: 'claude --resume'),
  ProcessRow(pid: 200, node: 'sh', age: '5 min', command: '/bin/zsh -l'),
  ProcessRow(pid: 300, age: '1 d', command: 'node server.js', orphan: true),
  ProcessRow(
    pid: 400,
    node: 'dev',
    age: '3 d',
    command: 'tail -f log',
    orphan: true,
  ),
];
