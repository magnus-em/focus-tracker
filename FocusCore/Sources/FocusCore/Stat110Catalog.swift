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
                quantRationale: String = "") {
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
    public static let all: [Stat110ProblemSet] = [hw2, hw3]

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
            topic: "Continuing with Conditioning", number: "1.1",
            title: "Biased Monty Hall",
            body: "Consider the Monty Hall problem, except that Monty enjoys opening Door 2 more than he enjoys opening Door 3, and if he has a choice between opening these two doors, he opens Door 2 with probability p, where 1/2 ≤ p ≤ 1.\n\nThere are three doors, behind one of which there is a car (which you want) and behind the other two of which there are goats. Initially, all possibilities are equally likely for where the car is. You choose Door 1. Monty opens a goat door and offers you the option of switching. Monty knows where the car is, will always open a goat door and offer the option of switching, and chooses Door 2 with probability p (with 1/2 ≤ p ≤ 1) when he has a choice.\n\n(a) Find the unconditional probability that the strategy of always switching succeeds.\n(b) Find the probability that always switching succeeds, given that Monty opens Door 2.\n(c) Find the probability that always switching succeeds, given that Monty opens Door 3.",
            firstLineHint: "(a) Let Cⱼ = car behind door j, W = win by switching. LOTP: P(W) = P(W|C₁)·(1/3) + P(W|C₂)·(1/3) + P(W|C₃)·(1/3) = 0 + 1/3 + 1/3 = 2/3.",
            quantRelevance: 4,
            quantRationale: "Monty Hall is the canonical interview problem for testing conditional probability. The biased variant tests deeper Bayes reasoning."),
        .init(
            id: "stat110-hw3-sp-1.2", setNumber: 3, kind: .strategicPractice,
            topic: "Continuing with Conditioning", number: "1.2",
            title: "True/False on independence of X, Y, Z",
            body: "For each statement below, either show that it is true or give a counterexample. Throughout, X, Y, Z are discrete random variables.\n\n(a) If X and Y are independent and Y and Z are independent, then X and Z are independent.\n(b) If X and Y are independent, then they are conditionally independent given Z.\n(c) If X and Y are conditionally independent given Z, then they are independent.\n(d) If X and Y have the same distribution given Z, i.e., for all a and z, we have P(X = a | Z = z) = P(Y = a | Z = z), then X and Y have the same distribution.",
            firstLineHint: "(a) False — take X = Z. (b) False — fire/popcorn example. (c) False — chess opponent of unknown strength, or coin-in-hat. (d) True — by LOTP: P(X = a) = Σ P(X = a | Z = z) P(Z = z).",
            quantRelevance: 5,
            quantRationale: "THE highest-yield problem in Stat 110 for quant interviews. These four traps are the deep water that separates careful thinkers from casual ones."),

        .init(
            id: "stat110-hw3-sp-2.1", setNumber: 3, kind: .strategicPractice,
            topic: "Simpson's Paradox", number: "2.1",
            title: "Simpson's Paradox — two-event vs three-event",
            body: "(a) Is it possible to have events A, B, E such that P(A|E) < P(B|E) and P(A|Eᶜ) < P(B|Eᶜ), yet P(A) > P(B)? That is, A is less likely than B given that E is true, and also given that E is false, yet A is more likely than B if given no information about E. Show this is impossible (with a short proof) or find a counterexample (with a \"story\").\n\n(b) Is it possible to have events A, B, E such that P(A|B,E) < P(A|Bᶜ,E) and P(A|B,Eᶜ) < P(A|Bᶜ,Eᶜ), yet P(A|B) > P(A|Bᶜ)? That is, given E is true, learning B is evidence against A, and similarly given Eᶜ; but given no information about E, learning B is evidence in favor of A. Show this is impossible or find a counterexample with a story.",
            firstLineHint: "(a) Not possible — straight LOTP. (b) Yes — this is the structure of Simpson's Paradox.",
            solutionSteps: [
                .init(title: "(a) Set up LOTP",
                      body: "For part (a) we want $P(A) > P(B)$ given that $A$ is less likely than $B$ both inside and outside $E$. Try writing both $P(A)$ and $P(B)$ as a weighted average via the law of total probability — same weights $P(E)$ and $P(E^c)$ in each."),
                .init(title: "(a) Finish the argument",
                      body: "$$P(A) = P(A \\mid E)P(E) + P(A \\mid E^c)P(E^c)$$\n$$< P(B \\mid E)P(E) + P(B \\mid E^c)P(E^c) = P(B).$$\nThe weighted average of two smaller numbers is smaller. So with just **two** events, this paradox **cannot** happen."),
                .init(title: "(b) Why three events differ",
                      body: "Now we have three events $A, B, E$, and we condition on $E$ vs $E^c$. The point: conditioning on $E$ partitions the world differently than conditioning on $B$. The LOTP argument from (a) no longer applies because the weights $P(E \\mid B)$ and $P(E \\mid B^c)$ are different. So the paradox **can** happen — and this is exactly Simpson's Paradox."),
                .init(title: "(b) Doctor story",
                      body: "Two doctors, Dr. Hibbert and Dr. Nick. Each performs heart transplants ($E$) and bandaid removals ($E^c$). Let $A$ = surgery succeeds, $B$ = Dr. Nick did the surgery (so $B^c$ = Dr. Hibbert).\n\nDr. Hibbert is the better surgeon at both:\n$$P(A \\mid B, E) < P(A \\mid B^c, E),$$\n$$P(A \\mid B, E^c) < P(A \\mid B^c, E^c).$$\nBut Hibbert does mostly hearts (hard), while Nick does mostly bandaids (easy)."),
                .init(title: "Full solution — specific numbers",
                      body: "Hibbert: 90 heart transplants (70 successful), 10 bandaid removals (10 successful). Nick: 10 hearts (2 successful), 90 bandaids (81 successful).\n\nWithin each surgery type, Hibbert wins. But aggregate success rates:\n$$P(A \\mid B^c) = 80 / 100 = 80\\% \\text{ (Hibbert)},$$\n$$P(A \\mid B) = 83 / 100 = 83\\% \\text{ (Nick)}.$$\nSo $P(A \\mid B) > P(A \\mid B^c)$ — the worse doctor *appears* better on aggregate.\n\n**This is why you must control for confounders.** Real-world example: a player can have higher batting average than another every season individually, yet a lower batting average when seasons are aggregated."),
            ],
            quantRelevance: 5,
            quantRationale: "Simpson's Paradox is a real risk-management trap. Understanding the structure is mandatory for anyone touching data at a hedge fund."),
        .init(
            id: "stat110-hw3-sp-2.2", setNumber: 3, kind: .strategicPractice,
            topic: "Simpson's Paradox", number: "2.2",
            title: "Lisa, Homer, and Stampy",
            body: "Consider the following conversation from an episode of The Simpsons:\n\n   Lisa: Dad, I think he's an ivory dealer! His boots are ivory, his hat is ivory, and I'm pretty sure that check is ivory.\n   Homer: Lisa, a guy who's got lots of ivory is less likely to hurt Stampy than a guy whose ivory supplies are low.\n\nHomer and Lisa are debating whether the man (named Blackheart) is likely to hurt Stampy the Elephant if they sell Stampy to him.\n\n(a) Define clear notation for the events of interest.\n(b) Express Lisa's and Homer's arguments as conditional probability statements.\n(c) Assume it is true that someone who has a lot of a commodity will have less desire to acquire more of the commodity. Explain what is wrong with Homer's reasoning that the evidence about Blackheart makes it less likely he will harm Stampy.",
            firstLineHint: "Three events run the conversation: $H$ = will hurt Stampy, $L$ = lots of ivory, $D$ = ivory dealer.",
            solutionSteps: [
                .init(title: "(a) Define the events",
                      body: "Three events keep the argument honest:\n\n• $H$ = the man will hurt Stampy.\n• $L$ = the man has lots of ivory.\n• $D$ = the man is an ivory dealer.\n\nLisa's argument involves all three; Homer's argument only uses $H$ and $L$. That's the asymmetry."),
                .init(title: "(b) Lisa's argument",
                      body: "Lisa observes $L$ is true. She suggests (reasonably) that lots of ivory makes the dealer hypothesis more likely:\n$$P(D \\mid L) > P(D).$$\nImplicitly, she assumes a dealer is more dangerous, so lots of ivory raises the probability of harm:\n$$P(H \\mid L) > P(H \\mid L^c).$$"),
                .init(title: "(b) Homer's argument",
                      body: "Homer asserts the opposite — having more ivory means less *need* to acquire ivory, less reason to harm Stampy for the ivory:\n$$P(H \\mid L) < P(H \\mid L^c).$$\nNote: he never conditions on $D$. That's the move that's about to backfire."),
                .init(title: "(c) Where Homer goes wrong",
                      body: "Homer's local intuition is **not wrong** — it can hold within the dealer group and within the non-dealer group separately:\n$$P(H \\mid L, D) < P(H \\mid L^c, D),$$\n$$P(H \\mid L, D^c) < P(H \\mid L^c, D^c).$$\nBut these two within-group inequalities do **not** imply $P(H \\mid L) < P(H \\mid L^c)$. The marginal can flip the within-group direction — that's Simpson's Paradox."),
                .init(title: "Full solution — why this is Simpson's",
                      body: "Observing $L$ (lots of ivory) shifts $P(D)$ way up — Blackheart is now very likely a dealer. And dealers have much higher baseline $P(H)$.\n\nSo when we marginalize over $D$:\n$$P(H \\mid L) = P(H \\mid L, D) P(D \\mid L) + P(H \\mid L, D^c) P(D^c \\mid L),$$\nthe huge mass shift from $D^c$ to $D$ dominates the within-group decrease in $P(H \\mid L, \\cdot)$.\n\nHomer condition-flipped on the wrong variable. The dangerous evidence is not 'has ivory' per se — it's the **information about dealer status** that the ivory leaks. **Always check the confounders.**"),
            ],
            quantRelevance: 3,
            quantRationale: "Narrative-heavy but the conditioning-on-the-wrong-thing fallacy is real. Less directly interview-asked than 2.1."),

        .init(
            id: "stat110-hw3-sp-3.1", setNumber: 3, kind: .strategicPractice,
            topic: "Gambler's Ruin", number: "3.1",
            title: "Gambler quits when ahead by $2",
            body: "A gambler repeatedly plays a game where in each round, he wins a dollar with probability 1/3 and loses a dollar with probability 2/3. His strategy is \"quit when he is ahead by $2,\" though some suspect he is a gambling addict anyway. Suppose that he starts with a million dollars. Show that the probability that he'll ever be ahead by $2 is less than 1/4.",
            firstLineHint: "Special case of gambler's ruin. Let $a_i$ = probability of reaching the target before being ruined, starting with $\\$i$.",
            solutionSteps: [
                .init(title: "Recognize the structure",
                      body: "This is a **gambler's ruin** problem. The gambler quits when he's $\\$2$ ahead — call that the *target*. He's 'ruined' if he reaches $\\$0$. Starting fortune is huge ($\\$10^6$), but the structure of the answer doesn't care about the starting fortune directly — it only depends on the distance to ruin vs. target.\n\nLet $a_i$ = probability of hitting the target ($\\$2$ profit) before being ruined, starting from fortune $\\$i$."),
                .init(title: "First-step analysis",
                      body: "Condition on the result of the next play. With probability $1/3$ we win and move to fortune $\\$(i+1)$; with probability $2/3$ we lose and move to $\\$(i-1)$:\n$$a_i = \\tfrac{1}{3} a_{i+1} + \\tfrac{2}{3} a_{i-1}.$$\nBoundary conditions: $a_0 = 0$ (ruined, target unreachable) and $a_{i_0 + 2} = 1$ (already at target). For starting fortune $\\$10^6$, target is at $\\$(10^6 + 2)$."),
                .init(title: "Solve the recurrence",
                      body: "The recurrence $\\tfrac{1}{3} a_{i+1} - a_i + \\tfrac{2}{3} a_{i-1} = 0$ has characteristic equation\n$$\\tfrac{1}{3} r^2 - r + \\tfrac{2}{3} = 0,$$\nwith roots $r = 1$ and $r = 2$. So\n$$a_i = A + B \\cdot 2^i$$\nfor constants determined by the boundary conditions $a_0 = 0$ and $a_{N+2} = 1$ (where $N$ is the starting fortune)."),
                .init(title: "Plug in boundaries",
                      body: "From $a_0 = 0$: $A + B = 0$, so $A = -B$.\nFrom $a_{N+2} = 1$: $A + B \\cdot 2^{N+2} = 1$, so $B(2^{N+2} - 1) = 1$, giving $B = 1/(2^{N+2} - 1)$.\n\nSo the probability of reaching the target starting from $\\$i$ is\n$$a_i = \\frac{2^i - 1}{2^{N+2} - 1}.$$\nIn particular, starting from $\\$N$ (one million):\n$$a_N = \\frac{2^N - 1}{2^{N+2} - 1}.$$"),
                .init(title: "Full solution — prove $a_N < 1/4$",
                      body: "We need to show $a_N = \\dfrac{2^N - 1}{2^{N+2} - 1} < \\dfrac{1}{4}$ for all $N \\geq 1$.\n\nCross-multiply (both denominators positive):\n$$4(2^N - 1) < 2^{N+2} - 1$$\n$$\\iff 2^{N+2} - 4 < 2^{N+2} - 1,$$\nwhich is always true. So $a_N < 1/4$ no matter how large the starting fortune. $\\blacksquare$\n\n**Why this matters for trading:** the gambler has positive marginal probability of hitting a fixed target on any one trajectory, but the geometric decay overwhelms the gain. Negative-edge strategies don't fix themselves with bigger bankrolls."),
            ],
            quantRelevance: 5,
            quantRationale: "Gambler's ruin is a top-3 interview topic at trading firms. First-step analysis + recurrence is the canonical move."),

        .init(
            id: "stat110-hw3-sp-4.1", setNumber: 3, kind: .strategicPractice,
            topic: "Bernoulli and Binomial", number: "4.1",
            title: "World Series",
            body: "(a) In the World Series of baseball, two teams (call them A and B) play a sequence of games against each other, and the first team to win four games wins the series. Let p be the probability that A wins an individual game, and assume the games are independent. What is the probability that team A wins the series?\n\n(b) Give a clear intuitive explanation of whether the answer to (a) depends on whether the teams always play 7 games (and whoever wins the majority wins the series), or the teams stop playing as soon as one team has won 4 games (as is actually the case in practice).",
            firstLineHint: "Try the **'play out all 7'** trick — even after the series is decided, imagine they keep playing. The series winner is unaffected.",
            solutionSteps: [
                .init(title: "(a) Direct approach (clunky but instructive)",
                      body: "A wins the series in exactly 4, 5, 6, or 7 games. Let $q = 1 - p$. For A to win in exactly 5 games: she must win 3 of the first 4 (in any order) **and** win the 5th. The first-4 part is $\\binom{4}{3} p^3 q$, then $\\cdot p$:\n$$P(A \\text{ wins in 5}) = \\binom{4}{3} p^4 q.$$\nSimilarly for 6 and 7. Adding:\n$$P(A \\text{ wins}) = p^4 + \\binom{4}{3} p^4 q + \\binom{5}{3} p^4 q^2 + \\binom{6}{3} p^4 q^3.$$"),
                .init(title: "(a) Cleaner approach — 'play all 7'",
                      body: "Imagine that even after a team wins 4 games, the teams keep playing the remaining games anyway (just for fun). The series winner is **unchanged** — the post-decision games don't matter.\n\nNow let $X$ = number of games A wins out of all 7. Since each game is independent Bernoulli($p$):\n$$X \\sim \\text{Bin}(7, p).$$\nA wins the series $\\iff$ A wins at least 4 of the 7 games:\n$$P(A \\text{ wins}) = P(X \\geq 4) = \\sum_{k=4}^{7} \\binom{7}{k} p^k (1-p)^{7-k}.$$"),
                .init(title: "(b) The two formulations agree",
                      body: "Both expressions are equal as functions of $p$ (you can verify by expanding both as polynomials in $p$ and seeing they match coefficient-by-coefficient).\n\nThe **intuition**: stopping early vs continuing doesn't change who wins. If A has already won 4, A is the series winner regardless of the remaining (irrelevant) games. So $P(A \\text{ wins series})$ doesn't depend on the stopping rule."),
                .init(title: "Full solution — why this trick matters",
                      body: "The 'play out all 7' trick is a general pattern: when a stochastic process has a stopping rule that doesn't affect the outcome you care about, you can replace it with a fixed-length process and get cleaner formulas.\n\nMore broadly, this is **'imagine the process completed even though it didn't'** — useful for negative binomials, runs problems, and many trading-style 'first to N' settings. Memorize it as a tool."),
            ],
            quantRelevance: 4,
            quantRationale: "Best-of-N series problems are interview canon. The \"play out all 7\" trick is the move and it generalizes."),
        .init(
            id: "stat110-hw3-sp-4.2", setNumber: 3, kind: .strategicPractice,
            topic: "Bernoulli and Binomial", number: "4.2",
            title: "Sequences given number of successes",
            body: "A sequence of n independent experiments is performed. Each experiment is a success with probability p and a failure with probability q = 1 − p. Show that conditional on the number of successes, all possibilities for the list of outcomes of the experiment are equally likely (of course, we only consider lists of outcomes where the number of successes is consistent with the information being conditioned on).",
            firstLineHint: "Set up indicators and write out the conditional probability with the definition.",
            solutionSteps: [
                .init(title: "Set up indicators",
                      body: "Let $X_j = 1$ if the $j$th trial is a success, $0$ otherwise. Let $X = X_1 + \\cdots + X_n$ be the total number of successes. Let $q = 1 - p$ for brevity. We want to compute, for any specific binary sequence $(a_1, \\ldots, a_n)$ with $a_1 + \\cdots + a_n = k$:\n$$P(X_1 = a_1, \\ldots, X_n = a_n \\mid X = k).$$"),
                .init(title: "Apply the definition",
                      body: "By the definition of conditional probability:\n$$P(X_1 = a_1, \\ldots, X_n = a_n \\mid X = k) = \\frac{P(X_1 = a_1, \\ldots, X_n = a_n)}{P(X = k)}.$$\n(We used the fact that the event $\\{X_1 = a_1, \\ldots, X_n = a_n\\}$ already implies $X = k$ since $\\sum a_j = k$.)"),
                .init(title: "Plug in the numerator and denominator",
                      body: "Numerator: by independence, $P(X_1 = a_1, \\ldots, X_n = a_n) = p^k q^{n-k}$ (since exactly $k$ of the $a_j$ are 1, and they appear in specified positions).\n\nDenominator: $X \\sim \\text{Bin}(n, p)$, so $P(X = k) = \\binom{n}{k} p^k q^{n-k}$.\n\nTherefore:\n$$P(X_1 = a_1, \\ldots, X_n = a_n \\mid X = k) = \\frac{p^k q^{n-k}}{\\binom{n}{k} p^k q^{n-k}} = \\frac{1}{\\binom{n}{k}}.$$"),
                .init(title: "Full solution — interpret the cancellation",
                      body: "Two remarkable facts:\n\n**1.** The answer doesn't depend on $(a_1, \\ldots, a_n)$. So conditional on the total being $k$, every one of the $\\binom{n}{k}$ specific sequences with $k$ successes is equally likely.\n\n**2.** The answer doesn't depend on $p$ either. This is the **sufficient statistic** phenomenon: once you know the total count $X = k$, the specific arrangement carries no information about $p$. Knowing the order would not help you estimate $p$ at all.\n\nThis is the gateway to formal estimation theory (Stat 111), and the underlying reason that the Hypergeometric distribution in 4.3(c) is $p$-free."),
            ],
            quantRelevance: 4,
            quantRationale: "Sufficient statistics in disguise. The fact that p drops out is the foundation of estimation theory — and the symmetry argument is interview-grade."),
        .init(
            id: "stat110-hw3-sp-4.3", setNumber: 3, kind: .strategicPractice,
            topic: "Bernoulli and Binomial", number: "4.3",
            title: "Sums and differences of Binomials",
            body: "Let X ∼ Bin(n, p) and Y ∼ Bin(m, p), independent of X.\n\n(a) Show that X + Y ∼ Bin(n + m, p), using a story proof.\n(b) Show that X − Y is not Binomial.\n(c) Find P(X = k | X + Y = j). How does this relate to the elk problem from HW 1?",
            firstLineHint: "(a) Tell a story — don't compute. (b) Range. (c) Definition of conditional probability + cancel $p$.",
            solutionSteps: [
                .init(title: "(a) Story proof for X + Y",
                      body: "Interpret $X$ as the number of successes in $n$ independent Bernoulli($p$) trials, and $Y$ as the number of successes in $m$ **more** independent Bernoulli($p$) trials, where the $n$ and the $m$ trials are independent.\n\nThen $X + Y$ counts the number of successes in the combined $n + m$ independent trials, each with success probability $p$. By definition of Binomial:\n$$X + Y \\sim \\text{Bin}(n + m, p).$$\nNo PMF calculation needed."),
                .init(title: "(b) Why X − Y is not Binomial",
                      body: "A Binomial random variable is non-negative — it counts successes. But $X - Y$ can be **negative** with positive probability (whenever $Y > X$, which has positive probability when $m \\geq 1$).\n\nSo $X - Y$ cannot be Binomial. Done."),
                .init(title: "(c) Set up the conditional probability",
                      body: "By definition:\n$$P(X = k \\mid X + Y = j) = \\frac{P(X = k, X + Y = j)}{P(X + Y = j)}.$$\nThe event $\\{X = k, X + Y = j\\}$ is the same as $\\{X = k, Y = j - k\\}$. By independence of $X$ and $Y$:\n$$P(X = k, Y = j - k) = P(X = k) \\, P(Y = j - k).$$"),
                .init(title: "(c) Plug in the PMFs and watch $p$ cancel",
                      body: "Using $X \\sim \\text{Bin}(n, p)$, $Y \\sim \\text{Bin}(m, p)$, $X + Y \\sim \\text{Bin}(n+m, p)$:\n$$\\frac{\\binom{n}{k} p^k (1-p)^{n-k} \\cdot \\binom{m}{j-k} p^{j-k} (1-p)^{m-(j-k)}}{\\binom{n+m}{j} p^j (1-p)^{n+m-j}}.$$\nThe $p$ and $(1-p)$ factors cancel exactly. Result:\n$$P(X = k \\mid X + Y = j) = \\frac{\\binom{n}{k}\\binom{m}{j-k}}{\\binom{n+m}{j}}.$$\nThis is the **Hypergeometric** PMF."),
                .init(title: "Full solution — connection to the elk problem",
                      body: "Why does $p$ cancel? Imagine $n$ male elk and $m$ female elk. Tag each elk independently with probability $p$. Now ask: given that $j$ total elk are tagged, how many of the $n$ males are tagged?\n\nAnswer: equivalent to sampling $j$ elk **without replacement** from the population of $n + m$, and counting males. That's $\\text{HGeom}(n+m, n, j)$ — no $p$ involved, because once we condition on the total tagged count, the **identities** of which $j$ were tagged are a uniform random subset (by 4.2).\n\nThis is one of the most elegant moments in elementary probability: conditioning on a sufficient statistic makes the parameter disappear."),
            ],
            quantRelevance: 4,
            quantRationale: "Story proofs and the surprising p-cancellation are both classic interview reveals. Hypergeometric structure is broadly useful."),

        // --- Homework 3 ---
        .init(
            id: "stat110-hw3-hw-1", setNumber: 3, kind: .homework,
            topic: nil, number: "1",
            title: "7-door (then general) Monty Hall",
            body: "(a) Consider the following 7-door version of the Monty Hall problem. There are 7 doors, behind one of which there is a car. Initially, all possibilities are equally likely. You choose a door. Monty Hall then opens 3 goat doors and offers you the option of switching to any of the remaining 3 doors. Assume Monty knows where the car is, always opens 3 goat doors, and chooses with equal probabilities. Should you switch? What is your probability of success if you switch to one of the remaining 3 doors?\n\n(b) Generalize the above to a Monty Hall problem where there are n ≥ 3 doors, of which Monty opens m goat doors, with 1 ≤ m ≤ n − 2.",
            firstLineHint: "(a) Stick strategy: P(success) = 1/n = 1/7. After Monty opens 3 doors, the remaining 3 doors collectively have probability 6/7, so each has 6/7/3 = 2/7. Switch. (b) Sticking: 1/n. Switching to any one remaining door: (n−1) / [(n−m−1)·n].",
            quantRelevance: 4,
            quantRationale: "Generalizing Monty Hall sharpens the conditioning intuition. Interview variants come up often."),
        .init(
            id: "stat110-hw3-hw-2", setNumber: 3, kind: .homework,
            topic: nil, number: "2",
            title: "Bayes in odds form — medical test",
            body: "The odds of an event with probability p are defined to be p / (1 − p). The prior probability of H is our probability before we gather new data; the posterior probability is after. The likelihood ratio is P(D|H) / P(D|Hᶜ).\n\n(a) Show that Bayes' rule can be expressed in terms of odds as follows: the posterior odds of a hypothesis H are the prior odds of H times the likelihood ratio.\n\n(b) Suppose a patient tests positive for a disease afflicting 1% of the population, with 95% sensitivity and 95% specificity. The patient gets a second, independent test done with the same sensitivity and specificity, and again tests positive. Use the odds form of Bayes' rule to find the probability the patient has the disease, in two ways: in one step (conditioning on both results at once), and in two steps.",
            firstLineHint: "(a) P(H|D)/P(Hᶜ|D) = [P(D|H)P(H)/P(D)] / [P(D|Hᶜ)P(Hᶜ)/P(D)] = (P(H)/P(Hᶜ)) · (P(D|H)/P(D|Hᶜ)). (b) Prior odds 1:99 against. One-step LR: (0.95/0.05)² = 361. Posterior odds: 361/99 ≈ 3.65. Probability: 361/460 ≈ 0.78.",
            quantRelevance: 5,
            quantRationale: "Bayes in odds form is THE quant tool — multiplies cleanly, generalizes to sequential evidence. Asked at Jane Street verbatim."),
        .init(
            id: "stat110-hw3-hw-3", setNumber: 3, kind: .homework,
            topic: nil, number: "3",
            title: "Union flip with conditional inequalities",
            body: "Is it possible to have events A₁, A₂, B, C with P(A₁|B) > P(A₁|C) and P(A₂|B) > P(A₂|C), yet P(A₁ ∪ A₂ | B) < P(A₁ ∪ A₂ | C)? If so, find an example (with a story interpreting the events and giving specific numbers); otherwise, show that it is impossible.",
            firstLineHint: "Yes, possible. Key: P(A₁ ∪ A₂ | B) = P(A₁|B) + P(A₂|B) − P(A₁ ∩ A₂ | B). Need P(A₁ ∩ A₂ | B) ≫ P(A₁ ∩ A₂ | C) to offset. Story: streaky player (always make-both or miss-both with p=0.8) vs steady player (each shot independent with p=0.7).",
            quantRelevance: 4,
            quantRationale: "Tests whether you really respect inclusion-exclusion under conditioning. Correlation > marginals is a key risk-management lesson."),
        .init(
            id: "stat110-hw3-hw-4", setNumber: 3, kind: .homework,
            topic: nil, number: "4",
            title: "Calvin & Hobbes, win-by-2",
            body: "Calvin and Hobbes play a match consisting of a series of games, where Calvin has probability p of winning each game (independently). They play with a \"win by two\" rule: the first player to win two games more than his opponent wins the match. Find the probability that Calvin wins the match (in terms of p), in two different ways:\n\n(a) by conditioning, using the law of total probability.\n(b) by interpreting the problem as a gambler's ruin problem.",
            firstLineHint: "(a) Let C = Calvin wins, X ∼ Bin(2, p) = wins in first 2 games. P(C) = P(C|X=0)·q² + P(C|X=1)·2pq + P(C|X=2)·p² = 2pq·P(C) + p². So P(C) = p² / (1 − 2pq) = p² / (p² + q²).",
            quantRelevance: 5,
            quantRationale: "Win-by-two is a famous interview problem. Recurrence + symmetry + gambler's ruin all in one — top-tier prep."),
        .init(
            id: "stat110-hw3-hw-5", setNumber: 3, kind: .homework,
            topic: nil, number: "5",
            title: "Die running total — find pₙ",
            body: "A fair die is rolled repeatedly, and a running total is kept. Let pₙ be the probability that the running total is ever exactly n.\n\n(a) Write down a recursive equation for pₙ. Define p₀ and pₖ for k < 0 so that the equation is true for small n.\n(b) Find p₇.\n(c) Give an intuitive explanation for the fact that pₙ → 1/3.5 = 2/7 as n → ∞.",
            firstLineHint: "(a) First-step analysis: condition on the first throw. pₙ = (pₙ₋₁ + pₙ₋₂ + pₙ₋₃ + pₙ₋₄ + pₙ₋₅ + pₙ₋₆)/6, with p₀ = 1 and pₖ = 0 for k < 0. (c) Each throw adds on average 7/2, so we land on 2 out of every 7 integers.",
            quantRelevance: 5,
            quantRationale: "Renewal/recursion classic. Asked in many forms at trading firms — running totals, level-hitting, sum-of-die-rolls."),
        .init(
            id: "stat110-hw3-hw-6", setNumber: 3, kind: .homework,
            topic: nil, number: "6",
            title: "A vs B trivia — first correct wins",
            body: "Players A and B take turns in answering trivia questions, starting with A. Each time A answers, she has probability p₁ of getting it right. Each time B plays, he has probability p₂.\n\n(a) If A answers m questions, what is the PMF of the number she gets right?\n(b) If A answers m times and B answers n times, what is the PMF of the total number they get right? When/whether is this Binomial?\n(c) Suppose the first to answer correctly wins (no predetermined maximum). Find the probability A wins.",
            firstLineHint: "(c) Let r = P(A wins). Condition on the first round: r = p₁ + (1−p₁)·p₂·0 + (1−p₁)·(1−p₂)·r. Solve: r = p₁ / (1 − (1−p₁)(1−p₂)) = p₁ / (p₁ + p₂ − p₁p₂).",
            quantRelevance: 4,
            quantRationale: "Geometric / first-success problems are interview canon. The recursion-with-feedback is the move."),
        .init(
            id: "stat110-hw3-hw-7", setNumber: 3, kind: .homework,
            topic: nil, number: "7",
            title: "Noisy channel with parity bit",
            body: "A message is sent over a noisy channel. The message is a sequence x₁, x₂, …, xₙ of n bits. Each bit is independently corrupted with probability p ∈ (0, 1/2). The nth bit is a parity check: xₙ = 0 if x₁ + ⋯ + xₙ₋₁ is even, 1 if odd. The recipient checks whether yₙ has the same parity as y₁ + ⋯ + yₙ₋₁.\n\n(a) For n = 5, p = 0.1, what is the probability the message has undetected errors?\n(b) For general n and p, write down an expression (as a sum) for the probability of undetected errors.\n(c) Give a simplified closed-form expression. Hint: with a = Σ_{k even, k≥0} C(n,k) pᵏ (1−p)ⁿ⁻ᵏ and b = Σ_{k odd, k≥1} C(n,k) pᵏ (1−p)ⁿ⁻ᵏ, find a + b and a − b via the binomial theorem.",
            firstLineHint: "Errors are undetected iff there are an even (and nonzero) number of them. Number of errors ∼ Bin(n, p). a + b = 1 (sum over all k), a − b = (1 − 2p)ⁿ (sum with (−p) plugged in). So a = (1 + (1 − 2p)ⁿ)/2, and the answer is a − (1 − p)ⁿ.",
            quantRelevance: 4,
            quantRationale: "Binomial theorem trick — a beautiful generating-function-style move. Comes up in problems with parity / sign-alternating structure."),
    ]
)
