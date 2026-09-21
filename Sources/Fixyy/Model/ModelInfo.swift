import Foundation
import FoundationModels

@MainActor
@Observable
public final class ModelInfo {
    private let model: SystemLanguageModel

    public init(model: SystemLanguageModel) {
        self.model = model
    }

    public var availability: ModelAvailability {
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .intelligenceOff
            case .modelNotReady: return .modelNotReady
            @unknown default: return .other
            }
        @unknown default:
            return .other
        }
    }

    public var variantName: String {
        if #available(macOS 27.0, *) {
            return model.variant.displayName
        }
        return "On-device"
    }

    public var contextSize: Int {
        model.contextSize
    }

    public var supportsCurrentLocale: Bool {
        model.supportsLocale()
    }

    public var capabilities: [String] {
        guard #available(macOS 27.0, *) else { return [] }
        var names: [String] = []
        let capabilities = model.capabilities
        if capabilities.contains(.guidedGeneration) { names.append("Guided generation") }
        if capabilities.contains(.toolCalling) { names.append("Tool calling") }
        if capabilities.contains(.vision) { names.append("Vision") }
        if capabilities.contains(.reasoning) { names.append("Reasoning") }
        return names
    }

    public var canCountTokens: Bool {
        if #available(macOS 26.4, *) { return true }
        return false
    }

    public var statusLine: String {
        Self.statusLine(availability: availability, variantName: variantName, contextSize: contextSize)
    }

    nonisolated public static func statusLine(availability: ModelAvailability, variantName: String, contextSize: Int) -> String {
        switch availability {
        case .available:
            "\(variantName) · On-device · \(contextSize.formatted()) ctx"
        case .intelligenceOff:
            "Unavailable · Apple Intelligence is off"
        case .deviceNotEligible:
            "Unavailable · This Mac isn’t eligible"
        case .modelNotReady:
            "Unavailable · Model is still downloading"
        case .other:
            "Unavailable · On-device model"
        }
    }
}
