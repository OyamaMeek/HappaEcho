import XCTest
@testable import HappaEcho

final class MessageRenderingTests: XCTestCase {
    func testParserRecognizesMultilineDisplayMath() {
        let document = MessageDocumentParser().parse("""
        Before
        $$
        r_1=0.03\\mathrm{m},\\qquad r_2=0.06\\mathrm{m}
        $$
        After
        """)

        XCTAssertEqual(document.nodes, [
            .paragraph("Before"),
            .displayMath("r_1=0.03\\mathrm{m},\\qquad r_2=0.06\\mathrm{m}"),
            .paragraph("After")
        ])
    }

    func testLatexRendererRendersCommandsInsteadOfReturningRawSource() {
        let result = LaTeXRenderer().render("r_1=0.03\\mathrm{m},\\qquad r_2=0.06\\mathrm{m}", displayMode: true)

        switch result {
        case .success:
            break
        case .failure:
            XCTFail("LaTex commands should render instead of falling back to raw source")
        }
    }
}
