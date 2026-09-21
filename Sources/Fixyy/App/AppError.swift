import Foundation

public enum AppError: Error, Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case openAccessibility
        case openIntelligence
        case retry
        case copyResult
    }

    case accessibilityDenied
    case intelligenceOff
    case modelDownloading
    case deviceIneligible
    case modelUnavailable
    case unsupportedLanguage
    case tooLong(estimated: Int?, fits: Int)
    case guardrail
    case refusal
    case rateLimited
    case stalled
    case emptySelection
    case secureField
    case pasteFailed
    case cancelled

    public var message: String {
        switch self {
        case .accessibilityDenied: "Fixyy needs Accessibility to read your selection"
        case .intelligenceOff: "Apple Intelligence is off"
        case .modelDownloading: "Apple’s model is still downloading"
        case .deviceIneligible: "This Mac can’t run the on-device model"
        case .modelUnavailable: "On-device model isn’t available"
        case .unsupportedLanguage: "The model doesn’t support this language yet"
        case .tooLong(let estimated, let fits):
            if let estimated {
                "Selection is ~\(estimated.formatted()) tokens; this model fits ~\(fits.formatted())"
            } else {
                "Selection is too long; this model fits ~\(fits.formatted()) tokens"
            }
        case .guardrail: "Blocked by Apple’s content filter"
        case .refusal: "The model declined this request"
        case .rateLimited: "Model is busy — try again in a moment"
        case .stalled: "Model stopped responding"
        case .emptySelection: "No text selected"
        case .secureField: "Won’t edit a password field"
        case .pasteFailed: "Couldn’t paste — result copied to clipboard"
        case .cancelled: ""
        }
    }

    public var detail: String? {
        switch self {
        case .tooLong(let estimated, let fits):
            guard let estimated else { return nil }
            return "\(estimated.formatted()) prompt tokens vs ~\(fits.formatted()) available"
        default:
            return nil
        }
    }

    public var action: Action? {
        switch self {
        case .accessibilityDenied: .openAccessibility
        case .intelligenceOff: .openIntelligence
        case .modelDownloading, .refusal, .rateLimited, .stalled: .retry
        default: nil
        }
    }

    public var opensAccessibilitySettings: Bool { self == .accessibilityDenied }
    public var opensIntelligenceSettings: Bool { self == .intelligenceOff }
}

public enum ModelAvailability: Equatable, Sendable {
    case available
    case deviceNotEligible
    case intelligenceOff
    case modelNotReady
    case other

    public var error: AppError? {
        switch self {
        case .available: nil
        case .deviceNotEligible: .deviceIneligible
        case .intelligenceOff: .intelligenceOff
        case .modelNotReady: .modelDownloading
        case .other: .modelUnavailable
        }
    }

    public var settingsLabel: String {
        switch self {
        case .available: "Available"
        case .deviceNotEligible: "This Mac isn’t eligible"
        case .intelligenceOff: "Turned off"
        case .modelNotReady: "Still downloading"
        case .other: "Unavailable"
        }
    }
}

public enum RewriteKind: Hashable, Sendable {
    case shorter
    case clearer
    case formal
    case friendly
    case custom(String)

    public var chipTitle: String {
        switch self {
        case .shorter: "Shorter"
        case .clearer: "Clearer"
        case .formal: "Formal"
        case .friendly: "Friendly"
        case .custom: "Custom"
        }
    }

    public static let modes: [RewriteKind] = [.shorter, .clearer, .formal, .friendly]
}

public enum RewriteSampling: Equatable, Sendable {
    case automatic
    case randomTop(Int)
}

public enum SelectionCapture: Equatable, Sendable {
    case text(String)
    case empty
    case secure
}

public let selectionCharacterLimit = 4000
public let styleNoteCharacterLimit = 500
public let modelTimeoutNanoseconds: UInt64 = 20_000_000_000
