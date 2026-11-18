import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_probe.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_viewport.dart';

import '../../../support/in_memory_canvas_repository.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/pump_canvas.dart';

/// `/geometry` e `/shot` perguntando ao canvas de fora (decisão 35).
void main() {
  const window = WindowFrame(x: 100, y: 50, screenHeight: 1000);
  const cards = [
    CanvasCard(
      id: 'a',
      kind: NodeKind.shell,
      title: 'a',
      frame: Rect.fromLTWH(200, 300, 720, 460),
    ),
    CanvasCard(
      id: 'b',
      kind: NodeKind.web,
      title: 'b',
      frame: Rect.fromLTWH(1100, 300, 600, 400),
    ),
  ];

  group('a geometria pura', () {
    test('zoom 1: o frame do documento vira tela, de cima para baixo', () {
      final geometry = canvasGeometry(
        workbenchId: 'bancada',
        viewport: CanvasViewport(
          size: const Size(1200, 800),
          origin: const Offset(100, 200),
        ),
        cards: cards,
        origin: const Offset(10, 20),
        size: const Size(1200, 800),
        window: window,
        headerHeight: 46,
      );
      expect(geometry['workbench'], 'bancada');
      expect(geometry['mode'], 'canvas');
      expect(geometry['magnification'], 1.0);
      expect(geometry['scrollOrigin'], {'x': 100, 'y': 200});
      // Canto do canvas: janela (100,50) + onde ele cai na janela (10,20).
      expect(geometry['canvasOnScreen'], {
        'x': 110,
        'y': 70,
        'w': 1200,
        'h': 800,
      });

      final a = (geometry['nodes']! as List).first as Map<String, Object?>;
      expect(a['id'], 'a');
      expect(
        a['kind'],
        'TerminalNode',
        reason: 'o nome da classe, como o Swift',
      );
      expect(a['docFrame'], {'x': 200, 'y': 300, 'w': 720, 'h': 460});
      // (200-100)+110 = 210; (300-200)+70 = 170.
      expect(a['screenFrame'], {'x': 210, 'y': 170, 'w': 720, 'h': 460});
      expect(a['screenHeader'], {'x': 210, 'y': 170, 'w': 720, 'h': 46});
      expect(a['grabPoint'], {'x': 216, 'y': 193});
    });

    test('com zoom, o cabeçalho encolhe junto: 46 viram 23 a 50%', () {
      final geometry = canvasGeometry(
        workbenchId: 'b',
        viewport: CanvasViewport(
          size: const Size(1200, 800),
          zoom: 0.5,
          rawZoom: 0.5,
        ),
        cards: cards,
        origin: Offset.zero,
        size: const Size(1200, 800),
        window: window,
        headerHeight: 46,
      );
      expect(geometry['magnification'], 0.5);
      final a = (geometry['nodes']! as List).first as Map<String, Object?>;
      expect(a['screenFrame'], {'x': 200, 'y': 200, 'w': 360, 'h': 230});
      expect(a['screenHeader'], {'x': 200, 'y': 200, 'w': 360, 'h': 23});
      // Dentro do cabeçalho: nem na borda de cima, nem fora dele.
      final grab = a['grabPoint']! as Map<String, int>;
      expect(grab['y'], inInclusiveRange(200, 223));
    });

    test('card estreito: o ponto de arrasto fica a um quarto da largura', () {
      final geometry = canvasGeometry(
        workbenchId: 'b',
        viewport: CanvasViewport(size: const Size(1200, 800)),
        cards: const [
          CanvasCard(
            id: 'n',
            kind: NodeKind.queue,
            frame: Rect.fromLTWH(0, 0, 20, 100),
          ),
        ],
        origin: Offset.zero,
        size: const Size(1200, 800),
        window: const WindowFrame(x: 0, y: 0, screenHeight: 800),
        headerHeight: 46,
      );
      final n = (geometry['nodes']! as List).single as Map<String, Object?>;
      expect((n['grabPoint']! as Map)['x'], 5);
    });
  });

  test('o kind é o nome da classe da view, para cada tipo de nó', () {
    final geometry = canvasGeometry(
      workbenchId: 'b',
      viewport: CanvasViewport(size: const Size(1200, 800)),
      cards: const [
        CanvasCard(
          id: 's',
          kind: NodeKind.shell,
          frame: Rect.fromLTWH(0, 0, 300, 200),
        ),
        CanvasCard(
          id: 'a',
          kind: NodeKind.agent,
          frame: Rect.fromLTWH(0, 0, 300, 200),
        ),
        CanvasCard(
          id: 'w',
          kind: NodeKind.web,
          frame: Rect.fromLTWH(0, 0, 300, 200),
        ),
        CanvasCard(
          id: 'q',
          kind: NodeKind.queue,
          frame: Rect.fromLTWH(0, 0, 300, 200),
        ),
      ],
      origin: Offset.zero,
      size: const Size(1200, 800),
      window: window,
      headerHeight: 46,
    );
    final kinds = [
      for (final n in (geometry['nodes']! as List).cast<Map<String, Object?>>())
        n['kind'],
    ];
    expect(kinds, ['TerminalNode', 'TerminalNode', 'WebNode', 'QueueNode']);
  });

  test('em chat o canvas está coberto: modo real e magnificação 1', () {
    Map<String, Object?> of(String mode) => canvasGeometry(
      workbenchId: 'b',
      viewport: CanvasViewport(
        size: const Size(1200, 800),
        zoom: 0.5,
        rawZoom: 0.5,
      ),
      cards: cards,
      origin: Offset.zero,
      size: const Size(1200, 800),
      window: window,
      headerHeight: 46,
      mode: mode,
    );
    expect(of('canvas')['mode'], 'canvas');
    expect(of('canvas')['magnification'], 0.5);
    expect(of('chat')['mode'], 'chat');
    expect(of('chat')['magnification'], 1);
  });

  group('o registro', () {
    test('só solta se ainda for o mesmo (a bancada nova já registrou)', () {
      final registry = CanvasProbeRegistry();
      final old = _FakeProbe('antiga');
      final fresh = _FakeProbe('nova');
      registry.register(old);
      registry.register(fresh);
      registry.unregister(old);
      expect(registry.active, same(fresh));
      registry.unregister(fresh);
      expect(registry.active, isNull);
    });
  });

  group('no canvas vivo', () {
    testWidgets('a geometria bate com onde o card está na janela', (
      tester,
    ) async {
      final registry = CanvasProbeRegistry();
      final repo = InMemoryCanvasRepository(cards: cards, links: const []);
      await pumpCanvas(tester, repo, probes: registry);

      final probe = registry.active!;
      expect(probe.workbenchId, 'bancada');
      final geometry = probe.geometry(window);
      final nodes = (geometry['nodes']! as List).cast<Map<String, Object?>>();
      final a = nodes.firstWhere((n) => n['id'] == 'a');

      // O mesmo card, medido pelo teste (janela do teste = origem 0,0), mais o
      // canto da janela que passamos.
      final topLeft = tester.getTopLeft(find.byKey(const ValueKey('card-a')));
      final frame = a['screenFrame']! as Map<String, int>;
      expect(frame['x'], (topLeft.dx + window.x).round());
      expect(frame['y'], (topLeft.dy + window.y).round());
      final zoom = geometry['magnification']! as double;
      expect(frame['w'], (720 * zoom).round());

      // A caixa do canvas é a janela inteira do teste.
      expect(geometry['canvasOnScreen'], {
        'x': 100,
        'y': 50,
        'w': 1200,
        'h': 800,
      });
    });

    testWidgets('a bancada que sai desregistra', (tester) async {
      final registry = CanvasProbeRegistry();
      final repo = InMemoryCanvasRepository(cards: cards, links: const []);
      await pumpCanvas(tester, repo, probes: registry);
      expect(registry.active, isNotNull);

      await tester.pumpWidget(const SizedBox());
      expect(registry.active, isNull);
    });

    testWidgets('o /shot grava o card inteiro em PNG', (tester) async {
      final registry = CanvasProbeRegistry();
      final repo = InMemoryCanvasRepository(cards: cards, links: const []);
      await pumpCanvas(tester, repo, probes: registry);
      final dir = Directory.systemTemp.createTempSync('egeon-shot');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = '${dir.path}/a.png';

      final result = await tester.runAsync(
        () => registry.active!.snapshot('a', file),
      );
      expect(result, file);
      final bytes = File(file).readAsBytesSync();
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      // A largura do PNG (bytes 16–19 do IHDR) é a do card, no pixel ratio do teste (1).
      final width = ByteData.sublistView(bytes, 16, 20).getUint32(0);
      final height = ByteData.sublistView(bytes, 20, 24).getUint32(0);
      expect((width, height), (720, 460));
    });

    testWidgets('card que não existe devolve "erro: …", como o Swift', (
      tester,
    ) async {
      final registry = CanvasProbeRegistry();
      final repo = InMemoryCanvasRepository(cards: cards, links: const []);
      await pumpCanvas(tester, repo, probes: registry);
      final result = await tester.runAsync(
        () => registry.active!.snapshot('nao-existe', '/tmp/x.png'),
      );
      expect(result, startsWith('erro:'));
      expect(result, contains('nao-existe'));
    });

    testWidgets('arquivo que não grava devolve "erro: …"', (tester) async {
      final registry = CanvasProbeRegistry();
      final repo = InMemoryCanvasRepository(cards: cards, links: const []);
      await pumpCanvas(tester, repo, probes: registry);
      final result = await tester.runAsync(
        () => registry.active!.snapshot('a', '/pasta/que/nao/existe/a.png'),
      );
      expect(result, startsWith('erro:'));
    });

    testWidgets('a página nativa (web) entra no corpo do card', (tester) async {
      final registry = CanvasProbeRegistry();
      final repo = InMemoryCanvasRepository(cards: cards, links: const []);
      var asked = '';
      final png = (await tester.runAsync(_redPng))!;
      await pumpCanvas(
        tester,
        repo,
        probes: registry,
        nativeCapture: (id) async {
          asked = id;
          return png;
        },
      );
      final dir = Directory.systemTemp.createTempSync('egeon-shot');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = '${dir.path}/b.png';
      final result = await tester.runAsync(
        () => registry.active!.snapshot('b', file),
      );
      expect(result, file);
      expect(asked, 'b');
      final bytes = File(file).readAsBytesSync();
      expect(ByteData.sublistView(bytes, 16, 20).getUint32(0), 600);
    });
  });
}

class _FakeProbe implements CanvasProbe {
  _FakeProbe(this.workbenchId);

  @override
  final String workbenchId;

  @override
  Map<String, Object?> geometry(WindowFrame window, {String mode = 'canvas'}) =>
      {};

  @override
  Future<String> snapshot(String cardId, String file) async => file;
}

/// Um PNG de verdade (vermelho, 8×8), gerado pelo próprio motor.
Future<Uint8List> _redPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    ui.Paint()..color = const Color(0xFFFF0000),
  );
  final image = await recorder.endRecording().toImage(8, 8);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
