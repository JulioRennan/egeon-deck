import XCTest
@testable import EgeonDeck

/// Onde a linha arrastada cai: a barra montada de verdade, com os frames do
/// layout, e o alvo calculado a partir de um ponto. Arrastar não é dirigível
/// de fora sem Acessibilidade (ADR-003) — o que dá para provar é a conta que
/// o arrasto usa.
@MainActor
final class SidebarDropTests: XCTestCase {
    private func project(_ id: String) -> ProjectConfig {
        ProjectConfig(id: id, name: id, path: "~/\(id)")
    }
    private func bench(_ name: String, _ project: String) -> WorkbenchConfig {
        WorkbenchConfig(name: name, path: "~/x", nodes: [], project: project)
    }

    /// Dois workspaces, o primeiro com dois projetos e três bancadas.
    private func sidebar() -> (Sidebar, [WorkspaceConfig], [WorkbenchConfig]) {
        let spaces = [WorkspaceConfig(id: "w1", name: "Um", projects: [project("p1"), project("p2")]),
                      WorkspaceConfig(id: "w2", name: "Dois", projects: [project("p3")])]
        let benches = [bench("um", "p1"), bench("dois", "p1"), bench("três", "p2")]
        let bar = Sidebar(workspaces: spaces, configs: benches)
        bar.frame = NSRect(x: 0, y: 0, width: 264, height: 800)
        let window = NSWindow(contentRect: bar.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = bar
        bar.layoutSubtreeIfNeeded()
        return (bar, spaces, benches)
    }

    /// O dígito fica no meio do selo — medido no pixel, que é onde o olho
    /// reclamou: o rótulo antes centrava a caixa do texto, não o glifo.
    func testCountSealCentersTheDigit() throws {
        for value in [1, 5, 12] {
            let seal = CountSeal()
            seal.value = value
            seal.frame = NSRect(origin: .zero, size: seal.size)
            let rep = try XCTUnwrap(seal.bitmapImageRepForCachingDisplay(in: seal.bounds))
            seal.cacheDisplay(in: seal.bounds, to: rep)

            // As linhas de pixel onde o dígito (claro) aparece, ignorando o
            // anel escuro e o fundo do selo.
            let scale = CGFloat(rep.pixelsHigh) / seal.bounds.height
            var rows: [Int] = []
            var columns: [Int] = []
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5,
                          color.brightnessComponent > 0.55 else { continue }
                    rows.append(y)
                    columns.append(x)
                }
            }
            let top = try XCTUnwrap(rows.min()), bottom = try XCTUnwrap(rows.max())
            let left = try XCTUnwrap(columns.min()), right = try XCTUnwrap(columns.max())
            let centerY = CGFloat(top + bottom) / 2 / scale
            let centerX = CGFloat(left + right) / 2 / scale
            XCTAssertEqual(centerY, seal.bounds.midY, accuracy: 1,
                           "\(value): o dígito não está no meio na vertical")
            XCTAssertEqual(centerX, seal.bounds.midX, accuracy: 1,
                           "\(value): nem na horizontal")
        }
    }

    func testWorkbenchDropsIntoTheProjectUnderTheCursor() throws {
        let (bar, _, _) = sidebar()
        let tiles = bar.cards.flatMap { $0.projects }
        let p1 = try XCTUnwrap(tiles.first { $0.projectID == "p1" })
        let p2 = try XCTUnwrap(tiles.first { $0.projectID == "p2" })

        // Sobre a primeira linha de p1, vindo de fora: cai antes dela.
        let first = p1.rows[0].frame
        XCTAssertEqual(bar.drop(for: .workbench(index: 2), at: NSPoint(x: first.midX, y: first.minY + 2)),
                       .workbench(projectID: "p1", position: 0))
        // Abaixo da última linha de p1: cai no fim.
        let last = p1.rows[p1.rows.count - 1].frame
        XCTAssertEqual(bar.drop(for: .workbench(index: 2), at: NSPoint(x: last.midX, y: last.maxY - 2)),
                       .workbench(projectID: "p1", position: 2))
        // Em outro projeto, o alvo muda de pai: abaixo da linha que ele já
        // tem, entra depois dela.
        let only = p2.rows[0].frame
        XCTAssertEqual(bar.drop(for: .workbench(index: 0), at: NSPoint(x: only.midX, y: only.maxY - 2)),
                       .workbench(projectID: "p2", position: 1))
        XCTAssertEqual(bar.drop(for: .workbench(index: 0), at: NSPoint(x: only.midX, y: only.minY + 2)),
                       .workbench(projectID: "p2", position: 0))
    }

    /// Arrastando para baixo dentro do próprio projeto, a linha que sai não
    /// pode contar como obstáculo — senão ela cai uma posição antes.
    func testMovingDownInsideTheSameProjectDiscountsItself() throws {
        let (bar, _, _) = sidebar()
        let p1 = try XCTUnwrap(bar.cards.flatMap { $0.projects }.first { $0.projectID == "p1" })
        let second = p1.rows[1].frame
        XCTAssertEqual(bar.drop(for: .workbench(index: 0), at: NSPoint(x: second.midX, y: second.maxY - 2)),
                       .workbench(projectID: "p1", position: 1))
        // A mesma queda, vinda de outro projeto, é a posição seguinte.
        XCTAssertEqual(bar.drop(for: .workbench(index: 2), at: NSPoint(x: second.midX, y: second.maxY - 2)),
                       .workbench(projectID: "p1", position: 2))
    }

    /// O laço completo: começar, arrastar e soltar avisa quem move — e a guia
    /// de queda aparece no meio do caminho e some no fim.
    func testDraggingEndsInAMoveAndTheGuideGoesAway() throws {
        let (bar, _, _) = sidebar()
        let p2 = try XCTUnwrap(bar.cards.flatMap { $0.projects }.first { $0.projectID == "p2" })
        var moved: (index: Int, project: String, position: Int)?
        bar.onMoveWorkbench = { index, project, position in moved = (index, project, position) }

        let target = p2.rows[0].frame
        // O arrasto fala em coordenadas de janela; a lista está sob o cabeçalho.
        func inWindow(_ point: NSPoint) -> NSPoint { bar.convert(point, to: nil) }
        let point = inWindow(NSPoint(x: target.midX, y: target.maxY - 2 + Sidebar.headerHeight))
        bar.handle(SidebarDrag(phase: .began, item: .workbench(index: 0), point: point))
        bar.handle(SidebarDrag(phase: .moved, item: .workbench(index: 0), point: point))
        XCTAssertNotNil(bar.dropLine.superview, "a guia aparece enquanto se arrasta")
        XCTAssertNotNil(bar.dragged)

        bar.handle(SidebarDrag(phase: .ended, item: .workbench(index: 0), point: point))
        XCTAssertNil(bar.dropLine.superview, "e some quando solta")
        XCTAssertNil(bar.dragged)
        XCTAssertEqual(moved?.index, 0)
        XCTAssertEqual(moved?.project, "p2")

        // Desistir no meio não move nada.
        moved = nil
        bar.handle(SidebarDrag(phase: .began, item: .workbench(index: 1), point: point))
        bar.handle(SidebarDrag(phase: .cancelled, item: .workbench(index: 1), point: point))
        XCTAssertNil(moved)
        XCTAssertNil(bar.dropLine.superview)
    }

    func testProjectAndWorkspaceTargets() throws {
        let (bar, _, _) = sidebar()
        let w1 = bar.cards[0], w2 = bar.cards[1]

        // Projeto solto sobre o segundo workspace entra nele — abaixo do que
        // ele já tem, na segunda posição.
        let p3 = w2.projects[0].tile.frame
        XCTAssertEqual(bar.drop(for: .project(workspaceID: "w1", id: "p1"),
                                at: NSPoint(x: p3.midX, y: p3.maxY - 2)),
                       .project(workspaceID: "w2", position: 1))
        XCTAssertEqual(bar.drop(for: .project(workspaceID: "w1", id: "p1"),
                                at: NSPoint(x: p3.midX, y: p3.minY + 2)),
                       .project(workspaceID: "w2", position: 0))
        // Sobre o topo do próprio workspace, vai para a primeira posição.
        XCTAssertEqual(bar.drop(for: .project(workspaceID: "w1", id: "p2"),
                                at: NSPoint(x: w1.card.frame.midX, y: w1.projects[0].tile.frame.minY + 2)),
                       .project(workspaceID: "w1", position: 0))

        // Workspace: pela metade do card de baixo, troca de lugar com ele.
        XCTAssertEqual(bar.drop(for: .workspace(id: "w1"),
                                at: NSPoint(x: w2.card.frame.midX, y: w2.card.frame.maxY - 2)),
                       .workspace(position: 1))
        XCTAssertEqual(bar.drop(for: .workspace(id: "w2"),
                                at: NSPoint(x: w1.card.frame.midX, y: w1.card.frame.minY + 2)),
                       .workspace(position: 0))
        // A pilha de órfãs não recebe nem sai do lugar.
        XCTAssertNil(bar.drop(for: .orphans, at: NSPoint(x: 100, y: 100)))
    }
}
