import SwiftUI
import ScryboardKit

/// Milestone 2 placeholder. Milestone 6 replaces this with onboarding
/// (enable keyboard, Full Access, paste-permission explainer) and the
/// attribution screen. The attribution text is already here because it is
/// non-negotiable and must never be absent from a build.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Set up") {
                    Label("Settings › General › Keyboard › Keyboards › Add New Keyboard › Scryboard", systemImage: "keyboard")
                    Label("Then open Scryboard in that list and turn on Allow Full Access so it can reach Scryfall.", systemImage: "network")
                }
                Section("About") {
                    Text(Attribution.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Scryboard")
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
