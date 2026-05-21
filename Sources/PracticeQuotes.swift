import Foundation

/// Curated quote library for Practice Mode — quotes from people who
/// *actually* struggled with hard math/probability, plus growth-mindset
/// research. Categorized so we surface contextually-relevant ones, not
/// random fluff.
///
/// Curation principles:
///   • No generic motivational-poster lines. Every quote has weight —
///     attribution to someone who did the work.
///   • Variety of voices: mathematicians, quants, learning researchers.
///   • Stat 110 / probability bias because that's the user's domain.
///   • Permission-granting tone in `afterHint` / `afterStuck` because
///     the framework's whole premise is peeking is part of the work.
enum PracticeQuotes {

    struct Quote: Hashable {
        let text: String
        let author: String
    }

    enum Context {
        case general            // rotates during active session
        case sessionStart       // first quote shown when session begins
        case yellowZone         // 15-20 min in
        case redZone            // 20+ min in
        case afterHint          // user just peeked a hint
        case afterMonteCarlo    // user just opened MC sheet
        case afterSolved        // celebration moment
        case afterStuck         // moving-on moment
        case afterSkipped       // explicit "not my toolkit" moment
        case idleScreen         // when the window opens to idle
    }

    // MARK: - The library

    /// Picks a contextually appropriate quote. Uses the seed (typically
    /// elapsedSeconds or attempt count) so the same context+seed always
    /// returns the same quote — stable across re-renders.
    static func pick(_ context: Context, seed: Int = 0) -> Quote {
        let pool = pool(for: context)
        guard !pool.isEmpty else { return general[0] }
        return pool[abs(seed) % pool.count]
    }

    private static func pool(for context: Context) -> [Quote] {
        switch context {
        case .general:         return general
        case .sessionStart:    return sessionStart
        case .yellowZone:      return yellowZone
        case .redZone:         return redZone
        case .afterHint:       return afterHint
        case .afterMonteCarlo: return afterMonteCarlo
        case .afterSolved:     return afterSolved
        case .afterStuck:      return afterStuck
        case .afterSkipped:    return afterSkipped
        case .idleScreen:      return idleScreen
        }
    }

    // MARK: - Pools

    /// General struggle / persistence — rotates every ~90s during a session.
    private static let general: [Quote] = [
        Quote(text: "It's not that I'm so smart. It's just that I stay with problems longer.",
              author: "Albert Einstein"),
        Quote(text: "The only way to learn mathematics is to do mathematics.",
              author: "Paul Halmos"),
        Quote(text: "It is by logic that we prove, but by intuition that we discover.",
              author: "Henri Poincaré"),
        Quote(text: "If I have any worthwhile mathematical thought, it is because I have a habit of thinking — slowly, persistently, and over time.",
              author: "David Hilbert"),
        Quote(text: "Mathematics is not a deductive science — that's a cliché. When you try to prove a theorem, you don't just list the hypotheses and then start to reason. What you do is trial and error, experimentation, guesswork.",
              author: "Paul Halmos"),
        Quote(text: "I have had my results for a long time: but I do not yet know how I am to arrive at them.",
              author: "Carl Friedrich Gauss"),
        Quote(text: "What is now proved was once only imagined.",
              author: "William Blake"),
        Quote(text: "Probability is common sense reduced to calculation.",
              author: "Pierre-Simon Laplace"),
        Quote(text: "Conditioning is the soul of statistics.",
              author: "Joe Blitzstein"),
        Quote(text: "It is not knowledge, but the act of learning, not possession but the act of getting there, which grants the greatest enjoyment.",
              author: "Carl Friedrich Gauss"),
        Quote(text: "Probability is the most important concept in modern science, especially as nobody has the slightest notion what it means.",
              author: "Bertrand Russell"),
        Quote(text: "I was working in the dark, but I was sure of my direction.",
              author: "Andrew Wiles, on the seven years before solving Fermat"),
        Quote(text: "What's important is what you learn from solving — or failing to solve — a problem.",
              author: "Terence Tao"),
        Quote(text: "The mathematical experience of the student is incomplete if he never has the opportunity to solve a problem invented by himself.",
              author: "George Pólya"),
    ]

    /// Shown when a session begins. Sets the tone — calibrate, don't rush.
    private static let sessionStart: [Quote] = [
        Quote(text: "Read the problem twice. The first read finds the surface; the second finds the structure.",
              author: "Stat 110 practice"),
        Quote(text: "Don't try to be brilliant — try to be careful.",
              author: "Paul Halmos"),
        Quote(text: "Understanding the problem is half of solving it.",
              author: "George Pólya, How to Solve It"),
        Quote(text: "Define your variables before you start writing equations. Your future self will thank you.",
              author: "Joe Blitzstein"),
        Quote(text: "Begin with what you know.",
              author: "George Pólya"),
    ]

    /// 15-20 min mark. Frame this as the magic zone, not a warning.
    private static let yellowZone: [Quote] = [
        Quote(text: "You've been thinking deeply for fifteen minutes. Most insights show up in the next five.",
              author: "deliberate practice research, Anders Ericsson"),
        Quote(text: "If you cannot solve a problem, then there is an easier problem you cannot solve: find it.",
              author: "George Pólya"),
        Quote(text: "When in doubt, condition on something.",
              author: "Stat 110 aphorism"),
        Quote(text: "Have you tried the smallest case?",
              author: "George Pólya"),
        Quote(text: "Step back. Restate the problem in your own words. The framing often is the answer.",
              author: "Stat 110 practice"),
    ]

    /// 20+ min. Pivot is the goal — explicitly permission-granting.
    private static let redZone: [Quote] = [
        Quote(text: "I have not failed. I've just found ten thousand ways that won't work.",
              author: "Thomas Edison"),
        Quote(text: "Sitting in front of a problem for an hour and getting nowhere is not deliberate practice. It's frustration.",
              author: "Anders Ericsson"),
        Quote(text: "Knowing when to switch tactics is a real skill — not a failure.",
              author: "interview-prep advice"),
        Quote(text: "Pivot the angle, not the goal.",
              author: "trader's heuristic"),
        Quote(text: "If the closed form is opaque, simulate. The structure usually reveals itself.",
              author: "Persi Diaconis, on Monte Carlo intuition"),
    ]

    /// User just peeked a hint. Affirm — peeking is part of the practice.
    private static let afterHint: [Quote] = [
        Quote(text: "If I have seen further it is by standing on the shoulders of giants.",
              author: "Isaac Newton"),
        Quote(text: "The first principle is that you must not fool yourself — and you are the easiest person to fool.",
              author: "Richard Feynman"),
        Quote(text: "Take the nudge and run with it. That's the muscle you're building.",
              author: "interview-prep advice"),
        Quote(text: "Even Feynman read other people's proofs.",
              author: "anonymous"),
        Quote(text: "Reading a hint and running with it is the same skill as taking a small piece of information from an interviewer.",
              author: "Stat 110 practice"),
    ]

    /// User just opened Monte Carlo. Reinforce the pivot.
    private static let afterMonteCarlo: [Quote] = [
        Quote(text: "Simulation is a serious tool. Mandelbrot built fractal geometry on it.",
              author: "anonymous"),
        Quote(text: "If you can write the rules, you can solve the problem. Eventually.",
              author: "computational thinking"),
        Quote(text: "Empirical structure first, closed form second.",
              author: "applied probability practice"),
    ]

    /// Celebration. Earned, specific. Avoid empty 'you did it!'
    private static let afterSolved: [Quote] = [
        Quote(text: "Locked in. The hard part wasn't the math — it was staying with it.",
              author: ""),
        Quote(text: "That insight is yours forever. Reconstructed cold tomorrow, it'll still be there.",
              author: ""),
        Quote(text: "One more pattern in your library.",
              author: ""),
        Quote(text: "Solving builds the intuition; rating builds the calibration. Both are practice.",
              author: ""),
    ]

    /// User marked stuck. Reframe — not failure, deferred learning.
    private static let afterStuck: [Quote] = [
        Quote(text: "Your brain will keep working on it in the background. Sleep often surfaces the move.",
              author: "Henri Poincaré, on the bus-step revelation"),
        Quote(text: "Wiles spent seven years stuck before Fermat. You're allowed an afternoon.",
              author: ""),
        Quote(text: "Coming back to a problem with fresh eyes is a real technique — not a consolation.",
              author: ""),
        Quote(text: "Logged. It'll resurface in your review queue at the right moment.",
              author: ""),
    ]

    /// User explicitly skipped — not in current toolkit. No shame.
    private static let afterSkipped: [Quote] = [
        Quote(text: "Recognizing what's not in your toolkit yet is information, not weakness.",
              author: ""),
        Quote(text: "The map is filling in. Today's gap is tomorrow's lesson.",
              author: ""),
    ]

    /// Idle screen — sets daily tone.
    private static let idleScreen: [Quote] = [
        Quote(text: "Treat these like athletic drills. Forty-five minutes of focused reps beats two hours of frustrated grinding.",
              author: "interview-prep advice"),
        Quote(text: "The power of 'yet'. You don't get it — yet.",
              author: "Carol Dweck, Mindset"),
        Quote(text: "Every problem you've ever solved was once a problem you couldn't solve.",
              author: ""),
        Quote(text: "Show up, set a timer, do the rep. That's the whole game.",
              author: ""),
    ]
}

/// Stat 110-specific "what to try when stuck" checklist. Surfaced in the
/// active view when the user hits the red zone — a real cognitive aid,
/// not generic advice. Each item is a concrete probabilistic move.
///
/// Derived from the recurring patterns across Blitzstein's HW2/HW3 +
/// strategic practice sets: indicators, conditioning, symmetry,
/// LOTUS, story proofs, complement events, small cases.
enum PolyaChecklist {

    struct Move: Identifiable, Hashable {
        let id: String
        let title: String
        let hint: String
    }

    static let stat110Moves: [Move] = [
        .init(
            id: "indicators",
            title: "Indicator random variables",
            hint: "Want to count something? Define X_i = 1 if event i happens. E[X] = sum of probabilities — no independence needed."
        ),
        .init(
            id: "condition",
            title: "Condition on something",
            hint: "First step, a hidden variable, the first success. P(A) = sum over k of P(A | B = k) P(B = k)."
        ),
        .init(
            id: "smallcases",
            title: "Try the small cases",
            hint: "Compute n=1, n=2, n=3 explicitly. The pattern usually appears by n=3. Then guess + verify."
        ),
        .init(
            id: "symmetry",
            title: "Symmetry",
            hint: "If three children are equally likely to be the oldest, P(A oldest) = 1/3 without computation. Look for indistinguishable cases."
        ),
        .init(
            id: "complement",
            title: "Try the complement",
            hint: "P(at least one) is often easier as 1 - P(none). Look for events with many subcases — the complement might collapse them."
        ),
        .init(
            id: "story",
            title: "Story proof",
            hint: "Both sides count the same thing two different ways. Combinatorial identities often have a one-line story."
        ),
        .init(
            id: "lotus",
            title: "Use LOTUS",
            hint: "E[g(X)] = sum of g(x) P(X=x). You don't need the distribution of g(X) — just X's. Often dodges a hard transformation."
        ),
        .init(
            id: "bayes",
            title: "Bayes' rule in odds form",
            hint: "posterior odds = prior odds × likelihood ratio. Sequential evidence multiplies cleanly. Often beats Bayes-with-denominators."
        ),
        .init(
            id: "linearity",
            title: "Linearity of expectation",
            hint: "E[X + Y] = E[X] + E[Y] always, even when X and Y are dependent. The most underrated tool in probability."
        ),
        .init(
            id: "simulate",
            title: "Simulate it",
            hint: "Write the rules in 10 lines of Python. If the empirical answer converges to a clean fraction, you've found it. Use the Monte Carlo button."
        ),
    ]
}
