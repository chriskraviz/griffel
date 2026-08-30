import SwiftUI
import Charts

struct StatsView: View {
    private let store = StatsStore.shared
    private let phraseStore = PhraseStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if store.events.isEmpty {
                    emptyState
                } else {
                    statTiles
                    weeklyChartCard
                    workflowShareCard
                }

                if !phraseStore.frequentPhrases(limit: 8).isEmpty {
                    frequentPhrasesCard
                }

                Text("Zeit gespart = Tippzeit bei \(Int(StatsStore.assumedTypingWordsPerMinute)) Wörtern/Minute minus Aufnahme- und Verarbeitungszeit. Alle Statistiken bleiben lokal auf deinem Mac. Häufige Phrasen werden nur als lokale Zählwerte gespeichert, nie als ganze Texte.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("Noch keine Daten")
                .font(.system(size: 12.5, weight: .semibold))
            Text("Starte eine Aufnahme, dann siehst du hier, wie viel Zeit dir Griffel spart.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 12)
        .glassCard()
    }

    private var statTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
            statTile(value: formattedCount(store.totalWords), label: "Wörter gesamt", icon: "text.word.spacing", tint: .blue)
            statTile(value: formattedCount(store.totalSessions), label: "Aufnahmen", icon: "mic.fill", tint: .purple)
            statTile(value: formattedDuration(store.estimatedTimeSavedSeconds), label: "Zeit gespart", icon: "clock.arrow.circlepath", tint: .green)
            statTile(value: formattedCount(store.averageWordsPerSession), label: "Ø Wörter je Aufnahme", icon: "chart.bar.fill", tint: .orange)
        }
    }

    private func statTile(value: String, label: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassCard(radius: DS.radiusS)
    }

    private var weeklyChartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wörter pro Woche")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Chart(store.wordsByWeek(lastWeeks: 8)) { bucket in
                BarMark(
                    x: .value("Woche", bucket.weekStart, unit: .weekOfYear),
                    y: .value("Wörter", bucket.words)
                )
                .foregroundStyle(Color.blue.gradient)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.narrow), centered: true)
                        .font(.system(size: 8))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                        .font(.system(size: 8))
                }
            }
            .frame(height: 110)
        }
        .padding(12)
        .glassCard()
    }

    private var workflowShareCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nutzung nach Workflow")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Chart(store.wordsByWorkflow) { share in
                    SectorMark(
                        angle: .value("Wörter", share.words),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.2
                    )
                    .foregroundStyle(by: .value("Workflow", share.name))
                    .cornerRadius(2)
                }
                .chartLegend(.hidden)
                .frame(width: 92, height: 92)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(store.wordsByWorkflow.prefix(5))) { share in
                        HStack(spacing: 6) {
                            Text(share.name)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(formattedCount(share.words))
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .glassCard()
    }

    private var frequentPhrasesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Häufige Phrasen")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Löschen") {
                    phraseStore.deleteAll()
                }
                .buttonStyle(.destructive(.compact))
                .help("Alle lokal gespeicherten Phrasen-Zählwerte löschen")
            }

            FlowLayout(spacing: 5) {
                ForEach(phraseStore.frequentPhrases(limit: 8)) { tracked in
                    GlassChip {
                        Text(tracked.phrase)
                            .font(.system(size: 10.5))
                            .lineLimit(1)
                        Text("\(tracked.count)×")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .glassCard()
    }

    private func formattedCount(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).locale(Locale(identifier: "de_DE")))
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds)) s"
        }
        if seconds < 3600 {
            return "\(Int(seconds / 60)) min"
        }
        let hours = Int(seconds / 3600)
        let minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        return "\(hours) h \(minutes) min"
    }
}
