import SwiftUI
import WidgetKit

@main
struct PolyWidgetBundle: WidgetBundle {
    var body: some Widget {
        MemoriesWidget()
    }
}

struct MemoriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MemoriesWidget", provider: MemoriesProvider()) { entry in
            MemoriesWidgetView(entry: entry)
        }
        .configurationDisplayName(Text("Memories"))
        .description(Text("A polaroid from your library, with photos from this day in past years."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline

struct MemoryEntry: TimelineEntry {
    enum Content {
        case memory(MemorySnapshot.Memory, image: UIImage?, yearsAgo: Int?)
        case locked
        case empty
    }

    let date: Date
    let content: Content
}

struct MemoriesProvider: TimelineProvider {
    private static let refreshInterval: TimeInterval = 3 * 60 * 60
    private static let entriesPerTimeline = 8

    func placeholder(in context: Context) -> MemoryEntry {
        MemoryEntry(date: Date(), content: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (MemoryEntry) -> Void) {
        let snapshot = MemorySnapshot.load()
        completion(entry(for: Date(), slot: 0, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MemoryEntry>) -> Void) {
        let snapshot = MemorySnapshot.load()
        let now = Date()
        let entries = (0..<Self.entriesPerTimeline).map { slot in
            entry(for: now.addingTimeInterval(Double(slot) * Self.refreshInterval), slot: slot, snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(for date: Date, slot: Int, snapshot: MemorySnapshot?) -> MemoryEntry {
        guard let snapshot else { return MemoryEntry(date: date, content: .empty) }
        guard snapshot.isPremium else { return MemoryEntry(date: date, content: .locked) }
        guard let (memory, yearsAgo) = pick(from: snapshot.memories, on: date, slot: slot) else {
            return MemoryEntry(date: date, content: .empty)
        }
        let image = MemorySnapshot.imageURL(for: memory).flatMap { UIImage(contentsOfFile: $0.path) }
        return MemoryEntry(date: date, content: .memory(memory, image: image, yearsAgo: yearsAgo))
    }

    /// Prefers photos taken on this calendar day in earlier years; otherwise rotates through
    /// the library deterministically so the same slot shows the same photo across reloads.
    private func pick(from memories: [MemorySnapshot.Memory], on date: Date, slot: Int) -> (MemorySnapshot.Memory, Int?)? {
        guard !memories.isEmpty else { return nil }
        let calendar = Calendar.current
        let day = calendar.dateComponents([.year, .month, .day], from: date)

        let anniversaries = memories.filter { memory in
            let c = calendar.dateComponents([.year, .month, .day], from: memory.timestamp)
            return c.month == day.month && c.day == day.day && (c.year ?? 0) < (day.year ?? 0)
        }
        if !anniversaries.isEmpty {
            let memory = anniversaries[slot % anniversaries.count]
            let years = (day.year ?? 0) - calendar.component(.year, from: memory.timestamp)
            return (memory, years)
        }

        let dayNumber = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let index = (dayNumber * Self.entriesPerTimeline + slot) % memories.count
        return (memories[index], nil)
    }
}

// MARK: - Views

struct MemoriesWidgetView: View {
    let entry: MemoryEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [Color(red: 0.12, green: 0.1, blue: 0.16), Color(red: 0.06, green: 0.06, blue: 0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.content {
        case .memory(let memory, let image, let yearsAgo):
            memoryView(memory, image: image, yearsAgo: yearsAgo)
                .widgetURL(PolyDeepLink.memory(memory.id))
        case .locked:
            lockedView
                .widgetURL(PolyDeepLink.premium)
        case .empty:
            emptyView
        }
    }

    @ViewBuilder
    private func memoryView(_ memory: MemorySnapshot.Memory, image: UIImage?, yearsAgo: Int?) -> some View {
        let polaroid = WidgetPolaroid(memory: memory, image: image)
        switch family {
        case .systemMedium:
            HStack(spacing: 16) {
                polaroid
                    .rotationEffect(.degrees(-3))
                    .padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(headline(yearsAgo: yearsAgo))
                        .font(.system(size: 11, weight: .heavy).width(.expanded))
                        .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.3))
                    if !memory.caption.isEmpty {
                        Text(memory.caption)
                            .font(.custom("Bradley Hand", size: 20))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    Text(memory.timestamp, format: .dateTime.day().month(.wide).year())
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            ZStack(alignment: .topLeading) {
                polaroid
                    .rotationEffect(.degrees(-4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if yearsAgo != nil {
                    Text(headline(yearsAgo: yearsAgo))
                        .font(.system(size: 8, weight: .heavy).width(.expanded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(red: 1.0, green: 0.8, blue: 0.3), in: Capsule())
                }
            }
        }
    }

    private func headline(yearsAgo: Int?) -> String {
        switch yearsAgo {
        case .none: NSLocalizedString("A MEMORY", comment: "")
        case .some(1): NSLocalizedString("1 YEAR AGO TODAY", comment: "")
        case .some(let years): String(format: NSLocalizedString("%d YEARS AGO TODAY", comment: ""), years)
        }
    }

    private var lockedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: family == .systemSmall ? 26 : 30))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.9, blue: 0.4), Color(red: 1.0, green: 0.6, blue: 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("Memories")
                .font(.system(size: 15, weight: .bold).width(.expanded))
                .foregroundStyle(.white)
            Text("Unlock Premium to relive a polaroid every day.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.8))
            Text("Take your first polaroid to see it here.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A small polaroid drawn natively in the widget (widgets can't host the app's views).
private struct WidgetPolaroid: View {
    let memory: MemorySnapshot.Memory
    let image: UIImage?

    var body: some View {
        GeometryReader { geo in
            let format = memory.frameFormat
            let fit = fitted(in: geo.size, aspect: format.frameAspect)
            let pad = fit.width * 0.045
            VStack(spacing: 0) {
                Color.clear
                    .overlay {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color(white: 0.2)
                        }
                    }
                    .clipped()
                    .padding([.horizontal, .top], pad)
                Text(memory.caption.isEmpty ? " " : memory.caption)
                    .font(.custom("Bradley Hand", size: max(8, fit.width * 0.08)))
                    .foregroundStyle(.black.opacity(0.65))
                    .lineLimit(1)
                    .padding(.horizontal, pad)
                    .frame(height: fit.height * 0.14)
            }
            .frame(width: fit.width, height: fit.height)
            .background(Color(widgetHex: memory.frameColorHex) ?? .white)
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(memory.frameFormat.frameAspect, contentMode: .fit)
    }

    private func fitted(in size: CGSize, aspect: CGFloat) -> CGSize {
        size.width / size.height > aspect
            ? CGSize(width: size.height * aspect, height: size.height)
            : CGSize(width: size.width, height: size.width / aspect)
    }
}

private extension Color {
    init?(widgetHex hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

#Preview(as: .systemMedium) {
    MemoriesWidget()
} timeline: {
    MemoryEntry(date: .now, content: .locked)
    MemoryEntry(date: .now, content: .empty)
}
