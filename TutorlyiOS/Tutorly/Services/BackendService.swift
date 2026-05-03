import Foundation

enum BackendService {

    // MARK: - Configuration
    // Replace with your deployed backend URL.
    // The endpoint must return JSON:  { "token": "<ephemeral-openai-key>" }
    // See the Node.js / Cloudflare Worker example at the bottom of this file.
    static let tokenEndpointURL = "https://YOUR_BACKEND_URL/realtime-token"

    // MARK: - Token fetch

    static func fetchRealtimeToken() async throws -> String {
        // Developer fallback: if endpoint isn't configured yet, use any Keychain key
        if tokenEndpointURL.contains("YOUR_BACKEND_URL") {
            if let key = Keychain.read("openai"), !key.isEmpty { return key }
            throw URLError(.badURL, userInfo: [
                NSLocalizedDescriptionKey:
                    "Set BackendService.tokenEndpointURL to your backend URL, " +
                    "or temporarily add your OpenAI key in Settings for local dev."
            ])
        }

        guard let url = URL(string: tokenEndpointURL) else { throw URLError(.badURL) }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String, !token.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return token
    }
}

// MARK: - Backend code (deploy one of these)
//
// ── Node.js (Express) ────────────────────────────────────────────────────────
//
//   const express = require('express')
//   const app = express()
//
//   app.get('/realtime-token', async (req, res) => {
//     const r = await fetch('https://api.openai.com/v1/realtime/sessions', {
//       method: 'POST',
//       headers: {
//         Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
//         'Content-Type': 'application/json'
//       },
//       body: JSON.stringify({ model: 'gpt-4o-realtime-preview', voice: 'alloy' })
//     })
//     const data = await r.json()
//     res.json({ token: data.client_secret.value })
//   })
//
//   app.listen(3000)
//
// ── Cloudflare Worker (free tier, zero infrastructure) ───────────────────────
//
//   export default {
//     async fetch(request, env) {
//       const r = await fetch('https://api.openai.com/v1/realtime/sessions', {
//         method: 'POST',
//         headers: {
//           Authorization: `Bearer ${env.OPENAI_API_KEY}`,
//           'Content-Type': 'application/json'
//         },
//         body: JSON.stringify({ model: 'gpt-4o-realtime-preview', voice: 'alloy' })
//       })
//       const data = await r.json()
//       return Response.json({ token: data.client_secret.value })
//     }
//   }
//
//   Set env var OPENAI_API_KEY in the Worker's Settings → Variables.
//   Deploy with: wrangler deploy
