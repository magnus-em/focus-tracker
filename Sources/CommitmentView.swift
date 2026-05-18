import SwiftUI

struct CommitmentView: View {
    @ObservedObject var settings: AppSettings
    @Binding var isShowing: Bool

    @State private var text = ""
    @FocusState private var focused: Bool

    private let red = Color(red: 0.96, green: 0.36, blue: 0.36)

    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 5) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                    Text("Good \(greeting)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(todayString)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)
                .padding(.bottom, 14)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Written commitment
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TODAY'S COMMITMENT")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(.secondary)
                            ZStack(alignment: .topLeading) {
                                if text.isEmpty {
                                    Text("What will you accomplish today?")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 9)
                                        .allowsHitTesting(false)
                                }
                                TextEditor(text: $text)
                                    .font(.system(size: 13))
                                    .frame(minHeight: 70)
                                    .scrollContentBackground(.hidden)
                                    .padding(6)
                                    .focused($focused)
                            }
                            .background(Color.secondary.opacity(0.06))
                            .cornerRadius(9)
                        }

                    }
                    .padding(18)
                }

                Divider()

                VStack(spacing: 6) {
                    Button {
                        settings.markCommitmentDone(text: text.trimmingCharacters(in: .whitespaces))
                        isShowing = false
                    } label: {
                        Text("Start My Day")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(text.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(text.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary.opacity(0.1) : red)
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button {
                        settings.markCommitmentDone(text: "")
                        isShowing = false
                    } label: {
                        Text("Skip for today")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .onAppear { focused = true }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "morning" : h < 17 ? "afternoon" : "evening"
    }

    private var todayString: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
        return f.string(from: Date())
    }
}
