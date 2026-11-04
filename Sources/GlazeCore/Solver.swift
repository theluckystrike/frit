import Foundation

/// Small linear solvers for Oxide Nudge and Replace Material (`Reformulate`).
public enum Solver {
    /// Non-negative least squares (Lawson and Hanson, "Solving Least Squares Problems", 1974, chapter 23).
    ///
    /// Finds `x >= 0` that minimizes the sum over rows i of (weights[i] x (a[i] · x − b[i]))².
    /// `a` has one row per equation and one column per unknown. `weights` multiplies each row; an empty array,
    /// or one of the wrong length, means a weight of 1 for every row. Made for small problems (about 20 unknowns).
    /// Returns an array of zeros when the input is empty, ragged or not finite.
    public static func nnls(_ a: [[Double]], _ b: [Double], weights: [Double]) -> [Double] {
        let m = a.count
        let n = a.first?.count ?? 0
        guard m > 0, n > 0, b.count == m, a.allSatisfy({ $0.count == n }),
              a.allSatisfy({ $0.allSatisfy(\.isFinite) }), b.allSatisfy(\.isFinite) else {
            return Array(repeating: 0, count: n)
        }
        let w = weights.count == m && weights.allSatisfy({ $0.isFinite && $0 >= 0 }) ? weights : Array(repeating: 1, count: m)

        // Weighted system, stored by column.
        var cols = [[Double]](repeating: [Double](repeating: 0, count: m), count: n)
        for i in 0..<m { for j in 0..<n { cols[j][i] = a[i][j] * w[i] } }
        let rhs = (0..<m).map { b[$0] * w[$0] }

        let scale = cols.map { $0.reduce(0) { $0 + abs($1) } }.max() ?? 1
        let tol = 1e-12 * max(scale, 1) * Double(max(m, n))

        var x = [Double](repeating: 0, count: n)
        var passive = [Bool](repeating: false, count: n)
        // Columns that gave no progress when added (degenerate); not tried again in this solve.
        var blocked = [Bool](repeating: false, count: n)

        func gradient() -> [Double] {
            var r = rhs
            for j in 0..<n where x[j] != 0 { for i in 0..<m { r[i] -= cols[j][i] * x[j] } }
            return (0..<n).map { j in (0..<m).reduce(0) { $0 + cols[j][$1] * r[$1] } }
        }

        func solvePassive() -> [Double] {
            let set = (0..<n).filter { passive[$0] }
            let s = leastSquares(columns: set.map { cols[$0] }, rhs: rhs)
            var z = [Double](repeating: 0, count: n)
            for (k, j) in set.enumerated() { z[j] = s[k] }
            return z
        }

        var outer = 0
        while outer < 10 * n + 20 {
            outer += 1
            let g = gradient()
            var best = -1
            var bestValue = tol
            for j in 0..<n where !passive[j] && !blocked[j] && g[j] > bestValue {
                best = j
                bestValue = g[j]
            }
            guard best >= 0 else { break }
            passive[best] = true
            var z = solvePassive()
            if z[best] <= 0 {
                // Degenerate: the column cannot enter with a positive value. Skip it until x changes.
                passive[best] = false
                blocked[best] = true
                continue
            }
            var inner = 0
            while inner < 3 * n + 10 {
                inner += 1
                let set = (0..<n).filter { passive[$0] }
                if set.allSatisfy({ z[$0] > 0 }) {
                    x = z
                    break
                }
                // Step from x toward z until the first passive value reaches 0, then drop it from the set.
                var alpha = 1.0
                for j in set where z[j] <= 0 {
                    let d = x[j] - z[j]
                    if d > 0 { alpha = min(alpha, x[j] / d) }
                }
                for j in 0..<n { x[j] += alpha * (z[j] - x[j]) }
                for j in set where x[j] <= tol {
                    x[j] = 0
                    passive[j] = false
                }
                z = solvePassive()
            }
            blocked = [Bool](repeating: false, count: n)
        }
        return x.map { $0 > 0 && $0.isFinite ? $0 : 0 }
    }

    /// Least squares by Householder QR with column pivoting.
    /// At each step the column with the largest remaining norm goes next, so a column that depends on the
    /// columns before it is left to the end and gets the value 0. The independent columns after it still get
    /// their values (L7 C6: without pivoting, a dependent column early in the set made later columns 0).
    static func leastSquares(columns input: [[Double]], rhs: [Double]) -> [Double] {
        let k = input.count
        guard k > 0 else { return [] }
        let m = rhs.count
        var c = input
        var b = rhs
        var perm = Array(0..<k)
        let norm = c.map { $0.reduce(0) { $0 + $1 * $1 }.squareRoot() }.max() ?? 0
        let tol = 1e-12 * max(norm, 1)
        var rank = 0
        for j in 0..<min(k, m) {
            // Pivot: the remaining column with the largest norm in rows j..<m.
            var best = j
            var bestNorm = -1.0
            for col in j..<k {
                let s = (j..<m).reduce(0) { $0 + c[col][$1] * c[col][$1] }
                if s > bestNorm { bestNorm = s; best = col }
            }
            if best != j { c.swapAt(j, best); perm.swapAt(j, best) }
            let len = bestNorm.squareRoot()
            if len <= tol { break }
            let alpha = c[j][j] > 0 ? -len : len
            var v = [Double](repeating: 0, count: m)
            for i in j..<m { v[i] = c[j][i] }
            v[j] -= alpha
            let vv = (j..<m).reduce(0) { $0 + v[$1] * v[$1] }
            if vv == 0 { break }
            for col in j..<k {
                let dot = (j..<m).reduce(0) { $0 + v[$1] * c[col][$1] }
                let f = 2 * dot / vv
                for i in j..<m { c[col][i] -= f * v[i] }
            }
            let dot = (j..<m).reduce(0) { $0 + v[$1] * b[$1] }
            let f = 2 * dot / vv
            for i in j..<m { b[i] -= f * v[i] }
            rank = j + 1
        }
        var s = [Double](repeating: 0, count: k)
        for j in stride(from: rank - 1, through: 0, by: -1) {
            var sum = b[j]
            for col in (j + 1)..<rank { sum -= c[col][j] * s[col] }
            s[j] = sum / c[j][j]
        }
        var out = [Double](repeating: 0, count: k)
        for j in 0..<k { out[perm[j]] = s[j] }
        return out
    }
}
