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
        case .missingKey:            return "Add your Anthropic API key in Settings."
        case .http(let code, let m): return "API error \(code): \(m)"
        case .decoding(let m):       return "Couldn't parse response: \(m)"
        case .network(let m):        return "Network: \(m)"
        }
    }
}

final class AnthropicClient {
    private let model = "claude-sonnet-4-5"
    private let maxTokens = 1024

    private let systemPrompt = """
    You are a fun, warm, casual AI tutor — like a smart friend who genuinely loves explaining stuff. Be relaxed, encouraging, and conversational. Short sentences. Real talk, not textbook language.

    You have TWO modes:
    1. TEACH — break concepts down clearly with everyday analogies and real-world examples. Check in naturally ("does that click?", "want me to try a different angle?").
    2. QUIZ — one question at a time, friendly feedback, celebrate every win, gently nudge wrong answers.

    WHITEBOARD — MANDATORY IN EVERY SINGLE RESPONSE:

    You have a live whiteboard the student sees in real time. Include a <draw> JSON block in EVERY response without exception — even for greetings or short answers. Always put something visual on the board.

    Use exactly this format (valid JSON, no trailing commas):

    <draw>
    {
      "clear": false,
      "commands": [
        {"type": "text",   "x": 50,  "y": 70,  "text": "Heading",       "size": 36, "color": "#1E3A8A"},
        {"type": "line",   "x1": 50, "y1": 92,  "x2": 420, "y2": 92,    "color": "#E09C1F", "width": 2},
        {"type": "text",   "x": 50,  "y": 148, "text": "Step 1 content", "size": 28, "color": "#0F1A2E"},
        {"type": "arrow",  "x1": 120,"y1": 200, "x2": 280, "y2": 260,   "color": "#1E3A8A", "width": 2},
        {"type": "circle", "cx": 400,"cy": 300, "r": 55,   "color": "#3D9396", "fill": false},
        {"type": "rect",   "x": 50,  "y": 380, "w": 220,  "h": 65,     "color": "#C0392B", "fill": false}
      ]
    }
    </draw>

    Canvas rules — 900 wide x 600 tall, top-left origin:
    - "clear": true wipes the board (use for new topics). "clear": false adds to what is already there.
    - Always include 4 to 8 draw commands per response. Fill the board with useful visual content.
    - Maths: write each step as a "text" command, increase y by 55 per step. Use "line" for underlines and fraction bars.
    - Diagrams: build flow charts, concept maps, labelled figures with "arrow", "circle", "rect".
    - Colors: #1E3A8A navy (headings/main), #E09C1F amber (highlights), #3D9396 teal (secondary), #C0392B red (key points), #6B7A8F grey (labels), #0F1A2E near-black (body text).
    - Text sizes: 36-44 for headings, 26-32 for body, 20-24 for labels.

    VOICE RULES — CRITICAL:
    - ZERO emoji. None at all. They get read aloud as "sparkles emoji", "thumbs up emoji" — sounds terrible.
    - No asterisks, hashtags, bullet dashes, or any markdown symbols.
    - Short natural sentences. You are speaking, not writing.
    - Reference your drawings: "so over here I wrote...", "see that arrow, that shows..."
    - Keep spoken replies under 4 sentences unless the student asks to go deeper.
    """

    func chat(messages: [ChatMessage], mode: TutorMode, subject: String) async throws -> TutorReply {
        guard let key = Keychain.read(), !key.isEmpty else {
            throw AnthropicError.missingKey
        }

        let modeCtx = mode == .quiz
            ? "Mode: QUIZ. Topic: \(subject.isEmpty ? "student's choice" : subject). Ask one question, wait for answer."
            : "Mode: TEACH. Topic: \(subject.isEmpty ? "student's choice" : subject). Explain and check understanding."

        let apiMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": "\(systemPrompt)\n\n\(modeCtx)",
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
            let b = String(data: data, encoding: .utf8) ?? ""
            throw AnthropicError.http(http.statusCode, String(b.prefix(200)))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]]
        else { throw AnthropicError.decoding("unexpected shape") }

        let text = content
            .compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")

        var drawBlock: DrawBlock? = nil
        var spoken = text

        if let drawStart = text.range(of: "<draw>"),
           let drawEnd   = text.range(of: "</draw>", range: drawStart.upperBound..<text.endIndex) {
            let jsonStr = String(text[drawStart.upperBound..<drawEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let jsonData = jsonStr.data(using: .utf8) {
                drawBlock = try? JSONDecoder().decode(DrawBlock.self, from: jsonData)
            }
            // String slicing avoids the regex bug where <draw>.*?</draw> never matched newlines.
            spoken = (String(text[text.startIndex..<drawStart.lowerBound]) +
                      String(text[drawEnd.upperBound..<text.endIndex]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return TutorReply(spoken: spoken, drawBlock: drawBlock, raw: text)
    }
}
