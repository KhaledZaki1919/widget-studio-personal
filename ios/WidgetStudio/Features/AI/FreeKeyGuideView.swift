import SwiftUI
import WidgetKitCore

/// "Get a free key" (M6): how to make a free Google Gemini key and where to paste it.
struct FreeKeyGuideView: View {
    var body: some View {
        List {
            Section {
                Text("keyguide.intro").font(M3Type.bodyMedium)
            }
            Section("keyguide.steps") {
                step(1, "keyguide.step1")
                step(2, "keyguide.step2")
                step(3, "keyguide.step3")
                step(4, "keyguide.step4")
            }
            Section {
                if let url = AIProviderKind.gemini.keyPageURL {
                    Link(destination: url) {
                        Label("keyguide.open", systemImage: "arrow.up.forward.square")
                    }
                    .accessibilityIdentifier("ax.keyguide.open")
                }
                NavigationLink {
                    AISettingsView()
                } label: {
                    Label("keyguide.paste", systemImage: "key")
                }
                .accessibilityIdentifier("ax.keyguide.settings")
            } footer: {
                Text("keyguide.footer")
            }
        }
        .m3List()
        .navigationTitle("keyguide.title")
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Text(verbatim: "\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(M3.primary.opacity(0.2)))
                .accessibilityHidden(true)
        }
    }
}
