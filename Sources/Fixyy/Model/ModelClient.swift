import Foundation
import FoundationModels

@MainActor
public final class ModelClient: LanguageGenerating {
    private let model: SystemLanguageModel
    public let info: ModelInfo

    public init() {
        let model = SystemLanguageModel(
            useCase: .general,
            guardrails: .permissiveContentTransformations
        )
        self.model = model
        self.info = ModelInfo(model: model)
    }

    public var availability: ModelAvailability {
        info.availability
    }

    public func prewarm() {
        LanguageModelSession(model: model).prewarm()
    }

    public func fixGrammar(text: String, styleNote: String) async throws -> FixResult {
        let output = try await respond(
            instructions: Prompts.fixInstructions(styleNote: styleNote),
            prompt: Prompts.fixPrompt(text),
            options: GenerationOptions(samplingMode: .greedy, temperature: 0)
        )
        return FixResult.from(original: text, modelOutput: output)
    }

    public func rewrite(
        text: String,
        kind: RewriteKind,
        styleNote: String,
        sampling: RewriteSampling
    ) -> AsyncThrowingStream<String, Error> {
        let instructions = Prompts.rewriteInstructions(styleNote: styleNote)
        let prompt = Prompts.rewritePrompt(text, kind: kind)
        let options: GenerationOptions
        switch sampling {
        case .automatic:
            options = GenerationOptions()
        case .randomTop(let top):
            options = GenerationOptions(samplingMode: .random(top: top))
        }
        let model = self.model
        return AsyncThrowingStream { continuation in
            let gate = StreamGate()
            let task = Task {
                do {
                    let session = LanguageModelSession(model: model, instructions: instructions)
                    var iterator = session.streamResponse(to: prompt, options: options).makeAsyncIterator()
                    while let snapshot = try await iterator.next() {
                        await gate.markToken()
                        continuation.yield(FixResult.clean(snapshot.content))
                    }
                    await gate.finish()
                    continuation.finish()
                } catch {
                    await gate.finish()
                    continuation.finish(throwing: Self.map(error))
                }
            }
            let watchdog = Task {
                try? await Task.sleep(nanoseconds: modelTimeoutNanoseconds)
                if await gate.claimTimeout() {
                    task.cancel()
                    continuation.finish(throwing: AppError.stalled)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                watchdog.cancel()
            }
        }
    }

    public func tokenCount(instructions: String, prompt: String) async -> Int? {
        guard #available(macOS 26.4, *) else { return nil }
        async let promptCount = model.tokenCount(for: prompt)
        async let instructionCount = model.tokenCount(for: Instructions(instructions))
        guard let promptTokens = try? await promptCount,
              let instructionTokens = try? await instructionCount
        else { return nil }
        return promptTokens + instructionTokens
    }

    private func respond(instructions: String, prompt: String, options: GenerationOptions) async throws -> String {
        let model = self.model
        do {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    let session = LanguageModelSession(model: model, instructions: instructions)
                    let response = try await session.respond(to: prompt, options: options)
                    return response.content
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: modelTimeoutNanoseconds)
                    throw AppError.stalled
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } catch is CancellationError {
            throw AppError.cancelled
        } catch let error as AppError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    nonisolated public static func map(_ error: Error) -> AppError {
        if error is CancellationError { return .cancelled }
        if let app = error as? AppError { return app }
        if #available(macOS 27.0, *) {
            if let modelError = error as? LanguageModelError {
                switch modelError {
                case .contextSizeExceeded(let context):
                    return .tooLong(estimated: nil, fits: context.contextSize)
                case .guardrailViolation:
                    return .guardrail
                case .refusal:
                    return .refusal
                case .rateLimited:
                    return .rateLimited
                case .unsupportedLanguageOrLocale:
                    return .unsupportedLanguage
                default:
                    return .stalled
                }
            }
            if let sessionError = error as? LanguageModelSession.Error {
                switch sessionError {
                case .concurrentRequests:
                    return .rateLimited
                default:
                    return .stalled
                }
            }
            if let modelError = error as? SystemLanguageModel.Error {
                switch modelError {
                case .assetsUnavailable:
                    return .modelDownloading
                default:
                    return .stalled
                }
            }
        }
        if let generationError = error as? LanguageModelSession.GenerationError {
            switch generationError {
            case .exceededContextWindowSize:
                return .tooLong(estimated: nil, fits: 4096)
            case .guardrailViolation:
                return .guardrail
            case .refusal:
                return .refusal
            case .rateLimited, .concurrentRequests:
                return .rateLimited
            case .unsupportedLanguageOrLocale:
                return .unsupportedLanguage
            case .assetsUnavailable:
                return .modelDownloading
            default:
                return .stalled
            }
        }
        return .stalled
    }
}

private actor StreamGate {
    private var sawToken = false
    private var finished = false

    func markToken() {
        sawToken = true
    }

    func finish() {
        finished = true
    }

    func claimTimeout() -> Bool {
        guard !sawToken, !finished else { return false }
        finished = true
        return true
    }
}
