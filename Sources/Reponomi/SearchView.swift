import AppKit
import SwiftUI
import ReponomiCore

struct SearchView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var state: AppState
    @ObservedObject var workspace: LocalWorkspace
    /// Called with a row index when the row is clicked.
    var onActivate: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            results
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: SearchPanel.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12))
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            if let repo = model.lockedRepo {
                Text(repo.name)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
            }
            SearchField(
                text: $model.query,
                placeholder: model.lockedRepo == nil ? "Search repositories…" : "Where to?",
                focusRequest: model.focusRequest
            )
            if state.isRefreshing || !workspace.cloning.isEmpty {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    Color.clear.frame(height: 2).id(Row.topID)
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Group {
                            switch row {
                            case .repo(let match):
                                RepoRow(
                                    match: match,
                                    showsHost: state.config.spansHosts,
                                    isCloned: workspace.cloned.contains(match.repo.key),
                                    isIgnored: model.showsIgnored && state.config.ignored.contains(match.repo.key),
                                    badge: index == model.selection ? badge : nil
                                )
                            case .location(let location, _):
                                LocationRow(location: location)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .background(
                            index == model.selection ? Color.accentColor.opacity(0.22) : .clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onActivate(index) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .onChange(of: model.selection) {
                if rows.indices.contains(model.selection) { proxy.scrollTo(rows[model.selection].id) }
            }
            .onChange(of: model.query) { proxy.scrollTo(Row.topID, anchor: .top) }
        }
        .overlay {
            if let emptyMessage {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }

    /// The list's rows. Their ids name the content, not just the position:
    /// a lazy stack keeps showing stale rows when it sees an id it already
    /// rendered, even after the content behind that id changed kind.
    private var rows: [Row] {
        if model.lockedRepo == nil {
            return model.repoMatches.map(Row.repo)
        }
        return model.locationMatches.enumerated().map { Row.location($1, $0) }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text(status.text)
                .lineLimit(3)
                .truncationMode(.middle)
                .foregroundStyle(status.isWarning ? Color.orange : Color.secondary)
            Spacer(minLength: 12)
            // A warning needs the room more than the reminders do.
            if !status.isWarning {
                KeyHint(key: "↩", label: "Open")
                if let repo = model.selectedRepo, state.config.account(for: repo)?.workingDirectoryURL != nil {
                    KeyHint(key: "⇧↩", label: workspace.cloned.contains(repo.key) ? "Open folder" : "Clone")
                }
                if model.lockedRepo == nil {
                    KeyHint(key: "⇥", label: "Locations")
                } else {
                    KeyHint(key: "esc", label: "Back")
                }
                KeyHint(key: "⌘↩", label: "Copy URL")
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(minHeight: 30)
    }

    /// Where Return will go, shown on the selected repository.
    private var badge: String? {
        switch model.inlineLocation {
        case .none: return nil
        case .found(let location): return "→ \(location.name)"
        case .unknown(let text): return "No location “\(text)”"
        }
    }

    private var emptyMessage: String? {
        if model.lockedRepo != nil {
            return model.locationMatches.isEmpty ? "No matching location" : nil
        }
        guard model.repoMatches.isEmpty else { return nil }
        if !state.repos.isEmpty { return "No matching repositories" }
        if !state.config.hasSources { return "Add an organization in Settings (⌘,) to get started." }
        return state.isRefreshing ? "Loading repositories…" : "No repositories found. Press ⌘R to refresh."
    }

    /// The footer's text: whatever is most worth knowing right now.
    private var status: (text: String, isWarning: Bool) {
        if let name = workspace.cloning.last { return ("Cloning \(name)…", false) }
        if let problem = workspace.problem { return (problem, true) }
        if let message = model.message { return (message, false) }
        if let error = state.errors.first { return (error, true) }
        return (state.summary ?? (state.isRefreshing ? "Refreshing…" : ""), false)
    }
}

private enum Row: Identifiable {
    case repo(RepoMatch)
    case location(Location, Int)

    static let topID = "top"

    var id: String {
        switch self {
        case .repo(let match): return "repo-\(match.repo.htmlURL)"
        case .location(let location, let offset): return "location-\(offset)-\(location.name)"
        }
    }
}

private struct RepoRow: View {
    let match: RepoMatch
    /// Whether to say which host the repository is on.
    let showsHost: Bool
    let isCloned: Bool
    let isIgnored: Bool
    let badge: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: match.repo.isPrivate ? "lock" : "book.closed")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title).lineLimit(1)
                    if showsHost { Tag(text: match.repo.host) }
                    if isCloned { Tag(text: "local") }
                    if isIgnored { Tag(text: "ignored") }
                    if match.repo.isArchived { Tag(text: "archived") }
                    if match.repo.isFork { Tag(text: "fork") }
                }
                if let description = match.repo.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let badge {
                Text(badge)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
        }
        .opacity(isIgnored ? 0.55 : 1)
    }

    /// `owner/name` with the owner dimmed and the matched characters in bold.
    private var title: AttributedString {
        let ownerLength = match.repo.fullName.count - match.repo.name.count
        var title = AttributedString()
        for (offset, character) in match.repo.fullName.enumerated() {
            var piece = AttributedString(String(character))
            piece.foregroundColor = offset < ownerLength ? .secondary : .primary
            piece.font = .system(size: 14, weight: match.indices.contains(offset) ? .bold : .regular)
            title += piece
        }
        return title
    }
}

private struct LocationRow: View {
    let location: Location

    var body: some View {
        HStack(spacing: 10) {
            Text(location.name).font(.system(size: 14))
            Spacer(minLength: 8)
            if let key = location.keys.first {
                Tag(text: key)
            }
        }
    }
}

private struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key).fontWeight(.semibold)
            Text(label)
        }
        .foregroundStyle(.secondary)
        .fixedSize()
    }
}

/// An AppKit text field, so the panel can hand it keyboard focus reliably
/// each time it appears.
private struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 22)
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        field.placeholderString = placeholder
        if field.stringValue != text {
            field.stringValue = text
            field.currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var focusRequest = -1

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
