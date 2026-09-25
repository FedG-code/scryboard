import SwiftUI
import ScryboardKit
import ScryboardUI

/// Milestone 2 placeholder. Milestone 6 replaces this with onboarding
/// (enable keyboard, Full Access, paste-permission explainer) and the
/// attribution screen. The attribution text is already here because it is
/// non-negotiable and must never be absent from a build.
struct ContentView: View {
    @State private var preferences = PreferencesStore.shared.load()

    var body: some View {
        NavigationStack {
            List {
                Section("Set up") {
                    Label("Settings › General › Keyboard › Keyboards › Add New Keyboard › Scryboard", systemImage: "keyboard")
                    Label("Then open Scryboard in that list and turn on Allow Full Access so it can reach Scryfall.", systemImage: "network")
                }
                Section {
                    // Pushed lists and segments, not drop-down menus: the
                    // menu picker's press animation on iOS 26 has no switch.
                    Picker("Sort results by", selection: $preferences.order) {
                        ForEach(SearchOrder.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                    Picker("Direction", selection: $preferences.direction) {
                        ForEach(SortDirection.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Card size", selection: $preferences.cardSize) {
                        ForEach(CardSize.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Search results")
                }
                Section {
                    Picker("Tapping a card copies", selection: $preferences.copyFormat) {
                        ForEach(CopyFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Copying")
                } footer: {
                    Text("Text copies the card’s name. From the printings view (hold a card) it copies the printing instead, as Name (SET) number, the line Moxfield and Arena understand.")
                }
                Section("About") {
                    Text(Attribution.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Scryboard")
            .onAppear { preferences = PreferencesStore.shared.load() }
            .onChange(of: preferences) { updated in PreferencesStore.shared.save(updated) }
        }
    }
}

enum Attribution {
    static let text = """
    Card data and images provided by Scryfall. Scryboard is unofficial Fan Content \
    permitted under the Wizards of the Coast Fan Content Policy. Not approved or \
    endorsed by Scryfall or Wizards of the Coast. Magic: The Gathering is a \
    trademark of Wizards of the Coast LLC.
    """
}

#Preview {
    ContentView()
}
