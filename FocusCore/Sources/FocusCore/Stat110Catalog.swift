import Foundation

// MARK: - Catalog types

/// A single problem from the Stat 110 problem sets (Joe Blitzstein, Harvard).
/// Each homework PDF contains two parallel sets: "Strategic Practice"
/// (grouped by topic, never graded — for warm-up) and "Homework" (the
/// actual numbered turn-in problems). We surface both as pickable items
/// because the user wants to log either kind as a homework problem.
/// One progressive hint step for a Stat 110 problem. Multiple steps form
/// the user's reveal path: peek once for step 1, peek again for step 2,
/// continue all the way to the full solution. Each step's `body` supports
/// `$inline$` and `$$display$$` LaTeX math (rendered via KaTeX in MathView).
public struct SolutionStep: Hashable, Sendable {
    /// Short label shown above the step body (e.g. "Set up", "Apply Bayes",
    /// "Solve the recurrence", or "Full solution"). Empty string OK.
    public let title: String
    /// Step text. Use `$...$` for inline math and `$$...$$` for displayed.
    /// Standard LaTeX commands work — `\frac`, `\binom`, `\sum`, etc.
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public struct Stat110Problem: Identifiable, Hashable, Sendable {
    /// Stable string identifier so we can mark this problem "done" in the
    /// homework store regardless of how the user edits the title.
    /// Format: `stat110-hw{N}-{sp|hw}-{number}`
    /// Examples: `stat110-hw2-sp-1.1`, `stat110-hw2-hw-3`
    public let id: String
    public let setNumber: Int        // e.g. 2 for HW2
    public let kind: Kind
    /// Topic header (Strategic Practice only — Homework problems aren't
    /// grouped by topic in Blitzstein's PDFs).
    public let topic: String?
    /// As printed in the PDF: "1", "3", "1.2", etc.
    public let number: String
    /// Short human-readable summary of the problem.
    public let title: String

    /// Full verbatim problem statement from the original PDF, lightly
    /// cleaned (the source has some encoding glitches: "o↵" → "off",
    /// "1 p" → "1-p", etc.). Empty string if not yet transcribed.
    public let body: String

    /// The FIRST LINE of Blitzstein's solution — kept for backwards
    /// compat. When `solutionSteps` is non-empty, the UI uses those
    /// instead. When empty, this is shown as the only hint.
    public let firstLineHint: String

    /// Progressive solution steps — peek once for step 1, peek again
    /// for step 2, all the way to the full solution. Supports inline
    /// `$...$` and display `$$...$$` LaTeX math via KaTeX.
    ///
    /// Empty array means "no progressive solution available" — fall
    /// back to `firstLineHint` for a single reveal.
    public let solutionSteps: [SolutionStep]

    /// Subjective 1-5 rating of how useful this problem is for quant
    /// interview prep (Jane Street / Citadel / Two Sigma style). 5 = a
    /// canonical interview problem family; 1 = narrative or
    /// niche. Rationale in `quantRationale`.
    public let quantRelevance: Int

    /// One-line explanation for why the relevance rating is what it is —
    /// surfaces in the UI so the user knows what to prioritize.
    public let quantRationale: String

    /// Final answer as printed in Blitzstein's official solutions handout.
    /// Concise: the key result plus minimal justification — NOT a full
    /// derivation, since the point is self-checking after the user has
    /// solved it themselves. Supports `$...$` / `$$...$$` LaTeX via KaTeX.
    /// Empty string if not yet transcribed for this problem.
    public let answer: String

    public enum Kind: String, Hashable, Sendable {
        case strategicPractice
        case homework

        public var label: String {
            switch self {
            case .strategicPractice: return "Strategic Practice"
            case .homework:          return "Homework"
            }
        }
    }

    public var sourceLabel: String {
        var s = "Stat 110 HW\(setNumber) \(kind.label) \(number)"
        if let topic { s += " — \(topic)" }
        return s
    }

    /// Memberwise init with sensible defaults so we can add metadata
    /// progressively without forcing every call site to pass everything.
    public init(id: String,
                setNumber: Int,
                kind: Kind,
                topic: String? = nil,
                number: String,
                title: String,
                body: String = "",
                firstLineHint: String = "",
                solutionSteps: [SolutionStep] = [],
                quantRelevance: Int = 3,
                quantRationale: String = "",
                answer: String = "") {
        self.id = id
        self.setNumber = setNumber
        self.kind = kind
        self.topic = topic
        self.number = number
        self.title = title
        self.body = body
        self.firstLineHint = firstLineHint
        self.solutionSteps = solutionSteps
        self.quantRelevance = quantRelevance
        self.quantRationale = quantRationale
        self.answer = answer
    }
}

public struct Stat110ProblemSet: Identifiable, Hashable, Sendable {
    public var id: Int { setNumber }
    public let setNumber: Int
    public let title: String          // "Strategic Practice & Homework 2"
    public let pdfURL: String
    public let problems: [Stat110Problem]

    public var strategicPractice: [Stat110Problem] {
        problems.filter { $0.kind == .strategicPractice }
    }
    public var homework: [Stat110Problem] {
        problems.filter { $0.kind == .homework }
    }

    /// Strategic-practice problems grouped by topic, preserving declaration order.
    public var spByTopic: [(topic: String, items: [Stat110Problem])] {
        var seen: [String: Int] = [:]
        var order: [String] = []
        for p in strategicPractice where p.topic != nil {
            if seen[p.topic!] == nil {
                seen[p.topic!] = order.count
                order.append(p.topic!)
            }
        }
        return order.map { t in
            (topic: t, items: strategicPractice.filter { $0.topic == t })
        }
    }
}

public enum Stat110Catalog {
    public static let all: [Stat110ProblemSet] = [hw1, hw2, hw3, hw4]

    public static func problemSet(number: Int) -> Stat110ProblemSet? {
        all.first { $0.setNumber == number }
    }

    public static func problem(id: String) -> Stat110Problem? {
        for set in all {
            if let p = set.problems.first(where: { $0.id == id }) { return p }
        }
        return nil
    }
}

// MARK: - HW1 (Fall 2011)
// Source: https://stat110.hsites.harvard.edu/sites/g/files/omnuum10111/files/stat110/files/strategic_practice_and_homework_1-2.pdf

private let hw1: Stat110ProblemSet = .init(
    setNumber: 1,
    title: "Strategic Practice & Homework 1",
    pdfURL: "https://stat110.hsites.harvard.edu/sites/g/files/omnuum10111/files/stat110/files/strategic_practice_and_homework_1-2.pdf",
    problems: [
        // --- Strategic Practice 1 ---
        .init(
            id: "stat110-hw1-sp-1a", setNumber: 1, kind: .strategicPractice,
            topic: "Naive Definition of Probability", number: "1(a)",
            title: "P(four-dice total = 21) vs 22",
            body: "Decide whether the blank should be filled in with $=$, $<$, or $>$, and give a short but clear explanation.\n\n(probability that the total after rolling 4 fair dice is 21) ___ (probability that the total after rolling 4 fair dice is 22)",
            firstLineHint: "All ordered outcomes are equally likely. Count permutations giving sum 21 vs sum 22.",
            quantRelevance: 3,
            quantRationale: "Combinatorics warm-up — counting ordered outcomes carefully.",
            answer: "$>$. To get a 21, the outcome must be a permutation of $(6,6,6,3)$ (4 possibilities), $(6,5,5,5)$ (4 possibilities), or $(6,6,5,4)$ ($4!/2 = 12$ possibilities) — total 20 ways. To get a 22, the outcome must be a permutation of $(6,6,6,4)$ (4 possibilities) or $(6,6,5,5)$ ($4!/2^2 = 6$ possibilities) — total 10 ways. So $P(21)$ is exactly twice $P(22)$."),
        .init(
            id: "stat110-hw1-sp-1b", setNumber: 1, kind: .strategicPractice,
            topic: "Naive Definition of Probability", number: "1(b)",
            title: "P(2-letter palindrome) vs 3-letter palindrome",
            body: "(probability that a random 2 letter word is a palindrome) ___ (probability that a random 3 letter word is a palindrome)\n\nA palindrome is an expression that reads the same backwards as forwards (ignoring spaces and punctuation). Assume that all words of the specified length are equally likely, and that the alphabet consists of the lowercase letters $a, b, \\ldots, z$.",
            firstLineHint: "Being a palindrome means first letter = last letter, regardless of the middle.",
            quantRelevance: 2,
            quantRationale: "Quick symmetry argument — useful warm-up for thinking about constraints vs sample size.",
            answer: "$=$. For both 2-letter and 3-letter words, being a palindrome means that the first and last letter are the same. The middle letter (in 3-letter case) is free."),
        .init(
            id: "stat110-hw1-sp-2", setNumber: 1, kind: .strategicPractice,
            topic: "Naive Definition of Probability", number: "2",
            title: "Poker: flush and two pair",
            body: "A random 5 card poker hand is dealt from a standard deck of cards. Find the probability of each of the following (in terms of binomial coefficients).\n\n(a) A flush (all 5 cards being of the same suit; do not count a royal flush, which is a flush with an Ace, King, Queen, Jack, and 10)\n\n(b) Two pair (e.g., two 3's, two 7's, and an Ace)",
            firstLineHint: "(a) 4 suits × ($\\binom{13}{5}-1$ non-royal hands per suit) / $\\binom{52}{5}$. (b) Pick 2 ranks for pairs, 2 cards from each rank, 1 from the 44 cards outside both ranks.",
            quantRelevance: 4,
            quantRationale: "Poker combinatorics — interviewers like this for careful enumeration.",
            answer: "**(a)** A flush can occur in any of the 4 suits; there are $\\binom{13}{5}$ ways to choose the cards in that suit, except for one way to have a royal flush in that suit. So\n$$P(\\text{flush}) = \\frac{4\\left(\\binom{13}{5} - 1\\right)}{\\binom{52}{5}}.$$\n\n**(b)** Choose the two ranks of the pairs, then which specific cards to have for those 4 cards, then the extraneous card (any of the $52 - 8 = 44$ cards not of the two chosen ranks):\n$$P(\\text{two pair}) = \\frac{\\binom{13}{2} \\binom{4}{2}^2 \\cdot 44}{\\binom{52}{5}}.$$"),
        .init(
            id: "stat110-hw1-sp-3", setNumber: 1, kind: .strategicPractice,
            topic: "Naive Definition of Probability", number: "3",
            title: "Lattice paths to (110, 111)",
            body: "(a) How many paths are there from the point $(0, 0)$ to the point $(110, 111)$ in the plane such that each step either consists of going one unit up or one unit to the right?\n\n(b) How many paths are there from $(0, 0)$ to $(210, 211)$, where each step consists of going one unit up or one unit to the right, and the path has to go through $(110, 111)$?",
            firstLineHint: "Encode a path as a sequence of $U$'s and $R$'s; to $(110,111)$ requires 110 R's and 111 U's.",
            quantRelevance: 4,
            quantRationale: "Lattice paths + multiplication rule — interview combinatorics.",
            answer: "**(a)** $\\binom{221}{110}$. (Encode the path as a sequence of $U$ and $R$ moves: 110 R's and 111 U's, determine where the R's go.)\n\n**(b)** $\\binom{221}{110} \\cdot \\binom{200}{100}$. (From $(110,111)$ to $(210,211)$ requires 100 R's and 100 U's. Multiply by paths to $(110,111)$.)"),
        .init(
            id: "stat110-hw1-sp-4", setNumber: 1, kind: .strategicPractice,
            topic: "Naive Definition of Probability", number: "4",
            title: "Norepeatword ≈ 1/e",
            body: "A *norepeatword* is a sequence of at least one (and possibly all) of the usual 26 letters $a, b, c, \\ldots, z$, with repetitions not allowed. For example, \"course\" is a norepeatword, but \"statistics\" is not. Order matters, e.g., \"course\" is not the same as \"source\".\n\nA norepeatword is chosen randomly, with all norepeatwords equally likely. Show that the probability that it uses all 26 letters is very close to $1/e$.",
            firstLineHint: "Count norepeatwords of length $k$ as $\\binom{26}{k} k!$; sum over $k$.",
            quantRelevance: 4,
            quantRationale: "Beautiful connection between combinatorics and $e$ — Stirling-flavored.",
            answer: "Norepeatwords with $k$ letters: $\\binom{26}{k} k!$ for $k = 1, \\ldots, 26$. So\n$$P = \\frac{26!}{\\sum_{k=1}^{26} \\binom{26}{k} k!} = \\frac{1}{\\frac{1}{25!} + \\frac{1}{24!} + \\cdots + \\frac{1}{1!} + 1}.$$\nThe denominator is the first 26 terms of the Taylor series $e^x = 1 + x + x^2/2! + \\cdots$ at $x = 1$. So $P \\approx 1/e$ — the approximation error is less than $10^{-26}$."),
        .init(
            id: "stat110-hw1-sp-5", setNumber: 1, kind: .strategicPractice,
            topic: "Story Proofs", number: "5",
            title: "Story proof: $\\sum_k \\binom{n}{k} = 2^n$",
            body: "Give a story proof that $\\sum_{k=0}^{n} \\binom{n}{k} = 2^n$.",
            firstLineHint: "Count subsets of $n$ people two ways.",
            quantRelevance: 4,
            quantRationale: "Simplest story proof — interviewers test the *technique* of two-way counting.",
            answer: "Count subsets of an $n$-element set two ways. **One way:** group by size — $\\binom{n}{k}$ subsets of size $k$, total $\\sum_k \\binom{n}{k}$. **Other way:** each element is independently in or out — $2^n$ subsets. The two counts must agree."),
        .init(
            id: "stat110-hw1-sp-6", setNumber: 1, kind: .strategicPractice,
            topic: "Story Proofs", number: "6",
            title: "Partnerships: $(2n)!/(2^n n!) = (2n-1)!!$",
            body: "Give a story proof that\n$$\\frac{(2n)!}{2^n \\cdot n!} = (2n - 1)(2n - 3) \\cdots 3 \\cdot 1.$$",
            firstLineHint: "Count ways to pair up $2n$ people into $n$ partnerships.",
            quantRelevance: 4,
            quantRationale: "Partnership counting — appears in genetics, scheduling, matching problems.",
            answer: "Take $2n$ people; count the partnerships (unordered set of $n$ pairs).\n\n**One way:** line them up in a row ($(2n)!$ orderings) and say the first two are a pair, next two are a pair, etc. This overcounts by $2^n n!$ (order of pairs $n!$, order within each pair $2^n$).\n\n**Other way:** pick person 1's partner ($2n - 1$ choices), then person 2's or 3's partner ($2n - 3$ choices), etc. Product: $(2n-1)(2n-3)\\cdots 3 \\cdot 1$."),
        .init(
            id: "stat110-hw1-sp-7", setNumber: 1, kind: .strategicPractice,
            topic: "Story Proofs", number: "7",
            title: "Pascal's rule, two ways",
            body: "Show that for all positive integers $n$ and $k$ with $n \\geq k$,\n$$\\binom{n}{k} + \\binom{n}{k-1} = \\binom{n+1}{k},$$\ndoing this in two ways: (a) algebraically and (b) with a \"story\", giving an interpretation for why both sides count the same thing.\n\n*Hint for the \"story\" proof:* imagine $n + 1$ people, with one of them pre-designated as \"president\".",
            firstLineHint: "Story: RHS counts $k$-subsets of $n+1$ people. LHS splits by whether the president is in the subset.",
            quantRelevance: 4,
            quantRationale: "Pascal's rule is THE foundational combinatorial identity.",
            answer: "**Algebraic:**\n$$\\binom{n}{k} + \\binom{n}{k-1} = \\frac{n!}{k!(n-k)!} + \\frac{n!}{(k-1)!(n-k+1)!} = \\frac{(n-k+1)n! + k \\cdot n!}{k!(n-k+1)!} = \\frac{(n+1)!}{k!(n+1-k)!} = \\binom{n+1}{k}.$$\n\n**Story:** RHS = ways to pick a $k$-subgroup from $n+1$ people. Split LHS by whether the pre-designated \"president\" is in the chosen group: (i) president in — $\\binom{n}{k-1}$ ways for the rest; (ii) president out — $\\binom{n}{k}$ ways. Sum gives total."),

        // --- Homework 1 ---
        .init(
            id: "stat110-hw1-hw-1", setNumber: 1, kind: .homework,
            topic: nil, number: "1",
            title: "3 eldest of 6 children are all girls",
            body: "A certain family has 6 children, consisting of 3 boys and 3 girls. Assuming that all birth orders are equally likely, what is the probability that the 3 eldest children are the 3 girls?",
            firstLineHint: "$\\binom{6}{3}$ ways to place the girls among 6 positions; only 1 places them first.",
            quantRelevance: 3,
            quantRationale: "Symmetry / equally-likely-positions — interviewer warm-up.",
            answer: "$P = \\frac{(3!)^2}{6!} = \\frac{1}{20} = 0.05$. Equivalently, choose 3 of 6 birth-order positions for the girls ($\\binom{6}{3} = 20$ ways); only one places them in positions 1–3."),
        .init(
            id: "stat110-hw1-hw-2", setNumber: 1, kind: .homework,
            topic: nil, number: "2",
            title: "Split 12 people into teams",
            body: "(a) How many ways are there to split a dozen people into 3 teams, where one team has 2 people, and the other two teams have 5 people each?\n\n(b) How many ways are there to split a dozen people into 3 teams, where each team has 4 people?",
            firstLineHint: "(a) Pick the 2-team, then split the remaining 10 in half (no designated first team of 5). (b) Multinomial $\\frac{12!}{4!4!4!}$, divided by $3!$ since the teams aren't labeled.",
            quantRelevance: 4,
            quantRationale: "Multinomial coefficients + correcting for unlabeled groups — interview material.",
            answer: "**(a)** $\\frac{\\binom{12}{2}\\binom{10}{5}}{2} = 8316$. Pick 2 of 12 for the 2-team, $\\binom{10}{5}$ for the first team of 5, divided by 2 since the two teams of 5 are interchangeable.\n\n**(b)** $\\frac{12!}{4!^3 \\cdot 3!} = 5775$. Multinomial $\\frac{12!}{4!^3}$ counts labeled-teams; divide by $3!$ since the three teams of 4 are interchangeable."),
        .init(
            id: "stat110-hw1-hw-3", setNumber: 1, kind: .homework,
            topic: nil, number: "3",
            title: "Scheduling conflict — 3 of 10 slots",
            body: "A college has 10 (non-overlapping) time slots for its courses, and blithely assigns courses to time slots randomly and independently. A student randomly chooses 3 of the courses to enroll in (for the PTP, to avoid getting fined). What is the probability that there is a conflict in the student's schedule?",
            firstLineHint: "Easier to compute the complement: $P(\\text{no conflict}) = \\frac{10 \\cdot 9 \\cdot 8}{10^3}$.",
            quantRelevance: 4,
            quantRationale: "Birthday-paradox style — compute via complement. Interview canon.",
            answer: "$P(\\text{conflict}) = 1 - \\frac{10 \\cdot 9 \\cdot 8}{10^3} = 1 - 0.72 = 0.28$. The numerator counts assignments where the three courses get distinct slots."),
        .init(
            id: "stat110-hw1-hw-4", setNumber: 1, kind: .homework,
            topic: nil, number: "4",
            title: "Some district has more than 1 robbery",
            body: "A city with 6 districts has 6 robberies in a particular week. Assume the robberies are located randomly, with all possibilities for which robbery occurred where equally likely. What is the probability that some district had more than 1 robbery?",
            firstLineHint: "Complement: $P(\\text{each district has exactly 1}) = 6!/6^6$.",
            quantRelevance: 4,
            quantRationale: "Pigeonhole / complement / birthday-problem cousin — surprising result.",
            answer: "$P = 1 - \\frac{6!}{6^6} \\approx 0.9846$. This also says: if a fair die is rolled 6 times, there's over a 98% chance that some value is repeated."),
        .init(
            id: "stat110-hw1-hw-5", setNumber: 1, kind: .homework,
            topic: nil, number: "5",
            title: "Capture-recapture (Hypergeometric)",
            body: "Elk dwell in a certain forest. There are $N$ elk, of which a simple random sample of size $n$ are captured and tagged (\"simple random sample\" means that all $\\binom{N}{n}$ sets of $n$ elk are equally likely). The captured elk are returned to the population, and then a new sample is drawn, this time with size $m$. This is an important method that is widely-used in ecology, known as *capture-recapture*.\n\nWhat is the probability that exactly $k$ of the $m$ elk in the new sample were previously tagged? (Assume that an elk that was captured before doesn't become more or less likely to be captured again.)",
            firstLineHint: "Hypergeometric: choose $k$ tagged of $n$ and $m-k$ untagged of $N-n$, over $\\binom{N}{m}$ total samples.",
            quantRelevance: 5,
            quantRationale: "Hypergeometric distribution — fundamental quant distribution, appears in Fisher exact test and many trading-card / urn problems.",
            answer: "$$P = \\frac{\\binom{n}{k} \\binom{N-n}{m-k}}{\\binom{N}{m}}$$\nfor $0 \\leq k \\leq n$ and $0 \\leq m - k \\leq N - n$, and 0 otherwise. This is a **Hypergeometric** probability."),
        .init(
            id: "stat110-hw1-hw-6", setNumber: 1, kind: .homework,
            topic: nil, number: "6",
            title: "Jar of r red, g green — second-draw symmetry",
            body: "A jar contains $r$ red balls and $g$ green balls, where $r$ and $g$ are fixed positive integers. A ball is drawn from the jar randomly (with all possibilities equally likely), and then a second ball is drawn randomly.\n\n(a) Explain intuitively why the probability of the second ball being green is the same as the probability of the first ball being green.\n\n(b) Define notation for the sample space of the problem, and use this to compute the probabilities from (a) and show that they are the same.\n\n(c) Suppose that there are 16 balls in total, and that the probability that the two balls are the same color is the same as the probability that they are different colors. What are $r$ and $g$ (list all possibilities)?",
            firstLineHint: "(a) Symmetry: ball positions 1 and 2 are interchangeable. (c) $P(\\text{same}) = P(\\text{diff}) = 1/2$ gives $(g-r)^2 = g + r = 16$.",
            quantRelevance: 5,
            quantRationale: "Symmetry argument + a quadratic constraint problem. Urn-problem interview material.",
            answer: "**(a)** By symmetry, the second ball is just as likely as the first to be any of the $g + r$ balls. So $P(G_2) = g/(g+r) = P(G_1)$.\n\n**(b)** Sample space = ordered pairs $(a, b)$ with $a \\neq b$, both in $\\{1, \\ldots, g+r\\}$. Denominator $(g+r)(g+r-1)$. Numerator for $G_i$ is $g(g+r-1)$ in each case. So $P(G_1) = P(G_2) = g/(g+r)$.\n\n**(c)** Let $A$ = different colors. $P(A) = \\frac{2gr}{(g+r)(g+r-1)} = \\frac{1}{2}$, giving $(g-r)^2 = g + r = 16$. So $g - r = \\pm 4$: either $(g, r) = (10, 6)$ or $(6, 10)$."),
        .init(
            id: "stat110-hw1-hw-7", setNumber: 1, kind: .homework,
            topic: nil, number: "7",
            title: "Hockey-stick identity + gummi bears",
            body: "(a) Show using a story proof that\n$$\\binom{k}{k} + \\binom{k+1}{k} + \\binom{k+2}{k} + \\cdots + \\binom{n}{k} = \\binom{n+1}{k+1},$$\nwhere $n$ and $k$ are positive integers with $n \\geq k$.\n*Hint:* imagine arranging a group of people by age, and then think about the oldest person in a chosen subgroup.\n\n(b) Suppose that a large pack of Haribo gummi bears can have anywhere between 30 and 50 gummi bears. There are 5 delicious flavors: pineapple (clear), raspberry (red), orange (orange), strawberry (green, mysteriously), and lemon (yellow). There are 0 non-delicious flavors. How many possibilities are there for the composition of such a pack of gummi bears? You can leave your answer in terms of a couple binomial coefficients, but not a sum of lots of binomial coefficients.",
            firstLineHint: "(a) Story: choose $k+1$ from $n+1$ ordered by age; split by who the oldest in the subgroup is. (b) Pack of $i$ bears with 5 flavors: $\\binom{i+4}{4}$. Sum and use (a).",
            quantRelevance: 5,
            quantRationale: "Hockey-stick is a foundational summation tool. Stars-and-bars closure is interview canon.",
            answer: "**(a)** Choose $k+1$ people from $n+1$. Call the oldest in the chosen subgroup \"Aemon.\" If $j$ people are younger than Aemon, $\\binom{j}{k}$ choices for the rest. Summing over $j = k, \\ldots, n$ gives the identity. (Called the *hockey-stick identity*.)\n\n**(b)** Pack of $i$ bears with 5 flavors: $\\binom{5+i-1}{i} = \\binom{i+4}{4}$ compositions (stars and bars). Total:\n$$\\sum_{i=30}^{50} \\binom{i+4}{4} = \\sum_{j=34}^{54} \\binom{j}{4}.$$\nApplying (a):\n$$\\sum_{j=34}^{54} \\binom{j}{4} = \\binom{55}{5} - \\binom{34}{5}.$$\n(This works out to 3,200,505 possibilities!)"),
    ]
)

// MARK: - HW2 (Fall 2011)
// Source: https://stat110.hsites.harvard.edu/sites/g/files/omnuum10111/files/stat110/files/strategic_practice_and_homework_2.pdf

private let hw2: Stat110ProblemSet = .init(
    setNumber: 2,
    title: "Strategic Practice & Homework 2",
    pdfURL: "https://stat110.hsites.harvard.edu/sites/g/files/omnuum10111/files/stat110/files/strategic_practice_and_homework_2.pdf",
    problems: [
        // --- Strategic Practice 2 ---
        .init(
            id: "stat110-hw2-sp-1.1", setNumber: 2, kind: .strategicPractice,
            topic: "Inclusion-Exclusion", number: "1.1",
            title: "All 4 seasons among 7 birthdays",
            body: "For a group of 7 people, find the probability that all 4 seasons (winter, spring, summer, fall) occur at least once each among their birthdays, assuming that all seasons are equally likely.",
            firstLineHint: "Let Aᵢ be the event that there are no birthdays in the i-th season. The probability that all seasons occur at least once is 1 − P(A₁ ∪ A₂ ∪ A₃ ∪ A₄).",
            quantRelevance: 3,
            quantRationale: "Inclusion-exclusion is interview-relevant; the seasons setup itself is niche but the technique transfers."),
        .init(
            id: "stat110-hw2-sp-1.2", setNumber: 2, kind: .strategicPractice,
            topic: "Inclusion-Exclusion", number: "1.2",
            title: "Alice picks 7 of 30 classes",
            body: "Alice attends a small college in which each class meets only once a week. She is deciding between 30 non-overlapping classes. There are 6 classes to choose from for each day of the week, Monday through Friday. Trusting in the benevolence of randomness, Alice decides to register for 7 randomly selected classes out of the 30, with all choices equally likely. What is the probability that she will have classes every day, Monday through Friday? (This problem can be done either directly using the naive definition of probability, or using inclusion-exclusion.)",
            firstLineHint: "Direct method: split into the two ways she can hit every day — either (2,2,1,1,1) classes/day or (3,1,1,1,1). Or use IE on Bᵢ = no class on day i.",
            quantRelevance: 3,
            quantRationale: "Counting two ways (direct vs IE) is a great muscle; the bin-packing flavor shows up in interviews."),

        .init(
            id: "stat110-hw2-sp-2.1", setNumber: 2, kind: .strategicPractice,
            topic: "Independence", number: "2.1",
            title: "Can an event be independent of itself?",
            body: "Is it possible that an event is independent of itself? If so, when?",
            firstLineHint: "If A is independent of itself, then P(A) = P(A ∩ A) = P(A)², so P(A) ∈ {0, 1}.",
            quantRelevance: 4,
            quantRationale: "Classic interview gotcha — tests whether you actually internalized the definition. Asked verbatim at trading firms."),
        .init(
            id: "stat110-hw2-sp-2.2", setNumber: 2, kind: .strategicPractice,
            topic: "Independence", number: "2.2",
            title: "Are Aᶜ and Bᶜ independent?",
            body: "Is it always true that if A and B are independent events, then Aᶜ and Bᶜ are independent events? Show that it is, or give a counterexample.",
            firstLineHint: "Yes. P(Aᶜ ∩ Bᶜ) = 1 − P(A ∪ B) = 1 − P(A) − P(B) + P(A)P(B) = (1 − P(A))(1 − P(B)).",
            quantRelevance: 3,
            quantRationale: "Basic complement manipulation, comes up as a warmup or sanity check."),
        .init(
            id: "stat110-hw2-sp-2.3", setNumber: 2, kind: .strategicPractice,
            topic: "Independence", number: "2.3",
            title: "Pairwise but not mutually independent",
            body: "Give an example of 3 events A, B, C which are pairwise independent but not independent. Hint: find an example where whether C occurs is completely determined if we know whether A occurred and whether B occurred, but completely undetermined if we know only one of these things.",
            firstLineHint: "Two fair, independent coin tosses. A = first toss is Heads; B = second toss is Heads; C = the two tosses have the same result.",
            quantRelevance: 4,
            quantRationale: "Tests whether you really understand independence vs pairwise — a frequent interview trap."),
        .init(
            id: "stat110-hw2-sp-2.4", setNumber: 2, kind: .strategicPractice,
            topic: "Independence", number: "2.4",
            title: "Non-indep with P(A∩B∩C) = P(A)P(B)P(C)",
            body: "Give an example of 3 events A, B, C which are not independent, yet satisfy P(A ∩ B ∩ C) = P(A)P(B)P(C). Hint: consider simple and extreme cases.",
            firstLineHint: "Take the extreme case P(A) = 0. Then P(A)P(B)P(C) = 0 automatically, and P(A ∩ B ∩ C) = 0 since it's a subset of A.",
            quantRelevance: 3,
            quantRationale: "Shows that the triple-product condition isn't sufficient — instructive but rarely asked verbatim."),

        .init(
            id: "stat110-hw2-sp-3.1", setNumber: 2, kind: .strategicPractice,
            topic: "Thinking Conditionally", number: "3.1",
            title: "Lewis Carroll's marble",
            body: "A bag contains one marble which is either green or blue, with equal probabilities. A green marble is put in the bag (so there are 2 marbles now), and then a random marble is taken out. The marble taken out is green. What is the probability that the remaining marble is also green? (Historical note: this problem was first posed by Lewis Carroll in 1893.)",
            firstLineHint: "Let A = initial marble is green, B = removed marble is green, C = remaining marble is green. Condition on A: P(C|B) = P(C|B,A)P(A|B) + P(C|B,Aᶜ)P(Aᶜ|B) = 1·P(A|B) + 0.",
            quantRelevance: 4,
            quantRationale: "Bayes basics. Two-marbles framing shows up in many forms (urn problems, coin-in-hat) at quant interviews."),
        .init(
            id: "stat110-hw2-sp-3.2", setNumber: 2, kind: .strategicPractice,
            topic: "Thinking Conditionally", number: "3.2",
            title: "Spam filter — P(spam | \"free money\")",
            body: "A spam filter is designed by looking at commonly occurring phrases in spam. Suppose that 80% of email is spam. In 10% of the spam emails, the phrase \"free money\" is used, whereas this phrase is only used in 1% of non-spam emails. A new email has just arrived, which does mention \"free money\". What is the probability that it is spam?",
            firstLineHint: "By Bayes: P(S|F) = P(F|S)P(S) / P(F) = (0.1 · 0.8) / (0.1·0.8 + 0.01·0.2) = 80/82 ≈ 0.9756.",
            quantRelevance: 4,
            quantRationale: "Pure Bayes-rule plug-and-chug — building block for medical test, false positive, fraud detection style interview questions."),
        .init(
            id: "stat110-hw2-sp-3.3", setNumber: 2, kind: .strategicPractice,
            topic: "Thinking Conditionally", number: "3.3",
            title: "Two pieces of evidence E₁, E₂",
            body: "Let G be the event that a certain individual is guilty of a certain robbery. In gathering evidence, it is learned that an event E₁ occurred, and a little later it is also learned that another event E₂ also occurred. (a) Is it possible that individually, these pieces of evidence increase the chance of guilt (so P(G|E₁) > P(G) and P(G|E₂) > P(G)), but together they decrease the chance of guilt (so P(G|E₁,E₂) < P(G))? (b) Show that the probability of guilt given the evidence is the same regardless of whether we update our probabilities all at once, or in two steps.",
            firstLineHint: "(a) Yes — and not just possible, but possible to preclude G entirely. Take E₁ = suspect at coffeeshop 1-2 pm and E₂ = at coffeeshop 2-3 pm, where the crime happened 1-3 pm. (b) Follows directly from the definition of conditional probability.",
            quantRelevance: 3,
            quantRationale: "Shows updating-order invariance — useful theoretically. (a) is a nice gotcha."),
        .init(
            id: "stat110-hw2-sp-3.4", setNumber: 2, kind: .strategicPractice,
            topic: "Thinking Conditionally", number: "3.4",
            title: "Blood-type forensic Bayes",
            body: "A crime is committed by one of two suspects, A and B. Initially, there is equal evidence against both of them. In further investigation at the crime scene, it is found that the guilty party had a blood type found in 10% of the population. Suspect A does match this blood type, whereas the blood type of Suspect B is unknown. (a) Given this new information, what is the probability that A is the guilty party? (b) Given this new information, what is the probability that B's blood type matches that found at the crime scene?",
            firstLineHint: "(a) Bayes: P(A|M) = (1/2) / (1/2 + (1/10)(1/2)) = 10/11. (P(M|B) = 1/10 since if B is guilty, A's blood matches with population frequency.)",
            quantRelevance: 4,
            quantRationale: "The prosecutor's fallacy — gold standard for testing whether someone really applies Bayes correctly. Asked at quant firms in disguised form."),
        .init(
            id: "stat110-hw2-sp-3.5", setNumber: 2, kind: .strategicPractice,
            topic: "Thinking Conditionally", number: "3.5",
            title: "Two chess games vs. unknown-skill opponent",
            body: "You are going to play 2 games of chess with an opponent whom you have never played against before. Your opponent is equally likely to be a beginner, intermediate, or a master. Depending on which, your chances of winning an individual game are 90%, 50%, or 30%, respectively. (a) What is your probability of winning the first game? (b) Given you won the first game, what is the probability that you will also win the second game (assume that, given the skill level of your opponent, the outcomes of the games are independent)? (c) Explain the distinction between assuming the games are independent and conditionally independent given skill level.",
            firstLineHint: "(a) P(W₁) = (0.9 + 0.5 + 0.3) / 3 = 17/30. (b) Condition on opponent skill: P(W₁, W₂) = (0.9² + 0.5² + 0.3²)/3 = 23/60, so P(W₂|W₁) = (23/60)/(17/30) = 23/34.",
            quantRelevance: 5,
            quantRationale: "Conditional independence is THE distinction that separates quants from amateurs. Coin-in-hat / mixture distribution interview classic."),

        // --- Homework 2 ---
        .init(
            id: "stat110-hw2-hw-1", setNumber: 2, kind: .homework,
            topic: nil, number: "1",
            title: "Arby's belief system — Dutch book",
            body: "Arby has a belief system assigning a number P_Arby(A) between 0 and 1 to every event A. Arby is willing to buy/sell a $1000-on-A certificate at price $1000·P_Arby(A) (in either direction). Arby refuses to accept the axioms of probability — in particular, there are two disjoint events A and B with P_Arby(A ∪ B) ≠ P_Arby(A) + P_Arby(B). Show how to make Arby go bankrupt by giving a list of transactions Arby is willing to make that will guarantee that Arby loses money.",
            firstLineHint: "If P_Arby(A ∪ B) < P_Arby(A) + P_Arby(B): buy an A-certificate and a B-certificate from Arby, and sell Arby an (A ∪ B)-certificate. Arby loses P_Arby(A) + P_Arby(B) − P_Arby(A ∪ B) immediately, and can't recoup it because at most one of A, B occurs.",
            quantRelevance: 5,
            quantRationale: "Dutch-book / arbitrage. THE foundational quant-theory problem — explains why the axioms aren't arbitrary. Asked verbatim at Jane Street."),
        .init(
            id: "stat110-hw2-hw-2", setNumber: 2, kind: .homework,
            topic: nil, number: "2",
            title: "13-card hand void in a suit",
            body: "A card player is dealt a 13 card hand from a well-shuffled, standard deck of cards. What is the probability that the hand is void in at least one suit (\"void in a suit\" means having no cards of that suit)?",
            firstLineHint: "Let S, H, D, C be void in spades, hearts, diamonds, clubs. By IE and symmetry: P(S ∪ H ∪ D ∪ C) = 4P(S) − 6P(S ∩ H) + 4P(S ∩ H ∩ D), where P(S) = C(39,13)/C(52,13), etc.",
            quantRelevance: 3,
            quantRationale: "IE + symmetry on cards. Counting/combinatorics interviewers like this style but you'll see simpler versions."),
        .init(
            id: "stat110-hw2-hw-3", setNumber: 2, kind: .homework,
            topic: nil, number: "3",
            title: "Three children — is A>B indep of A>C?",
            body: "A family has 3 children, creatively named A, B, and C. (a) Discuss intuitively (but clearly) whether the event \"A is older than B\" is independent of the event \"A is older than C.\" (b) Find the probability that A is older than B, given that A is older than C.",
            firstLineHint: "(a) Not independent: knowing A > B makes A > C more likely (only birth order CAB has A < C; both ABC and ACB are compatible with A > B). (b) P(A > B | A > C) = P(A is eldest) / P(A > C) = (1/3) / (1/2) = 2/3.",
            quantRelevance: 4,
            quantRationale: "Symmetry argument + conditioning. The \"think in extremes\" hint (100 children) is a classic interview move."),
        .init(
            id: "stat110-hw2-hw-4", setNumber: 2, kind: .homework,
            topic: nil, number: "4",
            title: "Fair vs biased coin in hat",
            body: "Two coins are in a hat. The coins look alike, but one coin is fair (with probability 1/2 of Heads), while the other coin is biased, with probability 1/4 of Heads. One of the coins is randomly pulled from the hat. Call the chosen coin \"Coin C\". (a) Coin C is tossed twice, showing Heads both times. Given this information, what is the probability that Coin C is the fair coin? (b) Are the events \"first toss is Heads\" and \"second toss is Heads\" independent? Explain. (c) Find the probability that in 10 flips of Coin C, there will be exactly 3 Heads.",
            firstLineHint: "(a) Bayes: P(fair|HH) = ((1/4)(1/2)) / ((1/4)(1/2) + (1/16)(1/2)) = 4/5. (b) Not independent — first toss being Heads is evidence for the fair coin.",
            quantRelevance: 5,
            quantRationale: "Coin-in-hat / mixture distribution — interview canon. Tests conditional independence + Bayes + binomial mixing all at once."),
        .init(
            id: "stat110-hw2-hw-5", setNumber: 2, kind: .homework,
            topic: nil, number: "5",
            title: "Murdered wife — Bayesian guilt",
            body: "A woman has been murdered, and her husband is accused. The man abused his wife in the past. The defense says abuse is irrelevant: only 1 in 1000 men who beat their wives end up murdering them. Assume that figure is correct, that half of men who murder their wives previously abused them, that 20% of murdered women were killed by their husbands, and that if a woman is murdered and the husband is not guilty, then there is only a 10% chance that the husband abused her. What is the probability that the man is guilty? Is the prosecution right that abuse is important evidence in favor of guilt?",
            firstLineHint: "The defense's 1/1000 is the wrong conditional — they didn't condition on the wife being murdered. Let G = guilty, M = murdered, A = abused. We want P(G|A,M). By Bayes (conditional on M): P(G|A,M) = (0.5·0.2) / (0.5·0.2 + 0.1·0.8) = 5/9 ≈ 0.56.",
            quantRelevance: 4,
            quantRationale: "Conditioning on the right event. Classic legal-statistics example — variants asked at hedge funds for risk reasoning."),
        .init(
            id: "stat110-hw2-hw-6", setNumber: 2, kind: .homework,
            topic: nil, number: "6",
            title: "Two-child puzzle with birth-month",
            body: "A family has two children. Assume birth month is independent of gender, with boys and girls equally likely and all months equally likely, and the elder child's characteristics are independent of the younger's. (a) Find the probability that both are girls, given that the elder child is a girl who was born in March. (b) Find the probability that both are girls, given that at least one is a girl who was born in March.",
            firstLineHint: "(a) Conditioning on the elder child's gender + month is independent of the younger child's gender: answer is just P(younger is girl) = 1/2. (b) Numerator: P(both girls, at least one March-born) = (1/4)(1 − (11/12)²). Denominator: 1 − (23/24)². Answer: 23/47 ≈ 0.489.",
            quantRelevance: 4,
            quantRationale: "Two-child paradox — interview-classic brainteaser. The March twist shows specificity-of-information effects, a deep Bayesian lesson."),
    ]
)

// MARK: - HW3 (Fall 2011)
// Source: https://stat110.hsites.harvard.edu/sites/g/files/omnuum10111/files/stat110/files/strategic_practice_and_homework_3.pdf

private let hw3: Stat110ProblemSet = .init(
    setNumber: 3,
    title: "Strategic Practice & Homework 3",
    pdfURL: "https://stat110.hsites.harvard.edu/sites/g/files/omnuum10111/files/stat110/files/strategic_practice_and_homework_3.pdf",
    problems: [
        // --- Strategic Practice 3 ---
        .init(
            id: "stat110-hw3-sp-1.1", setNumber: 3, kind: .strategicPractice,
            topic: "Monty Hall", number: "1.1",
            title: "Biased Monty Hall",
            body: "Consider the Monty Hall problem, except that Monty enjoys opening Door 2 more than he enjoys opening Door 3, and if he has a choice between opening these two doors, he opens Door 2 with probability $p$, where $\\tfrac{1}{2} \\leq p \\leq 1$.\n\nTo recap: there are three doors, behind one of which there is a car (which you want), and behind the other two of which there are goats (which you don't want). Initially, all possibilities are equally likely for where the car is. You choose a door, which for concreteness we assume is Door 1. Monty Hall then opens a door to reveal a goat, and offers you the option of switching. Assume that Monty Hall knows which door has the car, will always open a goat door and offer the option of switching, and as above assume that if Monty Hall has a choice between opening Door 2 and Door 3, he chooses Door 2 with probability $p$ (with $\\tfrac{1}{2} \\leq p \\leq 1$).\n\n(a) Find the unconditional probability that the strategy of always switching succeeds (unconditional in the sense that we do not condition on which of Doors 2,3 Monty opens).\n\n(b) Find the probability that the strategy of always switching succeeds, given that Monty opens Door 2.\n\n(c) Find the probability that the strategy of always switching succeeds, given that Monty opens Door 3.",
            firstLineHint: "(a) Let $C_j$ = car behind door $j$, $W$ = win by switching. LOTP: $P(W) = P(W|C_1)\\cdot(1/3) + P(W|C_2)\\cdot(1/3) + P(W|C_3)\\cdot(1/3) = 0 + 1/3 + 1/3 = 2/3$.",
            quantRelevance: 4,
            quantRationale: "Monty Hall is the canonical interview problem for testing conditional probability. The biased variant tests deeper Bayes reasoning.",
            answer: "**(a) Find the unconditional probability that the strategy of always switching succeeds (unconditional in the sense that we do not condition on which of Doors 2,3 Monty opens).**\n\nLet $C_j$ be the event that the car is hidden behind door $j$ and let $W$ be the event that we win using the switching strategy. Using the law of total probability, we can find the unconditional probability of winning in the same way as in class:\n$$P(W) = P(W|C_1)P(C_1) + P(W|C_2)P(C_2) + P(W|C_3)P(C_3) = 0 \\cdot \\tfrac{1}{3} + 1 \\cdot \\tfrac{1}{3} + 1 \\cdot \\tfrac{1}{3} = \\tfrac{2}{3}.$$\n\n**(b) Find the probability that the strategy of always switching succeeds, given that Monty opens Door 2.**\n\nA tree method works well here (delete the paths which are no longer relevant after the conditioning, and reweight the remaining values by dividing by their sum), or we can use Bayes' rule and the law of total probability (as below).\n\nLet $D_i$ be the event that Monty opens Door $i$. Note that we are looking for $P(W|D_2)$, which is the same as $P(C_3|D_2)$ as we first choose Door 1 and then switch to Door 3. By Bayes' rule and the law of total probability,\n$$P(C_3|D_2) = \\frac{P(D_2|C_3)P(C_3)}{P(D_2)} = \\frac{P(D_2|C_3)P(C_3)}{P(D_2|C_1)P(C_1) + P(D_2|C_2)P(C_2) + P(D_2|C_3)P(C_3)} = \\frac{1 \\cdot 1/3}{p \\cdot 1/3 + 0 \\cdot 1/3 + 1 \\cdot 1/3} = \\frac{1}{1+p}.$$\n\n**(c) Find the probability that the strategy of always switching succeeds, given that Monty opens Door 3.**\n\nThe structure of the problem is the same as part (b) (except for the condition that $p \\geq 1/2$, which was not needed above). Imagine repainting doors 2 and 3, reversing which is called which. By part (b) with $1-p$ in place of $p$, $P(C_2|D_3) = \\dfrac{1}{1+(1-p)} = \\dfrac{1}{2-p}$."),
        .init(
            id: "stat110-hw3-sp-1.2", setNumber: 3, kind: .strategicPractice,
            topic: "Conditional Independence", number: "1.2",
            title: "True/False on independence of X, Y, Z",
            body: "For each statement below, either show that it is true or give a counterexample. Throughout, $X, Y, Z$ are discrete random variables.\n\n(a) If $X$ and $Y$ are independent and $Y$ and $Z$ are independent, then $X$ and $Z$ are independent.\n\n(b) If $X$ and $Y$ are independent, then they are conditionally independent given $Z$.\n\n(c) If $X$ and $Y$ are conditionally independent given $Z$, then they are independent.\n\n(d) If $X$ and $Y$ have the same distribution given $Z$, i.e., for all $a$ and $z$, we have $P(X = a|Z = z) = P(Y = a|Z = z)$, then $X$ and $Y$ have the same distribution.",
            firstLineHint: "(a) False — take $X = Z$. (b) False — fire/popcorn example. (c) False — chess opponent of unknown strength, or coin-in-hat. (d) True — by LOTP.",
            quantRelevance: 5,
            quantRationale: "THE highest-yield problem in Stat 110 for quant interviews. These four traps are the deep water that separates careful thinkers from casual ones.",
            answer: "**(a)** If $X$ and $Y$ are independent and $Y$ and $Z$ are independent, then $X$ and $Z$ are independent.\n\n**False**: for a simple example, take $X = Z$.\n\n**(b)** If $X$ and $Y$ are independent, then they are conditionally independent given $Z$.\n\n**False**: this was discussed in class (the fire-popcorn example) in terms of events, for which we can let $X, Y, Z$ be indicators.\n\n**(c)** If $X$ and $Y$ are conditionally independent given $Z$, then they are independent.\n\n**False**: this was discussed in class in terms of events (the chess opponent of unknown strength example); a coin with a random bias (as on HW 2) is another simple, useful example to keep in mind.\n\n**(d)** If $X$ and $Y$ have the same distribution given $Z$, i.e., for all $a$ and $z$, we have $P(X = a|Z = z) = P(Y = a|Z = z)$, then $X$ and $Y$ have the same distribution.\n\n**True**: by the law of total probability, conditioning on $Z$ gives\n$$P(X = a) = \\sum_z P(X = a|Z = z)P(Z = z).$$\nSince $X$ and $Y$ have the same conditional distribution given $Z$, this becomes $\\sum_z P(Y = a|Z = z)P(Z = z) = P(Y = a)$."),

        .init(
            id: "stat110-hw3-sp-2.1", setNumber: 3, kind: .strategicPractice,
            topic: "Simpson's Paradox", number: "2.1",
            title: "Simpson's Paradox — two-event vs three-event",
            body: "(a) Is it possible to have events $A, B, E$ such that $P(A|E) < P(B|E)$ and $P(A|E^c) < P(B|E^c)$, yet $P(A) > P(B)$? That is, $A$ is less likely under $B$ given that $E$ is true, and also given that $E$ is false, yet $A$ is more likely than $B$ if given no information about $E$. Show this is impossible (with a short proof) or find a counterexample (with a \"story\" interpreting $A, B, E$).\n\n(b) Is it possible to have events $A, B, E$ such that $P(A|B, E) < P(A|B^c, E)$ and $P(A|B, E^c) < P(A|B^c, E^c)$, yet $P(A|B) > P(A|B^c)$? That is, given that $E$ is true, learning $B$ is evidence against $A$, and similarly given that $E$ is false; but given no information about $E$, learning that $B$ is true is evidence in favor of $A$. Show this is impossible (with a short proof) or find a counterexample (with a \"story\" interpreting $A, B, E$).",
            firstLineHint: "(a) Not possible — straight LOTP. (b) Yes — this is the structure of Simpson's Paradox.",
            quantRelevance: 5,
            quantRationale: "Simpson's Paradox is a real risk-management trap. Understanding the structure is mandatory for anyone touching data at a hedge fund.",
            answer: "**(a)** It is *not* possible, as seen using the law of total probability:\n$$P(A) = P(A|E)P(E) + P(A|E^c)P(E^c) < P(B|E)P(E) + P(B|E^c)P(E^c) = P(B).$$\n\n**(b)** Yes, this is possible: this is the structure of Simpson's Paradox! For example, consider the Stampy problem above. Or, consider the two doctors example discussed in class: suppose that there are two doctors, Dr. Hibbert and Dr. Nick. Each performs two types of surgery, say heart transplants and bandaid removals. Let $A$ be the event that a surgery is successful, let $B$ be the event that Dr. Nick performs the surgery and $B^c$ be the complement, that Dr. Hibbert performs the surgery. Let $E$ be heart surgery and $E^c$ be bandaid removal.\n\nIs it possible that Dr. Hibbert is better than Dr. Nick at both heart transplants and bandaid removals, yet Dr. Nick has a higher success rate overall? Yes, this can happen if Dr. Nick performs mostly bandaid removals and Dr. Hibbert performs mostly heart transplants. That is, the better doctor may perform relatively more of the harder surgery, resulting in a lower success rate.\n\nTo make up specific numbers, suppose that Dr. Hibbert performed 90 heart transplants, with 70 successful, and 10 bandaid removals, with all 10 successful. Dr. Nick performed 10 heart transplants, with 2 successful, and 90 bandaid removals, with 81 successful. Formally, our probability space consists of randomly choosing one of the 200 surgeries, uniformly. Note that each individual surgery is more likely to be successful given that it's performed by Dr. Hibbert, but Dr. Hibbert's overall success rate (80%) is lower than Dr. Nick's (83%).\n\nThere are many real-life examples of Simpson's Paradox. For example, it is possible for one baseball player to have a higher batting average than another in each of two seasons, yet a lower batting average when the two seasons are aggregated. Simpson's Paradox illustrates the importance of controlling for additional variables that interfere with the analysis (known as *confounders*)."),
        .init(
            id: "stat110-hw3-sp-2.2", setNumber: 3, kind: .strategicPractice,
            topic: "Simpson's Paradox", number: "2.2",
            title: "Lisa, Homer, and Stampy",
            body: "Consider the following conversation from an episode of *The Simpsons*:\n\n*Lisa: Dad, I think he's an ivory dealer! His boots are ivory, his hat is ivory, and I'm pretty sure that check is ivory.*\n\n*Homer: Lisa, a guy who's got lots of ivory is less likely to hurt Stampy than a guy whose ivory supplies are low.*\n\nHere Homer and Lisa are debating the question of whether or not the man (named Blackheart) is likely to hurt Stampy the Elephant if they sell Stampy to him. They clearly disagree about how to use their observations about Blackheart to learn about the probability (conditional on the evidence) that Blackheart will hurt Stampy.\n\n(a) Define clear notation for the various events of interest here.\n\n(b) Express Lisa's and Homer's arguments (Lisa's is partly implicit) as conditional probability statements in terms of your notation from (a).\n\n(c) Assume it is true that someone who has a lot of a commodity will have less desire to acquire more of the commodity. Explain what is wrong with Homer's reasoning that the evidence about Blackheart makes it less likely that he will harm Stampy.",
            firstLineHint: "Three events run the conversation: $H$ = will hurt Stampy, $L$ = lots of ivory, $D$ = ivory dealer.",
            quantRelevance: 3,
            quantRationale: "Narrative-heavy but the conditioning-on-the-wrong-thing fallacy is real. Less directly interview-asked than 2.1.",
            answer: "**(a) Define clear notation for the various events of interest here.**\n\nLet $H$ be the event that the man will hurt Stampy, let $L$ be the event that a man has lots of ivory, and let $D$ be the event that the man is an ivory dealer.\n\n**(b) Express Lisa's and Homer's arguments (Lisa's is partly implicit) as conditional probability statements in terms of your notation from (a).**\n\nLisa observes that $L$ is true. She suggests (reasonably) that this evidence makes $D$ more likely, i.e., $P(D|L) > P(D)$. Implicitly, she suggests that this makes it likely that the man will hurt Stampy, i.e.,\n$$P(H|L) > P(H|L^c).$$\nHomer argues that\n$$P(H|L) < P(H|L^c).$$\n\n**(c) Assume it is true that someone who has a lot of a commodity will have less desire to acquire more of the commodity. Explain what is wrong with Homer's reasoning that the evidence about Blackheart makes it less likely that he will harm Stampy.**\n\nHomer does not realize that observing that Blackheart has so much ivory makes it much more likely that Blackheart is an ivory dealer, which in turn makes it more likely that the man will hurt Stampy. (This is an example of Simpson's Paradox.) It may be true that, *controlling for whether or not Blackheart is a dealer*, having high ivory supplies makes it less likely that he will harm Stampy: $P(H|L, D) < P(H|L^c, D)$ and $P(H|L, D^c) < P(H|L^c, D^c)$. However, this does not imply that $P(H|L) < P(H|L^c)$."),

        .init(
            id: "stat110-hw3-sp-3.1", setNumber: 3, kind: .strategicPractice,
            topic: "Gambler's Ruin", number: "3.1",
            title: "Gambler quits when ahead by \\$2",
            body: "A gambler repeatedly plays a game where in each round, he wins a dollar with probability $1/3$ and loses a dollar with probability $2/3$. His strategy is \"quit when he is ahead by \\$2,\" though some suspect he is a gambling addict anyway. Suppose that he starts with a million dollars. Show that the probability that he'll ever be ahead by \\$2 is less than $1/4$.",
            firstLineHint: "Special case of gambler's ruin. Let $a_i$ = probability of reaching the target before being ruined, starting with \\$$i$.",
            quantRelevance: 5,
            quantRationale: "Gambler's ruin is a top-3 interview topic at trading firms. First-step analysis + recurrence is the canonical move.",
            answer: "This problem is a special case of the gambler's ruin. Let $A_1$ be the event that he is successful on the first play and let $W$ be the event that he is ever ahead by \\$2 before being ruined. Then by the law of total probability, we have\n$$P(W) = P(W|A_1)P(A_1) + P(W|A_1^c)P(A_1^c).$$\nLet $a_i$ be the probability that the gambler achieves a profit of \\$2 before being ruined, starting with a fortune of \\$$i$. For our setup, $P(W) = a_i$, $P(W|A_1) = a_{i+1}$ and $P(W|A_1^c) = a_{i-1}$. Therefore,\n$$a_i = a_{i+1}/3 + 2a_{i-1}/3,$$\nwith boundary conditions $a_0 = 0$ and $a_{i+2} = 1$. We can then solve this difference equation for $a_i$ (directly or using the result of the gambler's ruin problem):\n$$a_i = \\frac{2^i - 1}{2^{2+i} - 1}.$$\nThis is always less than $1/4$ since $\\frac{2^i-1}{2^{2+i}-1} < \\frac{1}{4}$ is equivalent to $4(2^i - 1) < 2^{2+i} - 1$, which is equivalent to the true statement $2^{2+i} - 4 < 2^{2+i} - 1$."),

        .init(
            id: "stat110-hw3-sp-4.1", setNumber: 3, kind: .strategicPractice,
            topic: "Binomial", number: "4.1",
            title: "World Series",
            body: "(a) In the World Series of baseball, two teams (call them $A$ and $B$) play a sequence of games against each other, and the first team to win four games wins the series. Let $p$ be the probability that $A$ wins an individual game, and assume that the games are independent. What is the probability that team $A$ wins the series?\n\n(b) Give a clear intuitive explanation of whether the answer to (a) depends on whether the teams always play 7 games (and whoever wins the majority wins the series), or the teams stop playing more games as soon as one team has won 4 games (as is actually the case in practice: once the match is decided, the two teams do not keep playing more games).",
            firstLineHint: "Try the \"play out all 7\" trick — even after the series is decided, imagine they keep playing. The series winner is unaffected.",
            quantRelevance: 4,
            quantRationale: "Best-of-N series problems are interview canon. The \"play out all 7\" trick is the move and it generalizes.",
            answer: "Let $q = 1 - p$. First let us do a direct calculation:\n$$P(A \\text{ wins}) = P(A \\text{ winning in 4 games}) + P(A \\text{ winning in 5 games}) + P(A \\text{ wins in 6 games}) + P(A \\text{ winning in 7 games})$$\n$$= p^4 + \\binom{4}{3} p^4 q + \\binom{5}{3} p^4 q^2 + \\binom{6}{3} p^4 q^3.$$\nTo understand how these probabilities are calculated, note for example that\n$$P(A \\text{ wins in 5}) = P(A \\text{ wins 3 out of first 4}) \\cdot P(A \\text{ wins 5th game} \\mid A \\text{ wins 3 out of first 4}) = \\binom{4}{3} p^3 q \\cdot p.$$\n(This value can also be found from the PMF of a distribution known as the *Negative Binomial*, which we will see later in the course.)\n\nA neater solution is to use the fact (explained in (b)) that we can assume that the teams play all 7 games no matter what. Then let $X$ be the number of wins for team $A$, so that\n$$X \\sim \\text{Binomial}(7, p).$$\nThe probability that team $A$ wins the series is\n$$P(X \\geq 4) = P(X = 4) + P(X = 5) + P(X = 6) + P(X = 7).$$\nThe PMF of the $\\text{Bin}(n, p)$ distribution is\n$$P(X = k) = \\binom{n}{k} p^k (1-p)^{n-k},$$\nand therefore\n$$P(X \\geq 4) = \\binom{7}{4} p^4 q^3 + \\binom{7}{5} p^5 q^2 + \\binom{7}{6} p^6 q + p^7,$$\nwhich looks different from the above but is actually identical as a function of $p$ (as can be verified by simplifying both expressions as polynomials in $p$).\n\n**(b)** Give a clear intuitive explanation of whether the answer to (a) depends on whether the teams always play 7 games (and whoever wins the majority wins the series), or the teams stop playing more games as soon as one team has won 4 games (as is actually the case in practice: once the match is decided, the two teams do not keep playing more games).\n\nThe answer to (a) does not depend on whether the teams play all seven games no matter what. Imagine telling the players to continue playing the games even after the match has been decided, just for fun: the outcome of the match won't be affected by this, and this also means that the probability that $A$ wins the match won't be affected by assuming that the teams always play 7 games!"),
        .init(
            id: "stat110-hw3-sp-4.2", setNumber: 3, kind: .strategicPractice,
            topic: "Binomial", number: "4.2",
            title: "Sequences given number of successes",
            body: "A sequence of $n$ independent experiments is performed. Each experiment is a success with probability $p$ and a failure with probability $q = 1 - p$. Show that conditional on the number of successes, all possibilities for the list of outcomes of the experiment are equally likely (of course, we only consider lists of outcomes where the number of successes is consistent with the information being conditioned on).",
            firstLineHint: "Set up indicators and write out the conditional probability with the definition.",
            quantRelevance: 4,
            quantRationale: "Sufficient statistics in disguise. The fact that p drops out is the foundation of estimation theory — and the symmetry argument is interview-grade.",
            answer: "Let $X_j$ be $1$ if the $j$th experiment is a success and $0$ otherwise, and let $X = X_1 + \\cdots + X_n$ be the total number of successes. Then for any $k$ and any $a_1, \\ldots, a_n \\in \\{0, 1\\}$ with $a_1 + \\cdots + a_n = k$,\n$$P(X_1 = a_1, \\ldots, X_n = a_n | X = k) = \\frac{P(X_1 = a_1, \\ldots, X_n = a_n, X = k)}{P(X = k)}$$\n$$= \\frac{P(X_1 = a_1, \\ldots, X_n = a_n)}{P(X = k)}$$\n$$= \\frac{p^k q^{n-k}}{\\binom{n}{k} p^k q^{n-k}}$$\n$$= \\frac{1}{\\binom{n}{k}}.$$\nThis does not depend on $a_1, \\ldots, a_n$. Thus, for $n$ independent Bernoulli trials, given that there are exactly $k$ successes, the $\\binom{n}{k}$ possible sequences consisting of $k$ successes and $n - k$ failures are equally likely. Interestingly, the conditional probability above also does not depend on $p$ (this leads to the notion of a *sufficient statistic*, which is studied in Stat 111)."),
        .init(
            id: "stat110-hw3-sp-4.3", setNumber: 3, kind: .strategicPractice,
            topic: "Binomial", number: "4.3",
            title: "Sums and differences of Binomials",
            body: "Let $X \\sim \\text{Bin}(n, p)$ and $Y \\sim \\text{Bin}(m, p)$, independent of $X$.\n\n(a) Show that $X + Y \\sim \\text{Bin}(n + m, p)$, using a story proof.\n\n(b) Show that $X - Y$ is *not* Binomial.\n\n(c) Find $P(X = k|X + Y = j)$. How does this relate to the elk problem from HW 1?",
            firstLineHint: "(a) Tell a story — don't compute. (b) Range. (c) Definition of conditional probability + cancel $p$.",
            quantRelevance: 4,
            quantRationale: "Story proofs and the surprising p-cancellation are both classic interview reveals. Hypergeometric structure is broadly useful.",
            answer: "**(a) Show that $X + Y \\sim \\text{Bin}(n + m, p)$, using a story proof.**\n\nInterpret $X$ as the number of successes in $n$ independent Bernoulli trials and $Y$ as the number of successes in $m$ more independent Bernoulli trials, where each trial has probability $p$ of success. Then $X + Y$ is the number of successes in the $n + m$ trials, so $X + Y \\sim \\text{Bin}(n + m, p)$.\n\n**(b) Show that $X - Y$ is not Binomial.**\n\nA Binomial can't be negative, but $X - Y$ is negative with positive probability.\n\n**(c) Find $P(X = k|X + Y = j)$. How does this relate to the elk problem from HW 1?**\n\nBy definition of conditional probability,\n$$P(X = k|X + Y = j) = \\frac{P(X = k, X + Y = j)}{P(X + Y = j)} = \\frac{P(X = k)P(Y = j - k)}{P(X + Y = j)}$$\nsince the event $X = k$ is independent of the event $Y = j - k$. This becomes\n$$\\frac{\\binom{n}{k} p^k (1-p)^{n-k} \\binom{m}{j-k} p^{j-k} (1-p)^{m-(j-k)}}{\\binom{n+m}{j} p^j (1-p)^{m+n-j}} = \\binom{n}{k}\\binom{m}{j-k} \\Big/ \\binom{n+m}{j}.$$\nNote that the $p$ disappeared! This is exactly the same distribution as in the elk problem (it is called the *Hypergeometric* distribution). To see why, imagine that there are $n$ male elk and $m$ female elk, each of which is tagged with the word \"success\" with probability $p$ (independently). Suppose we then want to know how many of the male elk are tagged, given that a total of $j$ elk have been tagged. For this, $p$ is no longer relevant, and we can \"capture\" the male elk and count how many are tagged, analogously to the original elk problem."),

        // --- Homework 3 ---
        .init(
            id: "stat110-hw3-hw-1", setNumber: 3, kind: .homework,
            topic: "Monty Hall", number: "1",
            title: "7-door (then general) Monty Hall",
            body: "(a) Consider the following 7-door version of the Monty Hall problem. There are 7 doors, behind one of which there is a car (which you want), and behind the rest of which there are goats (which you don't want). Initially, all possibilities are equally likely for where the car is. You choose a door. Monty Hall then opens 3 goat doors, and offers you the option of switching to any of the remaining 3 doors.\n\nAssume that Monty Hall knows which door has the car, will always open 3 goat doors and offer the option of switching, and that Monty chooses with equal probabilities from all his choices of which goat doors to open. Should you switch? What is your probability of success if you switch to one of the remaining 3 doors?\n\n(b) Generalize the above to a Monty Hall problem where there are $n \\geq 3$ doors, of which Monty opens $m$ goat doors, with $1 \\leq m \\leq n - 2$.",
            firstLineHint: "(a) Stick strategy: $P(\\text{success}) = 1/n = 1/7$. After Monty opens 3 doors, the remaining 3 doors collectively have probability $6/7$, so each has $\\frac{6/7}{3} = 2/7$. Switch.",
            quantRelevance: 4,
            quantRationale: "Generalizing Monty Hall sharpens the conditioning intuition. Interview variants come up often.",
            answer: "Assume the doors are labeled such that you choose Door 1 (to simplify notation), and suppose first that you follow the \"stick to your original choice\" strategy. Let $S$ be the event of success in getting the car, and let $C_j$ be the event that the car is behind Door $j$. Conditioning on which door has the car, we have\n$$P(S) = P(S|C_1)P(C_1) + \\cdots + P(S|C_7)P(C_7) = P(C_1) = \\frac{1}{7}.$$\nLet $M_{ijk}$ be the event that Monty opens Doors $i, j, k$. Then\n$$P(S) = \\sum_{i,j,k} P(S|M_{ijk})P(M_{ijk})$$\n(summed over all $i, j, k$ with $2 \\leq i < j < k \\leq 7$.) By symmetry, this gives\n$$P(S|M_{ijk}) = P(S) = \\frac{1}{7}$$\nfor all $i, j, k$ with $2 \\leq i < j < k \\leq 7$. Thus, the conditional probability that the car is behind 1 of the remaining 3 doors is $6/7$, which gives $2/7$ for each. So you should switch, thus making your probability of success $2/7$ rather than $1/7$.\n\n**(b) Generalize the above to a Monty Hall problem where there are $n \\geq 3$ doors, of which Monty opens $m$ goat doors, with $1 \\leq m \\leq n - 2$.**\n\nBy the same reasoning, the probability of success for \"stick to your original choice\" is $\\frac{1}{n}$, both unconditionally and conditionally. Each of the $n - m - 1$ remaining doors has conditional probability $\\frac{n-1}{(n-m-1)n}$ of having the car. This value is greater than $\\frac{1}{n}$, so you should switch, thus obtaining probability $\\frac{n-1}{(n-m-1)n}$ of success (both conditionally and unconditionally)."),
        .init(
            id: "stat110-hw3-hw-2", setNumber: 3, kind: .homework,
            topic: "Bayes' Rule", number: "2",
            title: "Bayes in odds form — medical test",
            body: "The *odds* of an event with probability $p$ are defined to be $\\frac{p}{1-p}$, e.g., an event with probability $3/4$ is said to have odds of 3 to 1 in favor (or 1 to 3 against). We are interested in a hypothesis $H$ (which we think of as a event), and we gather new data as evidence (expressed as an event $D$) to study the hypothesis. The *prior* probability of $H$ is our probability for $H$ being true before we gather the new data; the *posterior* probability of $H$ is our probability for it after we gather the new data. The *likelihood ratio* is defined as $\\frac{P(D|H)}{P(D|H^c)}$.\n\n(a) Show that Bayes' rule can be expressed in terms of odds as follows: *the posterior odds of a hypothesis $H$ are the prior odds of $H$ times the likelihood ratio*.\n\n(b) As in the example from class, suppose that a patient tests positive for a disease afflicting 1% of the population. For a patient who has the disease, there is a 95% chance of testing positive (in medical statistics, this is called the *sensitivity* of the test); for a patient who doesn't have the disease, there is a 95% chance of testing negative test (in medical statistics, this is called the *specificity* of the test).\n\nThe patient gets a second, independent test done (with the same sensitivity and specificity), and again tests positive. Use the odds form of Bayes' rule to find the probability that the patient has the disease, given the evidence, *in two ways*: in one step, conditioning on both test results simultaneously, and in two steps, first updating the probabilities based on the first test result, and then updating again based on the second test result.",
            firstLineHint: "(a) Divide Bayes' rule by its complement to kill $P(D)$ and get odds × LR.",
            quantRelevance: 5,
            quantRationale: "Bayes in odds form is THE quant tool — multiplies cleanly, generalizes to sequential evidence. Asked at Jane Street verbatim.",
            answer: "**(a)** We want to show that\n$$\\frac{P(H|D)}{P(H^c|D)} = \\frac{P(H)}{P(H^c)} \\cdot \\frac{P(D|H)}{P(D|H^c)}.$$\nBy Bayes' rule, we have\n$$P(H|D) = P(D|H)P(H)/P(D),$$\n$$P(H^c|D) = P(D|H^c)P(H^c)/P(D).$$\nDividing the first of these by the second, we immediately obtain the desired equation, which is a useful alternative way to write Bayes' rule.\n\n**(b)** To go from odds back to probability, we divide odds by (1 plus odds), since $\\frac{p/q}{1+p/q} = p$ for $q = 1 - p$. Let $H$ be the event of having the disease. The prior odds are 99 to 1 against having the disease. The likelihood ratio based on one test result is $\\frac{0.95}{0.05}$. Now we can immediately carry out either the one update or the two update method.\n\n*One update method:* The likelihood ratio based on both test results is $\\frac{0.95^2}{0.05^2}$ since the tests are independent. So the posterior odds of the patient having the disease are\n$$\\frac{1}{99} \\cdot \\frac{0.95^2}{0.05^2} = \\frac{361}{99} \\approx 3.646,$$\nwhich corresponds to a probability of $361/(361 + 99) = 361/460 \\approx 0.78$ (whereas based on one positive test, the probability was only $0.16$ of having the disease).\n\n*Two updates method:* After the first test, the posterior odds of the patient having the disease are\n$$\\frac{1}{99} \\cdot \\frac{0.95}{0.05} \\approx 0.19,$$\nwhich corresponds to a probability of $0.19/(1 + 0.19) \\approx 0.16$ (agreeing with the result from class). These posterior odds become the new prior odds, and then updating based on the second test gives $\\left(\\frac{1}{99} \\cdot \\frac{0.95}{0.05}\\right) \\frac{0.95}{0.05}$, which is the same result as above."),
        .init(
            id: "stat110-hw3-hw-3", setNumber: 3, kind: .homework,
            topic: "Conditioning", number: "3",
            title: "Union flip with conditional inequalities",
            body: "Is it possible to have events $A_1, A_2, B, C$ with $P(A_1|B) > P(A_1|C)$ and $P(A_2|B) > P(A_2|C)$, yet $P(A_1 \\cup A_2|B) < P(A_1 \\cup A_2|C)$? If so, find an example (with a \"story\" interpreting the events, as well as giving specific numbers); otherwise, show that it is impossible for this phenomenon to happen.",
            firstLineHint: "Yes, possible. Key: $P(A_1 \\cup A_2|B) = P(A_1|B) + P(A_2|B) - P(A_1 \\cap A_2|B)$. Need $P(A_1 \\cap A_2|B) \\gg P(A_1 \\cap A_2|C)$ to offset.",
            quantRelevance: 4,
            quantRationale: "Tests whether you really respect inclusion-exclusion under conditioning. Correlation > marginals is a key risk-management lesson.",
            answer: "Yes, this is possible. First note that $P(A_1 \\cup A_2|B) = P(A_1|B) + P(A_2|B) - P(A_1 \\cap A_2|B)$, so it is *not* possible if $A_1$ and $A_2$ are disjoint, and that it is crucial to consider the intersection. So let's choose examples where $P(A_1 \\cap A_2|B)$ is much larger than $P(A_1 \\cap A_2|C)$, to offset the other inequalities.\n\n*Story 1:* Consider two basketball players, one of whom is randomly chosen to shoot two free throws. The first player is very streaky, and always either makes both or misses both free throws, with probability 0.8 of making both (this is an extreme example chosen for simplicity, but we could also make it so the player has good days (on which there is a high chance of making both shots) and bad days (on which there is a high chance of missing both shots) without requiring *always* making both or missing both). The second player's free throws go in with probability 0.7, independently. Define the events as $A_j$: the $j$th free throw goes in; $B$: the free throw shooter is the first player; $C = B^c$. Then\n$$P(A_1|B) = P(A_2|B) = P(A_1 \\cap A_2|B) = P(A_1 \\cup A_2|B) = 0.8,$$\n$$P(A_1|C) = P(A_2|C) = 0.7, \\ P(A_1 \\cap A_2|C) = 0.49, \\ P(A_1 \\cup A_2|C) = 2 \\cdot 0.7 - 0.49 = 0.91.$$\n\n*Story 2:* Suppose that you can either take Good Class or Other Class, but not both. If you take Good Class, you'll attend lecture 70% of the time, and you will understand the material if and only if you attend lecture. If you take Other Class, you'll attend lecture 40% of the time and understand the material 40% of the time, but because the class is so poorly taught, the only way you understand the material is by studying on your own and not attending lecture. Defining the events as $A_1$: attend lecture; $A_2$: understand material; $B$: take Good Class; $C$: take Other Class,\n$$P(A_1|B) = P(A_2|B) = P(A_1 \\cap A_2|B) = P(A_1 \\cup A_2|B) = 0.7,$$\n$$P(A_1|C) = P(A_2|C) = 0.4, \\ P(A_1 \\cap A_2|C) = 0, \\ P(A_1 \\cup A_2|C) = 2 \\cdot 0.4 = 0.8.$$"),
        .init(
            id: "stat110-hw3-hw-4", setNumber: 3, kind: .homework,
            topic: "Gambler's Ruin", number: "4",
            title: "Calvin & Hobbes, win-by-2",
            body: "Calvin and Hobbes play a match consisting of a series of games, where Calvin has probability $p$ of winning each game (independently). They play with a \"win by two\" rule: the first player to win two games more than his opponent wins the match. Find the probability that Calvin wins the match (in terms of $p$), in two different ways:\n\n(a) by conditioning, using the law of total probability.\n\n(b) by interpreting the problem as a gambler's ruin problem.",
            firstLineHint: "(a) Let $C$ = Calvin wins, $X \\sim \\text{Bin}(2, p)$ = wins in first 2 games.",
            quantRelevance: 5,
            quantRationale: "Win-by-two is a famous interview problem. Recurrence + symmetry + gambler's ruin all in one — top-tier prep.",
            answer: "**(a)** Let $C$ be the event that Calvin wins the match, $X \\sim \\text{Bin}(2, p)$ be how many of the first 2 games he wins, and $q = 1 - p$. Then\n$$P(C) = P(C|X = 0) q^2 + P(C|X = 1)(2pq) + P(C|X = 2) p^2 = 2pq\\,P(C) + p^2,$$\nso $P(C) = \\frac{p^2}{1 - 2pq}$. This can also be written as $\\frac{p^2}{p^2 + q^2}$, since $p + q = 1$.\n\n*Miracle check:* Note that this should (and does) reduce to $1$ for $p = 1$, $0$ for $p = 0$, and $\\frac{1}{2}$ for $p = \\frac{1}{2}$. Also, it makes sense that the probability of Hobbes winning, which is $1 - P(C) = \\frac{q^2}{p^2 + q^2}$, can also be obtained by swapping $p$ and $q$.\n\n**(b) by interpreting the problem as a gambler's ruin problem.**\n\nThe problem can be thought of as a gambler's ruin where each player starts out with \\$2. So the probability that Calvin wins the match is\n$$\\frac{1 - (q/p)^2}{1 - (q/p)^4} = \\frac{(p^2 - q^2)/p^2}{(p^4 - q^4)/p^4} = \\frac{(p^2 - q^2)/p^2}{(p^2 - q^2)(p^2 + q^2)/p^4} = \\frac{p^2}{p^2 + q^2},$$\nwhich agrees with the above."),
        .init(
            id: "stat110-hw3-hw-5", setNumber: 3, kind: .homework,
            topic: "First-Step Recursion", number: "5",
            title: "Die running total — find $p_n$",
            body: "A fair die is rolled repeatedly, and a running total is kept (which is, at each time, the total of all the rolls up until that time). Let $p_n$ be the probability that the running total is ever *exactly* $n$ (assume the die will always be rolled enough times so that the running total will eventually exceed $n$, but it may or may not ever equal $n$).\n\n(a) Write down a recursive equation for $p_n$ (relating $p_n$ to earlier terms $p_k$ in a simple way). Your equation should be true for all positive integers $n$, so give a definition of $p_0$ and $p_k$ for $k < 0$ so that the recursive equation is true for small values of $n$.\n\n(b) Find $p_7$.\n\n(c) Give an intuitive explanation for the fact that $p_n \\to 1/3.5 = 2/7$ as $n \\to \\infty$.",
            firstLineHint: "(a) First-step analysis: condition on the first throw.",
            quantRelevance: 5,
            quantRationale: "Renewal/recursion classic. Asked in many forms at trading firms — running totals, level-hitting, sum-of-die-rolls.",
            answer: "**(a)** We will find something to condition on to reduce the case of interest to earlier, simpler cases. This is achieved by the useful strategy of *first step analysis*. Let $p_n$ be the probability that the running total is ever *exactly* $n$. Note that if, for example, the first throw is a 3, then the probability of reaching $n$ exactly is $p_{n-3}$ since starting from that point, we need to get a total of $n - 3$ exactly. So\n$$p_n = \\frac{1}{6}(p_{n-1} + p_{n-2} + p_{n-3} + p_{n-4} + p_{n-5} + p_{n-6}),$$\nwhere we define $p_0 = 1$ (which makes sense anyway since the running total is 0 before the first toss) and $p_k = 0$ for $k < 0$.\n\n**(b) Find $p_7$.**\n\nUsing the recursive equation in (a), we have\n$$p_1 = \\tfrac{1}{6}, \\quad p_2 = \\tfrac{1}{6}\\left(1 + \\tfrac{1}{6}\\right), \\quad p_3 = \\tfrac{1}{6}\\left(1 + \\tfrac{1}{6}\\right)^2,$$\n$$p_4 = \\tfrac{1}{6}\\left(1 + \\tfrac{1}{6}\\right)^3, \\quad p_5 = \\tfrac{1}{6}\\left(1 + \\tfrac{1}{6}\\right)^4, \\quad p_6 = \\tfrac{1}{6}\\left(1 + \\tfrac{1}{6}\\right)^5.$$\nHence,\n$$p_7 = \\tfrac{1}{6}(p_1 + p_2 + p_3 + p_4 + p_5 + p_6) = \\tfrac{1}{6}\\left(\\left(1 + \\tfrac{1}{6}\\right)^6 - 1\\right) \\approx 0.2536.$$\n\n**(c) Give an intuitive explanation for the fact that $p_n \\to 1/3.5 = 2/7$ as $n \\to \\infty$.**\n\nAn intuitive explanation is as follows. The average number thrown by the die is (total of dots)/6, which is $21/6 = 7/2$, so that every throw adds on an average of $7/2$. We can therefore expect to land on 2 out of every 7 numbers, and the probability of landing on any particular number is $2/7$. This result can be proved as follows (a proof was *not* required):\n$$p_{n+1} + 2p_{n+2} + 3p_{n+3} + 4p_{n+4} + 5p_{n+5} + 6p_{n+6}$$\n$$= p_{n+1} + 2p_{n+2} + 3p_{n+3} + 4p_{n+4} + 5p_{n+5}$$\n$$\\quad + p_n + p_{n+1} + p_{n+2} + p_{n+3} + p_{n+4} + p_{n+5}$$\n$$= p_n + 2p_{n+1} + 3p_{n+2} + 4p_{n+3} + 5p_{n+4} + 6p_{n+5}$$\n$$= \\ldots$$\n$$= p_{-5} + 2p_{-4} + 3p_{-3} + 4p_{-2} + 5p_{-1} + 6p_0 = 6.$$\nTaking the limit of the lefthand side as $n$ goes to $\\infty$, we have\n$$(1 + 2 + 3 + 4 + 5 + 6) \\lim_{n \\to \\infty} p_n = 6,$$\nso $\\lim_{n \\to \\infty} p_n = 2/7$."),
        .init(
            id: "stat110-hw3-hw-6", setNumber: 3, kind: .homework,
            topic: "First-Step Recursion", number: "6",
            title: "A vs B trivia — first correct wins",
            body: "Players $A$ and $B$ take turns in answering trivia questions, starting with player $A$ answering the first question. Each time $A$ answers a question, she has probability $p_1$ of getting it right. Each time $B$ plays, he has probability $p_2$ of getting it right.\n\n(a) If $A$ answers $m$ questions, what is the PMF of the number of questions she gets right?\n\n(b) If $A$ answers $m$ times and $B$ answers $n$ times, what is the PMF of the total number of questions they get right (you can leave your answer as a sum)? Describe exactly when/whether this is a Binomial distribution.\n\n(c) Suppose that the first player to answer correctly wins the game (with no predetermined maximum number of questions that can be asked). Find the probability that $A$ wins the game.",
            firstLineHint: "(c) Let $r = P(A \\text{ wins})$. Condition on the first round.",
            quantRelevance: 4,
            quantRationale: "Geometric / first-success problems are interview canon. The recursion-with-feedback is the move.",
            answer: "**(a)** The r.v. is $\\text{Bin}(m, p_1)$, so the PMF is $\\binom{m}{k} p_1^k (1 - p_1)^{m-k}$ for $k \\in \\{0, 1, \\ldots, m\\}$.\n\n**(b)** Let $T$ be the total number of questions they get right. To get a total of $k$ questions right, it must be that $A$ got 0 and $B$ got $k$, or $A$ got 1 and $B$ got $k - 1$, etc. These are disjoint events so the PMF is\n$$P(T = k) = \\sum_{j=0}^{k} \\binom{m}{j} p_1^j (1 - p_1)^{m-j} \\binom{n}{k-j} p_2^{k-j} (1 - p_2)^{n-(k-j)}$$\nfor $k \\in \\{0, 1, \\ldots, m + n\\}$, with the usual convention that $\\binom{n}{k}$ is 0 for $k > n$.\n\nThis is the $\\text{Bin}(m + n, p)$ distribution if $p_1 = p_2 = p$, as shown in class (using the story for the Binomial, or using Vandermonde's identity). For $p_1 \\neq p_2$, it's not a Binomial distribution, since the trials have different probabilities of success; having some trials with one probability of success and other trials with another probability of success isn't equivalent to having trials with some \"effective\" probability of success.\n\n**(c)** Let $r = P(A \\text{ wins})$. Conditioning on the results of the first question for each player, we have\n$$r = p_1 + (1 - p_1) p_2 \\cdot 0 + (1 - p_1)(1 - p_2) r,$$\nwhich gives $r = \\frac{p_1}{1 - (1 - p_1)(1 - p_2)} = \\frac{p_1}{p_1 + p_2 - p_1 p_2}$."),
        .init(
            id: "stat110-hw3-hw-7", setNumber: 3, kind: .homework,
            topic: "Binomial", number: "7",
            title: "Noisy channel with parity bit",
            body: "A message is sent over a noisy channel. The message is a sequence $x_1, x_2, \\ldots, x_n$ of $n$ bits ($x_i \\in \\{0, 1\\}$). Since the channel is noisy, there is a chance that any bit might be corrupted, resulting in an error (a 0 becomes a 1 or vice versa). Assume that the error events are independent. Let $p$ be the probability that an individual bit has an error ($0 < p < 1/2$). Let $y_1, y_2, \\ldots, y_n$ be the received message (so $y_i = x_i$ if there is no error in that bit, but $y_i = 1 - x_i$ if there is an error there).\n\nTo help detect errors, the $n$th bit is reserved for a parity check: $x_n$ is defined to be $0$ if $x_1 + x_2 + \\cdots + x_{n-1}$ is even, and 1 if $x_1 + x_2 + \\cdots + x_{n-1}$ is odd. When the message is received, the recipient checks whether $y_n$ has the same parity as $y_1 + y_2 + \\cdots + y_{n-1}$. If the parity is wrong, the recipient knows that at least one error occurred; otherwise, the recipient assumes that there were no errors.\n\n(a) For $n = 5, p = 0.1$, what is the probability that the received message has errors which go undetected?\n\n(b) For general $n$ and $p$, write down an expression (as a sum) for the probability that the received message has errors which go undetected.\n\n(c) Give a simplified expression, not involving a sum of a large number of terms, for the probability that the received message has errors which go undetected.\n\n*Hint for (c):* Letting\n$$a = \\sum_{k \\text{ even}, k \\geq 0} \\binom{n}{k} p^k (1 - p)^{n-k} \\quad \\text{and} \\quad b = \\sum_{k \\text{ odd}, k \\geq 1} \\binom{n}{k} p^k (1 - p)^{n-k},$$\nthe binomial theorem makes it possible to find simple expressions for $a + b$ and $a - b$, which then makes it possible to obtain $a$ and $b$.",
            firstLineHint: "Errors are undetected iff there are an even (and nonzero) number of them. Number of errors $\\sim \\text{Bin}(n, p)$.",
            quantRelevance: 4,
            quantRationale: "Binomial theorem trick — a beautiful generating-function-style move. Comes up in problems with parity / sign-alternating structure.",
            answer: "**(a)** Note that $\\sum_{i=1}^n x_i$ is even. If the number of errors is even (and nonzero), the errors will go undetected; otherwise, $\\sum_{i=1}^n y_i$ will be odd, so the errors will be detected.\n\nThe number of errors is $\\text{Bin}(n, p)$, so the probability of undetected errors when $n = 5, p = 0.1$ is\n$$\\binom{5}{2} p^2 (1 - p)^3 + \\binom{5}{4} p^4 (1 - p) \\approx 0.073.$$\n\n**(b)** By the same reasoning as in (a), the probability of undetected errors is\n$$\\sum_{k \\text{ even}, k \\geq 2} \\binom{n}{k} p^k (1 - p)^{n-k}.$$\n\n**(c)** Let $a, b$ be as in the hint. Then\n$$a + b = \\sum_{k \\geq 0} \\binom{n}{k} p^k (1 - p)^{n-k} = 1,$$\n$$a - b = \\sum_{k \\geq 0} \\binom{n}{k} (-p)^k (1 - p)^{n-k} = (1 - 2p)^n.$$\nSolving for $a$ and $b$ gives\n$$a = \\frac{1 + (1 - 2p)^n}{2} \\quad \\text{and} \\quad b = \\frac{1 - (1 - 2p)^n}{2}.$$\n$$\\sum_{k \\text{ even}, k \\geq 0} \\binom{n}{k} p^k (1 - p)^{n-k} = \\frac{1 + (1 - 2p)^n}{2}.$$\nSubtracting off the possibility of no errors, we have\n$$\\sum_{k \\text{ even}, k \\geq 2} \\binom{n}{k} p^k (1 - p)^{n-k} = \\frac{1 + (1 - 2p)^n}{2} - (1 - p)^n.$$\n*Miracle check:* note that letting $n = 5, p = 0.1$ here gives $0.073$, which agrees with (a); letting $p = 0$ gives 0, as it should; and letting $p = 1$ gives 0 for $n$ odd and 1 for $n$ even, which again makes sense."),
    ]
)

// MARK: - HW4 (Fall 2011)
// Source: https://stat110.hsites.harvard.edu/sites/g/files/omnuum10111/files/stat110/files/strategic_practice_and_homework_4.pdf

private let hw4: Stat110ProblemSet = .init(
    setNumber: 4,
    title: "Strategic Practice & Homework 4",
    pdfURL: "https://stat110.hsites.harvard.edu/sites/g/files/omnuum10111/files/stat110/files/strategic_practice_and_homework_4.pdf",
    problems: [
        // --- Strategic Practice 4 ---
        .init(
            id: "stat110-hw4-sp-1.1", setNumber: 4, kind: .strategicPractice,
            topic: "Distributions and Expected Values for Discrete RVs", number: "1.1",
            title: "Same distribution but $X = Y$ never",
            body: "Find an example of two discrete random variables $X$ and $Y$ (on the same sample space) such that $X$ and $Y$ have the same distribution (i.e., same PMF and same CDF), but the event $X = Y$ *never* occurs.",
            firstLineHint: "Try $X \\sim \\text{Bern}(1/2)$ and $Y = 1 - X$.",
            quantRelevance: 4,
            quantRationale: "Tests the crucial distinction between \"same distribution\" and \"equal as random variables\" — a frequent interview gotcha.",
            answer: "Let $X \\sim \\text{Bern}(1/2)$ and $Y = 1 - X$. Then $Y$ is also $\\text{Bern}(1/2)$ by symmetry, but $X = Y$ is impossible. More generally, $X \\sim \\text{Bin}(n, 1/2)$ and $Y = n - X$ for any odd $n$ also works."),
        .init(
            id: "stat110-hw4-sp-1.2", setNumber: 4, kind: .strategicPractice,
            topic: "Distributions and Expected Values for Discrete RVs", number: "1.2",
            title: "Day-of-week and the next day",
            body: "Let $X$ be a random day of the week, coded so that Monday is 1, Tuesday is 2, etc. (so $X$ takes values $1, 2, \\ldots, 7$, with equal probabilities). Let $Y$ be the next day after $X$ (again represented as an integer between 1 and 7). Do $X$ and $Y$ have the same distribution? What is $P(X < Y)$?",
            firstLineHint: "$Y$ is also uniform on $\\{1, \\ldots, 7\\}$; $P(X < Y) = P(X \\neq 7)$.",
            quantRelevance: 3,
            quantRationale: "Same-distribution-but-dependent — pairs with the previous problem.",
            answer: "$Y$ has the same distribution since $Y$ is also equally likely to be any day. $P(X < Y) = P(X \\neq 7) = 6/7$."),
        .init(
            id: "stat110-hw4-sp-1.3", setNumber: 4, kind: .strategicPractice,
            topic: "Distributions and Expected Values for Discrete RVs", number: "1.3",
            title: "Geometric CDF (tosses until first heads)",
            body: "A coin is tossed repeatedly until it lands Heads for the first time. Let $X$ be the number of tosses that are required (including the toss that landed Heads), and let $p$ be the probability of Heads. Find the CDF of $X$, and for $p = 1/2$ sketch its graph.",
            firstLineHint: "$X - 1 \\sim \\text{Geom}(p)$. $P(X > x) = (1-p)^{\\lfloor x \\rfloor}$ since the first $\\lfloor x \\rfloor$ tosses must all be tails.",
            quantRelevance: 5,
            quantRationale: "Geometric CDF — foundational discrete distribution. Asked verbatim at trading firms.",
            answer: "By the story of the Geometric, $X - 1 \\sim \\text{Geom}(p)$. The PMF is $P(X = k) = p(1 - p)^{k-1}$ for $k \\in \\{1, 2, 3, \\ldots\\}$. Directly,\n$$P(X \\leq x) = 1 - P(X > x) = 1 - (1 - p)^{\\lfloor x \\rfloor}$$\nfor $x \\geq 1$, and 0 for $x < 1$. For a fair coin, $F(x) = 1 - \\frac{1}{2^{\\lfloor x \\rfloor}}$ for $x \\geq 1$, 0 otherwise — a right-continuous step function with jumps of $p(1-p)^{k-1}$ at each integer $k$."),
        .init(
            id: "stat110-hw4-sp-1.4", setNumber: 4, kind: .strategicPractice,
            topic: "Distributions and Expected Values for Discrete RVs", number: "1.4",
            title: "E(X) huge but Y > X almost always",
            body: "Are there discrete random variables $X$ and $Y$ such that $E(X) > 100 E(Y)$ but $Y$ is greater than $X$ with probability at least $0.99$?",
            firstLineHint: "Yes — let $X$ be a rare-but-huge lottery payoff, $Y$ a small constant.",
            quantRelevance: 5,
            quantRationale: "St. Petersburg-style intuition pump — the gap between expectation and \"usually larger.\" Interview canon.",
            answer: "Yes. Make $X$ usually 0 but on rare occasions extremely large; $Y$ moderate. For example, let $X = 10^6$ with probability $1/100$ and 0 with probability $99/100$ (so $E(X) = 10^4$), and let $Y = 1$ identically. Then $E(X) = 10000 > 100 = 100 E(Y)$, but $Y > X$ happens whenever $X = 0$, i.e. with probability $99/100$."),
        .init(
            id: "stat110-hw4-sp-1.5", setNumber: 4, kind: .strategicPractice,
            topic: "Distributions and Expected Values for Discrete RVs", number: "1.5",
            title: "$E(X) = \\sum_{n=0}^\\infty (1 - F(n))$",
            body: "Let $X$ be a discrete r.v. with possible values $1, 2, 3, \\ldots$. Let $F(x) = P(X \\leq x)$ be the CDF of $X$. Show that\n$$E(X) = \\sum_{n=0}^{\\infty} \\left(1 - F(n)\\right).$$\n*Hint:* organize the order of summation carefully, using the fact that, for example, $P(X > 3) = P(X = 4) + P(X = 5) + \\cdots.$",
            firstLineHint: "$\\sum_{n=0}^\\infty (1 - F(n)) = \\sum_{n=0}^\\infty \\sum_{k > n} P(X = k)$; swap order of summation.",
            quantRelevance: 5,
            quantRationale: "Tail-sum formula for expectation — appears constantly in trading-mathematical questions about waiting times.",
            answer: "$$\\sum_{n=0}^{\\infty}(1 - F(n)) = \\sum_{n=0}^{\\infty} P(X > n) = \\sum_{n=0}^{\\infty} \\sum_{k=n+1}^{\\infty} P(X = k).$$\nFor each $k$, $P(X = k)$ appears exactly $k$ times (once for each $n < k$). Rearranging,\n$$\\sum_{n=0}^{\\infty}(1 - F(n)) = \\sum_{k=1}^{\\infty} k \\cdot P(X = k) = E(X).$$"),
        .init(
            id: "stat110-hw4-sp-1.6", setNumber: 4, kind: .strategicPractice,
            topic: "Distributions and Expected Values for Discrete RVs", number: "1.6",
            title: "Expected wait for someone better than $C_1$",
            body: "Job candidates $C_1, C_2, \\ldots$ are interviewed one by one, and the interviewer compares them and keeps an updated list of rankings (if $n$ candidates have been interviewed so far, this is a list of the $n$ candidates, from best to worst). Assume that there is no limit on the number of candidates available, that for any $n$ the candidates $C_1, C_2, \\ldots, C_n$ are equally likely to arrive in any order, and that there are no ties in the rankings given by the interview.\n\nLet $X$ be the index of the first candidate to come along who ranks as better than the very first candidate $C_1$ (so $C_X$ is better than $C_1$, but the candidates after 1 but prior to $X$ (if any) are worse than $C_1$). For example, if $C_2$ and $C_3$ are worse than $C_1$ but $C_4$ is better than $C_1$, then $X = 4$. All $4!$ orderings of the first 4 candidates are equally likely.\n\nWhat is $E(X)$ (which is a measure of how long, on average, the interviewer needs to wait to find someone better than the very first candidate)? *Hint:* find $P(X > n)$ by interpreting what $X > n$ says about how $C_1$ compares with other candidates, and then apply the result of the previous problem.",
            firstLineHint: "$P(X > n) = 1/n$ for $n \\geq 1$: $C_1$ must be the highest-ranked of the first $n$.",
            quantRelevance: 5,
            quantRationale: "$E(X) = \\infty$ — harmonic-divergence intuition. Famous interview problem.",
            answer: "For $n \\geq 2$, $P(X > n)$ is the probability that $C_1$ is the highest-ranked of the first $n$, which is $1/n$ by symmetry. $P(X > 0) = P(X > 1) = 1$. Applying the previous problem:\n$$E(X) = \\sum_{n=0}^{\\infty} P(X > n) = 1 + 1 + \\sum_{n=2}^{\\infty} \\frac{1}{n} = \\infty,$$\nsince the harmonic series diverges. The wait-time is infinite on average — but the divergence is logarithmic, so even with millions of candidates the average wait isn't huge."),
        .init(
            id: "stat110-hw4-sp-2.1", setNumber: 4, kind: .strategicPractice,
            topic: "Indicator RVs and Linearity of Expectation", number: "2.1",
            title: "Birthday matches in a group of 50",
            body: "A group of 50 people are comparing their birthdays (as usual, assume their birthdays are independent, are not February 29, etc.). Find the expected number of pairs of people with the same birthday, and the expected number of days in the year on which at least two of these people were born.",
            firstLineHint: "Indicator per pair for shared birthday: $\\binom{50}{2} / 365$. Indicator per day for ≥2 births that day.",
            quantRelevance: 5,
            quantRationale: "Indicator + linearity — the move appears in nearly every quant interview involving expectations.",
            answer: "Indicator per pair: $E(\\text{pairs}) = \\binom{50}{2} \\cdot \\frac{1}{365}$ by linearity.\n\nIndicator $D_i$ for day $i$ having $\\geq 2$ births: $P(D_i = 1) = 1 - (364/365)^{50} - 50 \\cdot (1/365)(364/365)^{49}$. By linearity,\n$$E\\left(\\sum D_i\\right) = 365\\left(1 - (364/365)^{50} - 50 \\cdot (1/365)(364/365)^{49}\\right).$$"),
        .init(
            id: "stat110-hw4-sp-2.2", setNumber: 4, kind: .strategicPractice,
            topic: "Indicator RVs and Linearity of Expectation", number: "2.2",
            title: "Haribo bags to 20 students",
            body: "A total of 20 bags of Haribo gummi bears are randomly distributed to the 20 students in a certain Stat 110 section. Each bag is obtained by a random student, and the outcomes of who gets which bag are independent. Find the average number of bags of gummi bears that the first three students get in total, and find the average number of students who get at least one bag.",
            firstLineHint: "Each bag is independently uniform → student $j$'s count $\\sim \\text{Bin}(20, 1/20)$. Indicator for \"at least one\".",
            quantRelevance: 4,
            quantRationale: "Standard linearity-of-indicators — variant of empty-box / coupon-collector.",
            answer: "Let $X_j$ = bags student $j$ gets. $X_j \\sim \\text{Bin}(20, 1/20)$, so $E(X_j) = 1$ and $E(X_1 + X_2 + X_3) = 3$.\n\nIndicator $I_j$ for student $j$ getting at least one bag: $P(I_j = 1) = 1 - (19/20)^{20}$. By linearity,\n$$E\\left(\\sum_{j=1}^{20} I_j\\right) = 20\\left(1 - (19/20)^{20}\\right) \\approx 12.83.$$"),
        .init(
            id: "stat110-hw4-sp-2.3", setNumber: 4, kind: .strategicPractice,
            topic: "Indicator RVs and Linearity of Expectation", number: "2.3",
            title: "100 shoelaces — expected steps and loops",
            body: "There are 100 shoelaces in a box. At each stage, you pick two random ends and tie them together. Either this results in a longer shoelace (if the two ends came from different pieces), or it results in a loop (if the two ends came from the same piece). What are the expected number of steps until everything is in loops, and the expected number of loops after everything is in loops? (This is a famous interview problem; leave the latter answer as a sum.)\n\n*Hint:* for each step, create an indicator r.v. for whether a loop was created then, and note that the number of free ends goes down by 2 after each step.",
            firstLineHint: "Free ends drop by 2 each step → exactly 100 steps. Indicator per step: $P(\\text{loop at step with } n \\text{ pieces left}) = 1/(2n-1)$.",
            quantRelevance: 5,
            quantRationale: "Famous interview problem at Jane Street, Citadel, etc. Indicator + clever counting.",
            answer: "Initially 200 free ends; each step decreases free ends by 2 (either tied to different piece or formed a loop). So exactly **100 steps** are always needed.\n\nLet $I_j$ = indicator of a new loop at step $j$. When $n$ unlooped pieces are present (so $2n$ free ends), $P(\\text{loop}) = n / \\binom{2n}{2} = 1/(2n-1)$. By linearity, expected loops:\n$$\\sum_{n=1}^{100} \\frac{1}{2n - 1}.$$"),
        .init(
            id: "stat110-hw4-sp-2.4", setNumber: 4, kind: .strategicPractice,
            topic: "Indicator RVs and Linearity of Expectation", number: "2.4",
            title: "Hash table collisions",
            body: "A *hash table* is a commonly used data structure in computer science, allowing for fast information retrieval. For example, suppose we want to store some people's phone numbers. Assume that no two of the people have the same name. For each name $x$, a *hash function* $h$ is used, where $h(x)$ is the location to store $x$'s phone number. After such a table has been computed, to look up $x$'s phone number one just recomputes $h(x)$ and then looks up what is stored in that location.\n\nThe hash function $h$ is deterministic, since we don't want to get different results every time we compute $h(x)$. But $h$ is often chosen to be *pseudorandom*. For this problem, assume that true randomness is used. So let there be $k$ people, with each person's phone number stored in a random location (independently), represented by an integer between 1 and $n$. It then might happen that one location has more than one phone number stored there, if two different people $x$ and $y$ end up with the same random location for their information to be stored.\n\nFind the expected number of locations with no phone numbers stored, the expected number with exactly one phone number, and the expected number with more than one phone number (should these quantities add up to $n$?).",
            firstLineHint: "Indicator per location for being empty: $P = (1 - 1/n)^k$. For exactly one: $k/n \\cdot (1-1/n)^{k-1}$.",
            quantRelevance: 5,
            quantRationale: "Hash table / balls-in-boxes — quant interview canon, CS-flavored.",
            answer: "Indicator $I_j$ for location $j$ being empty: $P(I_j = 1) = (1 - 1/n)^k$. By linearity:\n$$E(\\text{empty}) = n(1 - 1/n)^k.$$\nProbability a specific location has exactly one number: $\\frac{k}{n}(1 - 1/n)^{k-1}$, so\n$$E(\\text{exactly one}) = k(1 - 1/n)^{k-1}.$$\nSum of all three expected counts is $n$ by linearity, so\n$$E(\\text{more than one}) = n - n(1 - 1/n)^k - k(1 - 1/n)^{k-1}.$$"),

        // --- Homework 4 ---
        .init(
            id: "stat110-hw4-hw-1", setNumber: 4, kind: .homework,
            topic: nil, number: "1",
            title: "Convert F to G(x) = P(X < x)",
            body: "Let $X$ be a r.v. whose possible values are $0, 1, 2, \\ldots$, with CDF $F$. In some countries, rather than using a CDF, the convention is to use the function $G$ defined by $G(x) = P(X < x)$ to specify a distribution. Find a way to convert from $F$ to $G$, i.e., if $F$ is a known function show how to obtain $G(x)$ for all real $x$.",
            firstLineHint: "$G(x) = F(x) - P(X = x)$. For non-integer $x$, $P(X = x) = 0$, so $G = F$. For integer $x$, subtract the jump.",
            quantRelevance: 4,
            quantRationale: "Tests the CDF/jump intuition — a subtle but common interview question.",
            answer: "$G(x) = P(X \\leq x) - P(X = x) = F(x) - P(X = x)$. If $x \\notin \\{0, 1, 2, \\ldots\\}$, $P(X = x) = 0$ so $G(x) = F(x)$. For nonnegative integer $x$, $P(X = x) = F(x) - F(x - 1/2)$ (the jump). Thus\n$$G(x) = \\begin{cases} F(x) & \\text{if } x \\notin \\{0, 1, 2, \\ldots\\} \\\\ F(x - 1/2) & \\text{if } x \\in \\{0, 1, 2, \\ldots\\}. \\end{cases}$$\nMore compactly: $G(x) = \\lim_{t \\to x^-} F(t) = F(\\lceil x \\rceil - 1)$."),
        .init(
            id: "stat110-hw4-hw-2", setNumber: 4, kind: .homework,
            topic: nil, number: "2",
            title: "Eggs that hatch and survive",
            body: "There are $n$ eggs, each of which hatches a chick with probability $p$ (independently). Each of these chicks survives with probability $r$, independently. What is the distribution of the number of chicks that hatch? What is the distribution of the number of chicks that survive? (Give the PMFs; also give the names of the distributions and their parameters, if they are distributions we have seen in class.)",
            firstLineHint: "Hatched: $\\text{Bin}(n, p)$. Survived: $\\text{Bin}(n, pr)$ (each egg is an independent Bernoulli with success = hatched and survived).",
            quantRelevance: 5,
            quantRationale: "Binomial thinning / composition of Bernoulli trials — appears across signal-processing and trading interviews.",
            answer: "Let $H$ = number of eggs that hatch, $X$ = number that survive.\n\n$H \\sim \\text{Bin}(n, p)$ with PMF $P(H = k) = \\binom{n}{k} p^k (1-p)^{n-k}$ for $k = 0, 1, \\ldots, n$.\n\nEach egg independently has probability $pr$ of hatching a chick that survives. So $X \\sim \\text{Bin}(n, pr)$ with PMF $P(X = k) = \\binom{n}{k} (pr)^k (1-pr)^{n-k}$."),
        .init(
            id: "stat110-hw4-hw-3", setNumber: 4, kind: .homework,
            topic: nil, number: "3",
            title: "Couple wants ≥1 of each gender",
            body: "A couple decides to keep having children until they have at least one boy and at least one girl, and then stop. Assume they never have twins, that the \"trials\" are independent with probability $1/2$ of a boy, and that they are fertile enough to keep producing children indefinitely. What is the expected number of children?",
            firstLineHint: "After child 1, we need a different gender. Waiting time to a different result is $\\text{Geom}(1/2) + 1$.",
            quantRelevance: 5,
            quantRationale: "Conditional waiting time + geometric. Family-planning variant of classic interview material.",
            answer: "Let $X$ = number of children needed, starting with the 2nd child, to obtain one whose gender is *different* from the firstborn. Each subsequent trial succeeds with probability $1/2$, so $X - 1 \\sim \\text{Geom}(1/2)$ and $E(X) = 2$. Total: $E(X + 1) = E(X) + 1 = 3$. *Miracle check:* answer of 2 or lower would be a miracle since at least 2 children are always needed; 4 or higher would be a miracle since 4 is the expected count needed to have a boy and a girl with the boy older."),
        .init(
            id: "stat110-hw4-hw-4", setNumber: 4, kind: .homework,
            topic: nil, number: "4",
            title: "Empty boxes",
            body: "Randomly, $k$ distinguishable balls are placed into $n$ distinguishable boxes, with all possibilities equally likely. Find the expected number of empty boxes.",
            firstLineHint: "Indicator per box for being empty: $P = (1 - 1/n)^k$. Sum and use linearity.",
            quantRelevance: 5,
            quantRationale: "Empty-boxes / hash-table sibling — interview canon, appears in occupancy / coupon-collector problems.",
            answer: "Let $I_j$ = indicator that box $j$ is empty. $P(I_j = 1) = (1 - 1/n)^k$ since balls are placed in independent random locations. By linearity,\n$$E\\left(\\sum_{j=1}^n I_j\\right) = n(1 - 1/n)^k.$$\n*Miracle check:* for any $k \\geq 1$, at most $n-1$ boxes can be empty, so $n(1-1/n)^k \\leq n-1$ — indeed, $n(1-1/n) = n-1$."),
        .init(
            id: "stat110-hw4-hw-5", setNumber: 4, kind: .homework,
            topic: nil, number: "5",
            title: "Fisher exact test — conditional dist of $X | X+Y$",
            body: "A scientist wishes to study whether men or women are more likely to have a certain disease, or whether they are equally likely. A random sample of $m$ women and $n$ men is gathered, and each person is tested for the disease (assume for this problem that the test is completely accurate). The numbers of women and men in the sample who have the disease are $X$ and $Y$ respectively, with $X \\sim \\text{Bin}(m, p_1)$ and $Y \\sim \\text{Bin}(n, p_2)$. Here $p_1$ and $p_2$ are unknown, and we are interested in testing the \"null hypothesis\" $p_1 = p_2$.\n\n(a) Consider a 2 by 2 table listing with rows corresponding to disease status and columns corresponding to gender, with each entry the count of how many people have that disease status and gender (so $m + n$ is the sum of all 4 entries). Suppose that it is observed that $X + Y = r$.\n\nThe *Fisher exact test* is based on conditioning on both the row and column sums, so $m, n, r$ are all treated as fixed, and then seeing if the observed value of $X$ is \"extreme\" compared to this conditional distribution. Assuming the null hypothesis, use Bayes' Rule to find the conditional PMF of $X$ given $X + Y = r$. Is this a distribution we have studied in class? If so, say which (and give its parameters).\n\n(b) Give an intuitive explanation for the distribution of (a), explaining how this problem relates to other problems we've seen, and why $p_1$ disappears (magically?) in the distribution found in (a).",
            firstLineHint: "Under $H_0$, $X + Y \\sim \\text{Bin}(m+n, p)$. Bayes: $P(X = x | X+Y=r) = P(Y=r-x)P(X=x)/P(X+Y=r)$. The $p$'s cancel.",
            quantRelevance: 5,
            quantRationale: "Hypergeometric emerges from Binomials conditioned on sum — beautiful and a common interview probe.",
            answer: "**(a)** Under $H_0$ with $p = p_1 = p_2$, $X \\sim \\text{Bin}(m, p)$, $Y \\sim \\text{Bin}(n, p)$ independent, so $X + Y \\sim \\text{Bin}(m+n, p)$. By Bayes,\n$$P(X = x | X + Y = r) = \\frac{P(Y = r-x) P(X = x)}{P(X+Y = r)} = \\frac{\\binom{n}{r-x}\\binom{m}{x}}{\\binom{m+n}{r}}.$$\nThe $p^r(1-p)^{m+n-r}$ factors cancel. This is **Hypergeometric** with parameters $m, n, r$.\n\n**(b)** Same structure as the elk capture-recapture problem. Women correspond to tagged elk; men to untagged; the $r$ diseased people correspond to a fresh sample of size $r$ from the $m + n$ population. Once we know $X + Y = r$, the set of $r$ diseased people is equally likely to be any $r$-subset of the $m + n$ — so $p$ no longer matters: we're sampling without replacement from a known population."),
        .init(
            id: "stat110-hw4-hw-6", setNumber: 4, kind: .homework,
            topic: nil, number: "6",
            title: "Bubble sort — expected inversions & comparisons",
            body: "Consider the following algorithm for sorting a list of $n$ distinct numbers into increasing order. Initially they are in a random order, with all orders equally likely. The algorithm compares the numbers in positions 1 and 2, and swaps them if needed, then it compares the new numbers in positions 2 and 3, and swaps them if needed, etc., until it has gone through the whole list. Call this one \"sweep\" through the list. After the first sweep, the largest number is at the end, so the second sweep (if needed) only needs to work with the first $n - 1$ positions. Similarly, the third sweep (if needed) only needs to work with the first $n - 2$ positions, etc. Sweeps are performed until $n - 1$ sweeps have been completed or there is a swapless sweep.\n\n(a) An *inversion* is a pair of numbers that are out of order (e.g., 12345 has no inversions, while 53241 has 8 inversions). Find the expected number of inversions in the original list.\n\n(b) Show that the expected number of comparisons is between $\\frac{1}{2}\\binom{n}{2}$ and $\\binom{n}{2}$.\n*Hint for (b):* for one bound, think about how many comparisons are made if $n - 1$ sweeps are done; for the other bound, use Part (a).",
            firstLineHint: "(a) Indicator per pair, $1/2$ each by symmetry. (b) Lower: $X \\geq V$ (every inversion must be repaired). Upper: at most $(n-1) + (n-2) + \\cdots + 1$ comparisons.",
            quantRelevance: 5,
            quantRationale: "Algorithm-analysis-meets-probability — favorite CS/quant crossover interview problem.",
            answer: "**(a)** $\\binom{n}{2}$ pairs, each equally likely to be in either order. By symmetry and linearity,\n$$E(\\text{inversions}) = \\frac{1}{2}\\binom{n}{2}.$$\n\n**(b)** Let $X$ = comparisons, $V$ = inversions. Every inversion must be repaired, so $X \\geq V$, giving $E(X) \\geq \\frac{1}{2}\\binom{n}{2}$. Maximum comparisons with $n - 1$ sweeps: $(n-1) + (n-2) + \\cdots + 1 = \\binom{n}{2}$, so $X \\leq \\binom{n}{2}$. Hence $\\frac{1}{2}\\binom{n}{2} \\leq E(X) \\leq \\binom{n}{2}$. (This algorithm is called *bubble sort*.)"),
        .init(
            id: "stat110-hw4-hw-7", setNumber: 4, kind: .homework,
            topic: nil, number: "7",
            title: "Records in a sequence of i.i.d. jumps",
            body: "Athletes compete one at a time at the high jump. Let $X_j$ be how high the $j$th jumper jumped, with $X_1, X_2, \\ldots$ i.i.d. with a continuous distribution. We say that the $j$th jumper set a *record* if $X_j$ is greater than all of $X_{j-1}, \\ldots, X_1$.\n\n(a) Is the event \"the 110th jumper sets a record\" independent of the event \"the 111th jumper sets a record\"? Justify your answer by finding the relevant probabilities in the definition of independence *and* with an intuitive explanation.\n\n(b) Find the mean number of records among the first $n$ jumpers (as a sum). What happens to the mean as $n \\to \\infty$?",
            firstLineHint: "(a) $P(I_j = 1) = 1/j$ by symmetry. (b) Sum and recognize the harmonic series.",
            quantRelevance: 5,
            quantRationale: "Records / i.i.d. ranking — appears in algorithm problems (secretary problem, online learning), and harmonic-series divergence is interview canon.",
            answer: "**(a)** Yes — independent. By symmetry $P(I_j = 1) = 1/j$. Also,\n$$P(I_{110} = 1, I_{111} = 1) = \\frac{109!}{111!} = \\frac{1}{110 \\cdot 111},$$\nsince the 110th and 111th both being records means the highest of the first 111 is in position 111, second highest in position 110, and the other 109 in any order. So $P(I_{110} = 1, I_{111} = 1) = P(I_{110})P(I_{111})$. Intuitively, knowing that the 111th jumper sets a record gives no information about how the first 110 jumps compare *among themselves*.\n\n**(b)** By linearity,\n$$E(\\text{records}) = \\sum_{j=1}^{n} \\frac{1}{j} \\to \\infty \\text{ as } n \\to \\infty,$$\nsince this is the harmonic series."),
    ]
)
