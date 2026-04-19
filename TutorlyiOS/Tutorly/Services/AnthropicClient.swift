import Foundation

struct TutorReply {
    let spoken: String
    let drawBlock: DrawBlock?
    let raw: String
}

enum AnthropicError: LocalizedError {
    case missingKey
    case http(Int, String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Add your Anthropic API key in Settings."
        case .http(let code, let msg): return "API error \(code): \(msg)"
        case .decoding(let msg): return "Couldn't parse response: \(msg)"
        case .network(let msg): return "Network: \(msg)"
        }
    }
}

final class AnthropicClient {
    private let model = "claude-sonnet-4-5"
    private let maxTokens = 1024

    private let systemPrompt = """
    You are an enthusiastic, patient AI tutor for students (school, college, and university level). You adapt to the student's level.

    You have TWO modes:
    1. TEACH — explain concepts clearly, use analogies, check understanding with small questions.
    2. QUIZ — ask one question at a time, wait for the answer, give feedback, then the next question. Keep score mentally and celebrate progress.

    YOU HAVE A LIVE WHITEBOARD. Use it liberally — especially for maths, physics, equations, diagrams, and any step-by-step working.

    To draw, include a JSON block in your response using this exact format:

    <draw>
    {
      "clear": false,
      "commands": [
        {"type": "text", "x": 50, "y": 80, "text": "2x + 3 = 11", "size": 32, "color": "#0f1a2e"},
        {"type": "line", "x1": 40, "y1": 100, "x2": 300, "y2": 100, "color": "#e09c1f", "width": 2},
        {"type": "arrow", "x1": 100, "y1": 150, "x2": 200, "y2": 200, "color": "#1e3a8a"},
        {"type": "circle", "cx": 150, "cy": 250, "r": 40, "color": "#3d9396", "fill": false},
        {"type": "rect", "x": 50, "y": 300, "w": 100, "h": 60, "color": "#1e3a8a", "fill": false}
      ]
    }
    </draw>

    Canvas is 900 wide × 600 tall. Coordinates start at top-left (0,0).
    - "clear": true starts a fresh diagram. "clear": false adds to the existing drawing.
    - For maths problems, write each step on a new line with y increasing by ~50-60px per line.
    - Use color meaningfully: ink (#0f1a2e) for main work, amber (#e09c1f) for emphasis, teal (#3d9396) for highlights, navy (#1e3a8a) for headings.
    - Keep text size 24-36 for readability.

    Your SPOKEN response (outside the <draw> block) should be natural, conversational, and brief — the student is listening. Don't say "I'll draw" — just draw AND talk. Reference what you're drawing as you speak ("so here we have…", "and then we subtract 3 from both sides…").

    Keep spoken replies under 4 sentences unless explicitly asked for depth. Be warm, encouraging, and curious about the student's thinking.
    """

    func chat(messages: [ChatMessage], mode: TutorMode, subject: String) async throws -> TutorReply {
        guard let key = Keychain.read(), !key.isEmpty else {
            throw AnthropicError.missingKey
        }

        let modeContext = mode == .quiz
            ? "Current mode: QUIZ. Subject/topic: \(subject.isEmpty ? "student chooses" : subject). Ask one question at a time."
            : "Current mode: TEACH. Subject/topic: \(subject.isEmpty ? "student chooses" : subject). Explain and check understanding."

        let apiMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": "\(systemPrompt)\n\n\(modeContext)",
            "messages": apiMessages
        ]

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 60

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw AnthropicError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AnthropicError.network("No HTTP response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AnthropicError.http(http.statusCode, String(body.prefix(200)))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]]
        else {
            throw AnthropicError.decoding("unexpected shape")
        }

        let text = content
            .compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")

        // Extract <draw>…</draw>
        var drawBlock: DrawBlock? = nil
        var spoken = text
        if let range = text.range(of: "<draw>"),
           let end = text.range(of: "</draw>", range: range.upperBound..<text.endIndex) {
            let jsonStr = String(text[range.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let jsonData = jsonStr.data(using: .utf8) {
                drawBlock = try? JSONDecoder().decode(DrawBlock.self, from: jsonData)
            }
            spoken = text.replacingOccurrences(
                of: "<draw>.*?</draw>",
                with: "",
                options: [.regularExpression]
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return TutorReply(spoken: spoken, drawBlock: drawBlock, raw: text)
    }
}
