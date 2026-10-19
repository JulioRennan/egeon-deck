import AppKit
import XCTest
@testable import EgeonDeck

/// Link no chat: `[rótulo](url)` mostra o rótulo e leva a URL; URL solta vira
/// link; o resto continua texto.
final class MarkdownLinkTests: XCTestCase {
    private func links(_ text: NSAttributedString) -> [(String, URL)] {
        var out: [(String, URL)] = []
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let url = value as? URL { out.append(((text.string as NSString).substring(with: range), url)) }
        }
        return out
    }

    func testMarkdownLinkShowsLabelAndCarriesURL() {
        XCTAssertEqual(MarkdownLite.spans("veja [o PR](https://github.com/a/b/pull/1) agora"),
                       [.text("veja "), .link(label: "o PR", url: "https://github.com/a/b/pull/1"), .text(" agora")])
        let rendered = MarkdownLite.render("veja [o PR](https://x.dev/p)", font: .systemFont(ofSize: 13), color: .white)
        XCTAssertEqual(rendered.string, "veja o PR")
        XCTAssertEqual(links(rendered).map(\.0), ["o PR"])
    }

    func testBracketsWithoutSchemeStayText() {
        XCTAssertEqual(MarkdownLite.spans("[1](2) e [a] (b)"), [.text("[1](2) e [a] (b)")])
    }

    func testBareURLBecomesLink() {
        let plain = NSAttributedString(string: "abre http://localhost:3000/x e https://x.dev.")
        let found = links(MarkdownLite.linkify(plain))
        XCTAssertEqual(found.map(\.0), ["http://localhost:3000/x", "https://x.dev"])
    }

    func testLinkifyKeepsExistingLink() {
        let rendered = MarkdownLite.render("[docs](https://x.dev/a)", font: .systemFont(ofSize: 13), color: .white)
        XCTAssertEqual(links(MarkdownLite.linkify(rendered)).map(\.1.absoluteString), ["https://x.dev/a"])
    }
}
