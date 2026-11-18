import Foundation
import Testing
@testable import WidgetKitCore

/// The catalog is the single source of truth (ADR-027): these fail when a list drifts from
/// `capabilities.json`, or a capability in it has no implementation.
struct CapabilityDriftTests {
    private var aiActions: [String] { Capabilities.actions.filter(\.ai).map(\.id) }

    @Test func catalogIsWellFormed() {
        let bindings = Capabilities.bindings
        let actions = Capabilities.actions
        #expect(bindings.count > 80 && actions.count > 30, "capabilities.json did not load")
        #expect(Set((bindings + actions).map(\.id)).count == bindings.count + actions.count, "duplicate ids")
        let groups = Set(Capabilities.groups.map(\.id))
        let permissions = Set(Capabilities.permissions.map(\.id))
        for capability in bindings + actions {
            #expect(groups.contains(capability.group), "\(capability.id): unknown group")
            #expect(!capability.description.isEmpty, "\(capability.id): no description")
            if case .localized(let en, let ar) = capability.title {
                #expect(!en.isEmpty && !ar.isEmpty, "\(capability.id): empty title")
            } else {
                Issue.record("\(capability.id): the title needs en and ar")
            }
            for icon in capability.icons { #expect(Icons.isAllowed(icon), "\(capability.id): icon \(icon) is not whitelisted") }
            for platform in [CapabilityPlatform.ios, .android] {
                if let permission = capability.permission(on: platform) {
                    #expect(permissions.contains(permission), "\(capability.id): unknown permission \(permission)")
                }
            }
        }
        for binding in bindings {
            #expect(binding.type != nil, "\(binding.id): no type")
            #expect(!binding.layers.isEmpty, "\(binding.id): no layers")
            #expect(binding.example != nil, "\(binding.id): no example")
        }
        for action in actions {
            #expect(action.support(on: .ios) != .panel, "\(action.id): iOS has no panels")
            #expect(action.support(on: .android) != .shortcut, "\(action.id): Android has no Shortcuts")
            if let state = action.state { #expect(Capabilities.binding(state) != nil, "\(action.id): unknown state \(state)") }
            if action.support(on: .ios) == .shortcut, action.id != "shortcut.run" {
                #expect(action.shortcut != nil, "\(action.id): no Shortcut recipe")
            }
        }
    }

    /// The validator's list is built from the catalog, and takes exactly its non-parametric ids.
    @Test func validatorWhitelistMatches() {
        #expect(Set(Bindings.catalog.keys) == Set(Capabilities.bindings.filter { !$0.parametric }.map(\.id)))
        for binding in Capabilities.bindings where !binding.parametric {
            let name = Bindings.Name(binding.id)
            #expect(name != nil, "\(binding.id) doesn't parse")
            if let name { #expect(SpecValidator.allowsInAI(name) == binding.ai, "\(binding.id)") }
        }
        for action in ButtonLayer.Action.allCases {
            #expect(SpecValidator.allowsInAI(action) == (Capabilities.action(action.rawValue)?.ai ?? false))
        }
    }

    @Test func promptAndInstructionsListEveryId() {
        let instructions = ExternalAI.instructions(options: GenerationOptions())
        for text in [WidgetPrompt.system, instructions] {
            for binding in Capabilities.bindings where binding.ai {
                #expect(text.contains("{{\(binding.id)}}"), "missing {{\(binding.id)}}")
            }
            for binding in Capabilities.bindings where !binding.ai {
                #expect(!text.contains("{{\(binding.id)}}"), "{{\(binding.id)}} must not be offered")
            }
            for action in aiActions { #expect(text.contains("`\(action)`"), "missing \(action)") }
        }
    }

    @Test func aiSchemaListsEveryAction() throws {
        let text = AIWidgetSchema.schema(mode: .recreate).jsonString()
        for action in aiActions { #expect(text.contains("\"\(action)\""), "schema misses \(action)") }
        // ADR-029: any SF Symbol name is allowed (a pattern), so symbol bindings are listed in the prompt instead.
        for binding in Capabilities.bindings where binding.type == "symbol" && binding.ai {
            #expect(WidgetPrompt.system.contains("{{\(binding.id)}}"), "prompt misses {{\(binding.id)}}")
        }
    }

    /// Every live value has a provider or at least a preview value, so nothing renders "--" in the app.
    @Test func everyBindingResolvesInPreviews() {
        let spec = WidgetSpec(id: "t", name: "t", family: .small, background: Background(type: .solid, color: "#000000"), layers: [])
        let resolver = BindingResolver(spec: spec, context: RenderContext(data: .sample()))
        // counter.progress needs the spec's `target` field; the validator says so.
        for binding in Capabilities.bindings where !binding.parametric && binding.type != "image" && binding.id != "counter.progress" {
            #expect(resolver.value(of: binding.id) != nil, "\(binding.id) resolves to nothing")
        }
    }

    /// Native on iOS means something performs it: the extension or the app.
    @Test func everyNativeActionIsImplemented() {
        let implemented = NativeActions.widgetExtension.union(NativeActions.app)
        for action in Capabilities.actions where action.support(on: .ios) == .native {
            #expect(implemented.contains(action.id), "\(action.id) is native on iOS but nothing performs it")
        }
        #expect(implemented.isSubset(of: Set(Capabilities.actions.map(\.id))), "NativeActions lists an unknown action")
    }

    @Test func permissionsFollowTheSpec() {
        let layers = [
            Layer(frame: Frame(x: 0, y: 0, w: 10, h: 10), content: .button(ButtonLayer(action: ButtonLayer.Action(rawValue: "media.next")))),
            Layer(frame: Frame(x: 0, y: 0, w: 10, h: 10), content: .button(ButtonLayer(action: ButtonLayer.Action(rawValue: "system.toggle.dnd")))),
        ]
        let spec = WidgetSpec(id: "t", name: "t", family: .small, background: Background(type: .solid, color: "#000000"), layers: layers)
        #expect(Capabilities.permissions(for: spec, on: .ios).map(\.id) == ["mediaLibrary", "shortcut"])
        #expect(Capabilities.permissions(for: spec, on: .android).map(\.id) == ["notificationAccess", "dndAccess"])
    }
}
