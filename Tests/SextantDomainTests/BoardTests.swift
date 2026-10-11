import CoreGraphics
import SextantDomain
import Testing

struct BoardTests {
    let geo = BoardGeometry.voyager

    @Test func matrixMapsToOryxIndex() {
        let board = BoardDefinition.voyager
        #expect(board.keyCount == 52)
        #expect(board.keyIndex(matrixRow: 0, column: 1) == 0)
        #expect(board.keyIndex(matrixRow: 5, column: 0) == 24)
        #expect(board.keyIndex(matrixRow: 10, column: 2) == 44)
        #expect(board.keyIndex(matrixRow: 11, column: 6) == 51)
        #expect(board.keyIndex(matrixRow: 0, column: 0) == nil)
        #expect(board.layoutOrder.count == 52 && Set(board.layoutOrder) == Set(0..<52))
    }

    @Test func staggerAndThumbs() {
        #expect(abs(geo.key(3).center.y - geo.key(0).center.y + 0.30) < 0.001)
        #expect(abs(geo.key(2).center.y - geo.key(0).center.y + 0.15) < 0.001)
        #expect(abs(geo.key(28).center.y - geo.key(3).center.y) < 0.001, "the right half mirrors the stagger")
        #expect(geo.key(24).rotation == 30 && geo.key(25).rotation == 30)
        #expect(geo.key(50).rotation == -30 && geo.key(51).rotation == -30)
        #expect(geo.key(25).size.height > geo.key(24).size.height, "inner thumbs are taller")
        #expect(abs(geo.bounds.width - 15.0) < 0.6, "about 15 pitch units wide (spec §4.1)")
    }

    @Test func noCapsOverlap() {
        let layout = geo.layout(keySize: 50, spacing: 5.5)
        for a in layout.frames {
            for b in layout.frames where b.index > a.index {
                #expect(!overlaps(a.corners, b.corners), "keys \(a.index) and \(b.index) overlap")
            }
        }
    }

    @Test func navigationAndHitTesting() {
        #expect(geo.neighbor(of: 5, toward: .right) == 26)
        #expect(geo.neighbor(of: 23, toward: .down) == 24)
        #expect(geo.neighbor(of: 16, toward: .up) == 10)
        let points = geo.layout(keySize: 50, spacing: 5.5)
        #expect(points.keyIndex(at: points.frame(25).center) == 25)
    }

    /// Separating-axis test for two convex quads.
    private func overlaps(_ a: [CGPoint], _ b: [CGPoint]) -> Bool {
        for poly in [a, b] {
            for i in poly.indices {
                let p1 = poly[i], p2 = poly[(i + 1) % poly.count]
                let axis = CGPoint(x: p2.y - p1.y, y: p1.x - p2.x)
                let pa = a.map { $0.x * axis.x + $0.y * axis.y }, pb = b.map { $0.x * axis.x + $0.y * axis.y }
                if pa.max()! <= pb.min()! + 0.01 || pb.max()! <= pa.min()! + 0.01 { return false }
            }
        }
        return true
    }
}
