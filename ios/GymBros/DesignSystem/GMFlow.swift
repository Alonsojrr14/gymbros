import SwiftUI

/// Layout que quebra linha, para chips
struct GMFlow: Layout {
    var spacing: CGFloat = 8

    /// Folga para o arredondamento de pixels: sem ela, a linha mais larga cabia no cálculo da altura e
    /// quebrava na hora de posicionar, e os chips vazavam para fora do quadro
    private let slack: CGFloat = 1

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width - slack, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            row = max(row, s.height)
        }
        // Ocupa a largura oferecida: assim o posicionamento quebra as linhas igual ao cálculo
        return CGSize(width: width.isFinite ? width : maxX, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX - slack, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}
