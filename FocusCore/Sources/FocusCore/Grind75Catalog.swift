import Foundation

/// Grind 75 default 8-week schedule (techinterviewhandbook.org/grind75).
/// Categories are mapped onto `ProblemDomain.swe.categories`.
public struct Grind75Problem: Identifiable, Hashable, Sendable {
    public let slug: String
    public let title: String
    public let difficulty: ProblemDifficulty
    public let categories: [String]
    public let week: Int

    public var id: String { slug }
    public var url: String { "https://leetcode.com/problems/\(slug)/" }
}

public enum Grind75Catalog {
    public static let weekCount = 8

    public static func problems(inWeek week: Int) -> [Grind75Problem] {
        all.filter { $0.week == week }
    }

    public static func problem(slug: String) -> Grind75Problem? {
        all.first { $0.slug == slug }
    }

    /// Matches a logged entry back to the catalog by LeetCode URL slug, falling
    /// back to title so entries typed in before the picker existed still count.
    public static func problem(matching entry: ProblemEntry) -> Grind75Problem? {
        guard entry.domain == .swe else { return nil }
        if let slug = slug(fromURL: entry.url), let p = problem(slug: slug) { return p }
        let t = normalize(entry.title)
        return all.first { normalize($0.title) == t }
    }

    public static func search(_ query: String) -> [Grind75Problem] {
        let q = normalize(query)
        guard !q.isEmpty else { return all }
        let terms = q.split(separator: " ")
        let hits = all.filter { p in
            let hay = normalize(p.title) + " " + p.categories.map(normalize).joined(separator: " ")
            return terms.allSatisfy { hay.contains($0) }
        }
        return hits.sorted { a, b in
            let ap = normalize(a.title).hasPrefix(q), bp = normalize(b.title).hasPrefix(q)
            return ap != bp ? ap : false
        }
    }

    private static func slug(fromURL url: String) -> String? {
        guard let r = url.range(of: "leetcode.com/problems/") else { return nil }
        let rest = url[r.upperBound...]
        let slug = rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        return slug.isEmpty ? nil : String(slug).lowercased()
    }

    private static func normalize(_ s: String) -> String {
        String(s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " })
            .split(separator: " ")
            .joined(separator: " ")
    }

    public static let all: [Grind75Problem] = [
        // Week 1
        .init(slug: "two-sum", title: "Two Sum", difficulty: .easy, categories: ["Arrays & Hashing"], week: 1),
        .init(slug: "valid-parentheses", title: "Valid Parentheses", difficulty: .easy, categories: ["Stack"], week: 1),
        .init(slug: "merge-two-sorted-lists", title: "Merge Two Sorted Lists", difficulty: .easy, categories: ["Linked List"], week: 1),
        .init(slug: "best-time-to-buy-and-sell-stock", title: "Best Time to Buy and Sell Stock", difficulty: .easy, categories: ["Sliding Window"], week: 1),
        .init(slug: "valid-palindrome", title: "Valid Palindrome", difficulty: .easy, categories: ["Two Pointers"], week: 1),
        .init(slug: "invert-binary-tree", title: "Invert Binary Tree", difficulty: .easy, categories: ["Trees"], week: 1),
        .init(slug: "valid-anagram", title: "Valid Anagram", difficulty: .easy, categories: ["Arrays & Hashing"], week: 1),
        .init(slug: "binary-search", title: "Binary Search", difficulty: .easy, categories: ["Binary Search"], week: 1),
        .init(slug: "flood-fill", title: "Flood Fill", difficulty: .easy, categories: ["Graphs"], week: 1),
        .init(slug: "lowest-common-ancestor-of-a-binary-search-tree", title: "Lowest Common Ancestor of a Binary Search Tree", difficulty: .easy, categories: ["Trees"], week: 1),
        .init(slug: "balanced-binary-tree", title: "Balanced Binary Tree", difficulty: .easy, categories: ["Trees"], week: 1),
        .init(slug: "linked-list-cycle", title: "Linked List Cycle", difficulty: .easy, categories: ["Linked List", "Two Pointers"], week: 1),
        .init(slug: "implement-queue-using-stacks", title: "Implement Queue using Stacks", difficulty: .easy, categories: ["Stack"], week: 1),
        // Week 2
        .init(slug: "first-bad-version", title: "First Bad Version", difficulty: .easy, categories: ["Binary Search"], week: 2),
        .init(slug: "ransom-note", title: "Ransom Note", difficulty: .easy, categories: ["Arrays & Hashing"], week: 2),
        .init(slug: "climbing-stairs", title: "Climbing Stairs", difficulty: .easy, categories: ["Dynamic Programming"], week: 2),
        .init(slug: "longest-palindrome", title: "Longest Palindrome", difficulty: .easy, categories: ["Arrays & Hashing", "Greedy"], week: 2),
        .init(slug: "reverse-linked-list", title: "Reverse Linked List", difficulty: .easy, categories: ["Linked List"], week: 2),
        .init(slug: "majority-element", title: "Majority Element", difficulty: .easy, categories: ["Arrays & Hashing"], week: 2),
        .init(slug: "add-binary", title: "Add Binary", difficulty: .easy, categories: ["Bit Manipulation", "Math & Geometry"], week: 2),
        .init(slug: "diameter-of-binary-tree", title: "Diameter of Binary Tree", difficulty: .easy, categories: ["Trees"], week: 2),
        .init(slug: "middle-of-the-linked-list", title: "Middle of the Linked List", difficulty: .easy, categories: ["Linked List", "Two Pointers"], week: 2),
        .init(slug: "maximum-depth-of-binary-tree", title: "Maximum Depth of Binary Tree", difficulty: .easy, categories: ["Trees"], week: 2),
        .init(slug: "contains-duplicate", title: "Contains Duplicate", difficulty: .easy, categories: ["Arrays & Hashing"], week: 2),
        .init(slug: "maximum-subarray", title: "Maximum Subarray", difficulty: .medium, categories: ["Dynamic Programming", "Greedy"], week: 2),
        // Week 3
        .init(slug: "insert-interval", title: "Insert Interval", difficulty: .medium, categories: ["Intervals"], week: 3),
        .init(slug: "01-matrix", title: "01 Matrix", difficulty: .medium, categories: ["Graphs"], week: 3),
        .init(slug: "k-closest-points-to-origin", title: "K Closest Points to Origin", difficulty: .medium, categories: ["Heap"], week: 3),
        .init(slug: "longest-substring-without-repeating-characters", title: "Longest Substring Without Repeating Characters", difficulty: .medium, categories: ["Sliding Window"], week: 3),
        .init(slug: "3sum", title: "3Sum", difficulty: .medium, categories: ["Two Pointers"], week: 3),
        .init(slug: "binary-tree-level-order-traversal", title: "Binary Tree Level Order Traversal", difficulty: .medium, categories: ["Trees"], week: 3),
        .init(slug: "clone-graph", title: "Clone Graph", difficulty: .medium, categories: ["Graphs"], week: 3),
        .init(slug: "evaluate-reverse-polish-notation", title: "Evaluate Reverse Polish Notation", difficulty: .medium, categories: ["Stack"], week: 3),
        // Week 4
        .init(slug: "course-schedule", title: "Course Schedule", difficulty: .medium, categories: ["Graphs"], week: 4),
        .init(slug: "implement-trie-prefix-tree", title: "Implement Trie (Prefix Tree)", difficulty: .medium, categories: ["Tries"], week: 4),
        .init(slug: "coin-change", title: "Coin Change", difficulty: .medium, categories: ["Dynamic Programming"], week: 4),
        .init(slug: "product-of-array-except-self", title: "Product of Array Except Self", difficulty: .medium, categories: ["Arrays & Hashing"], week: 4),
        .init(slug: "min-stack", title: "Min Stack", difficulty: .medium, categories: ["Stack"], week: 4),
        .init(slug: "validate-binary-search-tree", title: "Validate Binary Search Tree", difficulty: .medium, categories: ["Trees"], week: 4),
        .init(slug: "number-of-islands", title: "Number of Islands", difficulty: .medium, categories: ["Graphs"], week: 4),
        .init(slug: "rotting-oranges", title: "Rotting Oranges", difficulty: .medium, categories: ["Graphs"], week: 4),
        // Week 5
        .init(slug: "search-in-rotated-sorted-array", title: "Search in Rotated Sorted Array", difficulty: .medium, categories: ["Binary Search"], week: 5),
        .init(slug: "combination-sum", title: "Combination Sum", difficulty: .medium, categories: ["Backtracking"], week: 5),
        .init(slug: "permutations", title: "Permutations", difficulty: .medium, categories: ["Backtracking"], week: 5),
        .init(slug: "merge-intervals", title: "Merge Intervals", difficulty: .medium, categories: ["Intervals"], week: 5),
        .init(slug: "lowest-common-ancestor-of-a-binary-tree", title: "Lowest Common Ancestor of a Binary Tree", difficulty: .medium, categories: ["Trees"], week: 5),
        .init(slug: "time-based-key-value-store", title: "Time Based Key-Value Store", difficulty: .medium, categories: ["Binary Search"], week: 5),
        .init(slug: "accounts-merge", title: "Accounts Merge", difficulty: .medium, categories: ["Graphs"], week: 5),
        .init(slug: "sort-colors", title: "Sort Colors", difficulty: .medium, categories: ["Two Pointers"], week: 5),
        // Week 6
        .init(slug: "word-break", title: "Word Break", difficulty: .medium, categories: ["Dynamic Programming"], week: 6),
        .init(slug: "partition-equal-subset-sum", title: "Partition Equal Subset Sum", difficulty: .medium, categories: ["Dynamic Programming"], week: 6),
        .init(slug: "string-to-integer-atoi", title: "String to Integer (atoi)", difficulty: .medium, categories: ["Math & Geometry"], week: 6),
        .init(slug: "spiral-matrix", title: "Spiral Matrix", difficulty: .medium, categories: ["Math & Geometry"], week: 6),
        .init(slug: "subsets", title: "Subsets", difficulty: .medium, categories: ["Backtracking"], week: 6),
        .init(slug: "binary-tree-right-side-view", title: "Binary Tree Right Side View", difficulty: .medium, categories: ["Trees"], week: 6),
        .init(slug: "longest-palindromic-substring", title: "Longest Palindromic Substring", difficulty: .medium, categories: ["Dynamic Programming", "Two Pointers"], week: 6),
        .init(slug: "unique-paths", title: "Unique Paths", difficulty: .medium, categories: ["Dynamic Programming"], week: 6),
        .init(slug: "construct-binary-tree-from-preorder-and-inorder-traversal", title: "Construct Binary Tree from Preorder and Inorder Traversal", difficulty: .medium, categories: ["Trees"], week: 6),
        // Week 7
        .init(slug: "container-with-most-water", title: "Container With Most Water", difficulty: .medium, categories: ["Two Pointers"], week: 7),
        .init(slug: "letter-combinations-of-a-phone-number", title: "Letter Combinations of a Phone Number", difficulty: .medium, categories: ["Backtracking"], week: 7),
        .init(slug: "word-search", title: "Word Search", difficulty: .medium, categories: ["Backtracking"], week: 7),
        .init(slug: "find-all-anagrams-in-a-string", title: "Find All Anagrams in a String", difficulty: .medium, categories: ["Sliding Window"], week: 7),
        .init(slug: "minimum-height-trees", title: "Minimum Height Trees", difficulty: .medium, categories: ["Graphs"], week: 7),
        .init(slug: "task-scheduler", title: "Task Scheduler", difficulty: .medium, categories: ["Heap", "Greedy"], week: 7),
        .init(slug: "lru-cache", title: "LRU Cache", difficulty: .medium, categories: ["Linked List", "Arrays & Hashing"], week: 7),
        .init(slug: "kth-smallest-element-in-a-bst", title: "Kth Smallest Element in a BST", difficulty: .medium, categories: ["Trees"], week: 7),
        // Week 8
        .init(slug: "minimum-window-substring", title: "Minimum Window Substring", difficulty: .hard, categories: ["Sliding Window"], week: 8),
        .init(slug: "serialize-and-deserialize-binary-tree", title: "Serialize and Deserialize Binary Tree", difficulty: .hard, categories: ["Trees"], week: 8),
        .init(slug: "trapping-rain-water", title: "Trapping Rain Water", difficulty: .hard, categories: ["Two Pointers", "Stack"], week: 8),
        .init(slug: "find-median-from-data-stream", title: "Find Median from Data Stream", difficulty: .hard, categories: ["Heap"], week: 8),
        .init(slug: "word-ladder", title: "Word Ladder", difficulty: .hard, categories: ["Graphs"], week: 8),
        .init(slug: "basic-calculator", title: "Basic Calculator", difficulty: .hard, categories: ["Stack"], week: 8),
        .init(slug: "maximum-profit-in-job-scheduling", title: "Maximum Profit in Job Scheduling", difficulty: .hard, categories: ["Dynamic Programming", "Binary Search"], week: 8),
        .init(slug: "merge-k-sorted-lists", title: "Merge k Sorted Lists", difficulty: .hard, categories: ["Heap", "Linked List"], week: 8),
        .init(slug: "largest-rectangle-in-histogram", title: "Largest Rectangle in Histogram", difficulty: .hard, categories: ["Stack"], week: 8),
    ]
}
