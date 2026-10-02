import Foundation

public struct FuzzyMatch: Equatable {
    public let score: Double
    /// Character offsets into the haystack that matched the needle.
    public let indices: [Int]
}

/// Case-insensitive subsequence matcher with fzy-style scoring: consecutive
/// characters and matches at word starts rank above scattered ones.
public enum Fuzzy {
    public static let exactScore = 100.0

    private static let gapLeading = -0.005
    private static let gapTrailing = -0.005
    private static let gapInner = -0.01
    private static let consecutive = 1.0

    public static func match(_ needle: String, in haystack: String) -> FuzzyMatch? {
        let original = Array(haystack)
        let hay = original.map { $0.lowercased() }
        let pin = needle.map { $0.lowercased() }
        let n = pin.count, m = hay.count

        if n == 0 { return FuzzyMatch(score: 0, indices: []) }
        guard n <= m, isSubsequence(pin, of: hay) else { return nil }
        if n == m { return FuzzyMatch(score: exactScore, indices: Array(0..<m)) }

        let bonus = bonuses(original)
        // best[i][j]: best score matching pin[...i] within hay[...j];
        // ending[i][j]: the same, but with pin[i] matched exactly at hay[j].
        var best = [[Double]](repeating: [Double](repeating: -.infinity, count: m), count: n)
        var ending = best

        for i in 0..<n {
            var previous = -Double.infinity
            let gap = i == n - 1 ? gapTrailing : gapInner
            for j in 0..<m {
                if pin[i] == hay[j] {
                    var score = -Double.infinity
                    if i == 0 {
                        score = Double(j) * gapLeading + bonus[j]
                    } else if j > 0 {
                        score = max(best[i - 1][j - 1] + bonus[j], ending[i - 1][j - 1] + consecutive)
                    }
                    ending[i][j] = score
                    previous = max(score, previous + gap)
                } else {
                    previous += gap
                }
                best[i][j] = previous
            }
        }

        var indices = [Int](repeating: 0, count: n)
        var mustMatch = false
        var j = m - 1
        for i in stride(from: n - 1, through: 0, by: -1) {
            while j >= 0 {
                defer { j -= 1 }
                if ending[i][j] != -.infinity, mustMatch || ending[i][j] == best[i][j] {
                    mustMatch = i > 0 && j > 0 && best[i][j] == ending[i - 1][j - 1] + consecutive
                    indices[i] = j
                    break
                }
            }
        }
        return FuzzyMatch(score: best[n - 1][m - 1], indices: indices)
    }

    private static func isSubsequence(_ pin: [String], of hay: [String]) -> Bool {
        var i = 0
        for character in hay where i < pin.count && character == pin[i] {
            i += 1
        }
        return i == pin.count
    }

    /// Bonus for matching each character, based on what precedes it.
    private static func bonuses(_ characters: [Character]) -> [Double] {
        var previous: Character = "/"
        return characters.map { character in
            defer { previous = character }
            switch previous {
            case "/": return 0.9
            case "-", "_", " ": return 0.8
            case ".": return 0.6
            default: return previous.isLowercase && character.isUppercase ? 0.7 : 0
            }
        }
    }
}
