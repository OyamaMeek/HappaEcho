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

    func testParserRecognizesBracketDelimitedDisplayMath() {
        let document = MessageDocumentParser().parse("""
        设第 (i) 行塔的座数为 \\(a_i\\)。
        \\[
        \\frac{6(2b+5d)}{2}=108
        \\]
        """)

        XCTAssertEqual(document.nodes, [
            .paragraph("设第 (i) 行塔的座数为 \\(a_i\\)。"),
            .displayMath("\\frac{6(2b+5d)}{2}=108")
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

    func testInlineLatexIsConvertedBeforeMarkdownRendering() {
        let rendered = LaTeXTextFormatter().formatInlineMath(
            in: "椭圆为 \\(x^2/25+y^2/9=1\\)，焦点为 \\(\\pm4,0\\)，离心率为 \\(\\frac45\\)。"
        )

        XCTAssertEqual(rendered, "椭圆为 x²/25+y²/9=1，焦点为 ±4,0，离心率为 4⁄5。")
    }
}
