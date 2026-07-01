import SwiftUI

/// The set of filters the Events page applies on top of the shared event-range
/// window. Everything defaults to "show all".
struct EventFilter {
    var kinds: Set<EventKind> = Set(EventKind.allCases)
    var toolName: String?
    var errorsOnly = false
    var searchText = ""

    /// Whether any filter narrows the list (drives the "Clear filters" affordance).
    var isActive: Bool {
        kinds.count != EventKind.allCases.count
            || toolName != nil
            || errorsOnly
            || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Events mode: the session's full, time-ordered event list as an expandable
/// list — the same row presentation the Analysis tab used to show at its bottom
/// — honoring the shared event-range window plus a rich per-page filter bar.
struct EventsView: View {
    let session: Session
    let appliedRange: ClosedRange<Int>?
    @Binding var filter: EventFilter

    var body: some View {
        let items = filteredEvents
        VStack(spacing: 0) {
            filterBar(matching: items.count)
            Divider()
            if items.isEmpty {
                ContentUnavailableLabel(
                    "No events match", systemImage: "line.3.horizontal.decrease.circle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(items) { EventRow(item: $0) }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Filter bar

    private func filterBar(matching count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(appliedRange == nil ? "Events" : "Events in range")
                    .font(.headline)
                Text("\(count)")
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                if filter.isActive {
                    Button("Clear filters") { filter = EventFilter() }
                        .buttonStyle(.borderless)
                }
            }
            HStack(spacing: 8) {
                searchField
                toolMenu
                Toggle(isOn: $filter.errorsOnly) {
                    Label("Errors", systemImage: "exclamationmark.triangle")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                Spacer(minLength: 0)
            }
            FlowLayout(spacing: 6) {
                ForEach(EventKind.allCases) { kind in
                    KindChip(kind: kind, isOn: filter.kinds.contains(kind)) {
                        toggle(kind)
                    }
                }
            }
        }
        .padding(12)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search text", text: $filter.searchText)
                .textFieldStyle(.plain)
            if !filter.searchText.isEmpty {
                Button { filter.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: 260)
    }

    private var toolMenu: some View {
        Menu {
            Button("All tools") { filter.toolName = nil }
            if !availableTools.isEmpty {
                Divider()
                ForEach(availableTools, id: \.self) { name in
                    Button {
                        filter.toolName = (filter.toolName == name) ? nil : name
                    } label: {
                        if filter.toolName == name {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
            }
        } label: {
            Label(filter.toolName ?? "All tools", systemImage: "wrench.and.screwdriver")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(availableTools.isEmpty)
    }

    private func toggle(_ kind: EventKind) {
        if filter.kinds.contains(kind) {
            filter.kinds.remove(kind)
        } else {
            filter.kinds.insert(kind)
        }
    }

    // MARK: - Filtering

    /// Events within the applied range that satisfy every active filter.
    private var filteredEvents: [EventItem] {
        let toolNames = toolNameByCallID
        return session.events.enumerated().compactMap { index, event in
            if let range = appliedRange, !range.contains(index) { return nil }
            guard matches(event.payload, toolNames: toolNames) else { return nil }
            return EventItem(id: index, time: event.timestamp, payload: event.payload)
        }
    }

    private func matches(_ payload: Event.Payload, toolNames: [String: String]) -> Bool {
        guard filter.kinds.contains(payload.kind) else { return false }
        if let tool = filter.toolName {
            switch payload {
            case .toolCall(let call):
                if call.name != tool { return false }
            case .toolResult(let result):
                guard let id = result.callID, toolNames[id] == tool else { return false }
            default:
                return false   // non-tool events are hidden while a tool is selected
            }
        }
        if filter.errorsOnly, !payload.isError { return false }
        let query = filter.searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            let haystack = payload.kindLabel + "\n" + payload.detailText
            if !haystack.localizedCaseInsensitiveContains(query) { return false }
        }
        return true
    }

    /// Maps each tool call's id to its name, so results (which only carry a
    /// call id) can be matched against the selected tool.
    private var toolNameByCallID: [String: String] {
        var map: [String: String] = [:]
        for event in session.events {
            if case .toolCall(let call) = event.payload, let id = call.id {
                map[id] = call.name
            }
        }
        return map
    }

    /// Distinct tool names present in the session, sorted for the menu.
    private var availableTools: [String] {
        var names = Set<String>()
        for event in session.events {
            if case .toolCall(let call) = event.payload { names.insert(call.name) }
        }
        return names.sorted()
    }
}

/// A toggleable filter chip for one event kind.
private struct KindChip: View {
    let kind: EventKind
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 4) {
                Image(systemName: kind.icon)
                Text(kind.label)
            }
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(isOn ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12),
                        in: Capsule())
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            .overlay(Capsule().strokeBorder(
                isOn ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// One event, keyed by its position in the session's flat event list.
private struct EventItem: Identifiable {
    let id: Int
    let time: Date?
    let payload: Event.Payload
}

/// A collapsible row: one-line summary when closed, full content when opened.
private struct EventRow: View {
    let item: EventItem
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.15)) { expanded.toggle() }
            } label: {
                summaryRow
            }
            .buttonStyle(.plain)

            if expanded {
                expandedContent
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }

    private var summaryRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.payload.icon)
                .foregroundStyle(item.payload.isError ? Color.red : Color.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.payload.kindLabel).font(.callout).bold()
                    Spacer()
                    Text(item.time.map { $0.formatted(date: .omitted, time: .standard) } ?? "—")
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !expanded {
                    let detail = item.payload.detailText
                        .split(whereSeparator: \.isNewline).joined(separator: " ")
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.callout).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var expandedContent: some View {
        let text = item.payload.detailText
        if text.isEmpty {
            Text("(no content)").font(.caption).foregroundStyle(.tertiary)
        } else if let json = JSONHighlighter.highlightedIfJSON(text, limit: .max) {
            Text(json)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Minimal left-to-right wrapping layout for the filter chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                          anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
