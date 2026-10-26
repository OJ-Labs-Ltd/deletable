import SwiftUI
import AppKit

struct CleanView: View {
    @EnvironmentObject var cleaner: Cleaner
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Clean")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Common places where junk piles up. Everything except the Trash is moved to the Trash, so you can still restore it.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if cleaner.isMeasuring {
                    ProgressView().controlSize(.small)
                }
                Button {
                    cleaner.measure()
                } label: {
                    Label("Re-measure", systemImage: "arrow.clockwise")
                }
                .disabled(cleaner.isMeasuring || cleaner.isCleaning)
            }
            .padding(28)

            ScrollView {
                VStack(spacing: 10) {
                    if cleaner.results.isEmpty && cleaner.isMeasuring {
                        Text("Measuring…")
                            .foregroundStyle(.secondary)
                            .padding(40)
                    }
                    ForEach(cleaner.visibleCategories) { cat in
                        CleanRow(category: cat)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }

            HStack {
                if let message = cleaner.message {
                    Label(message, systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .lineLimit(2)
                }
                Spacer()
                Text("Selected: \(cleaner.selectedTotal.formattedBytes)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Button {
                    confirm = true
                } label: {
                    Label(cleaner.isCleaning ? "Cleaning…" : "Clean", systemImage: "sparkles")
                        .frame(minWidth: 90)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(cleaner.selectedTotal == 0 || cleaner.isCleaning || cleaner.isMeasuring)
            }
            .padding(.horizontal, 28)
            .frame(height: 66)
            .background(Theme.panel)
            .overlay(alignment: .top) { Divider() }
        }
        .confirmationDialog("Clean \(cleaner.selectedTotal.formattedBytes)?", isPresented: $confirm) {
            Button("Clean", role: .destructive) { cleaner.cleanSelected() }
        } message: {
            Text(confirmText)
        }
        .onAppear { if cleaner.results.isEmpty { cleaner.measure() } }
    }

    private var confirmText: String {
        let names = cleaner.categories
            .filter { cleaner.selected.contains($0.id) && (cleaner.results[$0.id]?.size ?? 0) > 0 }
            .map(\.title)
        var text = "This will clear: " + names.joined(separator: ", ") + "."
        if cleaner.selected.contains("trash") {
            text += "\n\nItems already in the Trash are deleted permanently."
        }
        return text
    }
}

struct CleanRow: View {
    @EnvironmentObject var cleaner: Cleaner
    let category: CleanCategory

    var body: some View {
        let result = cleaner.results[category.id]
        let isOn = Binding(
            get: { cleaner.selected.contains(category.id) },
            set: { on in
                if on { cleaner.selected.insert(category.id) } else { cleaner.selected.remove(category.id) }
            })

        HStack(spacing: 14) {
            Toggle("", isOn: isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(result?.error != nil || (result?.size ?? 0) == 0)

            Image(systemName: category.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(category.permanent ? Color.red : Theme.accent)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.06)))

            VStack(alignment: .leading, spacing: 3) {
                Text(category.title).font(.headline)
                if let error = result?.error {
                    HStack(spacing: 6) {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        Button("Open Settings") { AppState.openFullDiskAccessSettings() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                } else {
                    Text(category.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text((result?.size ?? 0).formattedBytes)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text("\(result?.itemCount ?? 0) items")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([category.root])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
    }
}
