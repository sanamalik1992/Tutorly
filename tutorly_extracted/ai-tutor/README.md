# Tutorly 🎓

Your AI study buddy — talk to a tutor, get quizzed, and watch it **draw the solution live on a whiteboard**.

Built for students at school, college, and university. Pick a subject, tap the mic, and just start talking. The tutor explains concepts, quizzes you, and illustrates ideas by sketching directly on a virtual whiteboard (especially useful for maths, physics, and diagrams).

## Features

- 🎙 **Voice in** — speak your question naturally (Chrome/Edge Web Speech API)
- 🔊 **Voice out** — tutor replies are spoken aloud
- ✏️ **Live AI whiteboard** — the tutor draws equations, diagrams, arrows, and step-by-step working while it talks
- 🖊 **You can draw too** — pen, eraser, colours, sizes. Annotate the tutor's work or show your own working
- 📚 **Teach mode / Quiz mode** — switch between explanation and practice
- 🎯 **Any subject, any level** — algebra, calculus, physics, chemistry, history, essay writing, coding, and more
- 💬 **Text fallback** — type if you'd rather

## Prerequisites

- **Node.js 18+**
- **An Anthropic API key** — get one at <https://console.anthropic.com>
- **Chrome or Edge** (best voice support). Firefox/Safari will work for typing but have limited speech recognition.

## Quick start with Claude Code

If you're using Claude Code, from the project folder run:

```bash
claude
```

Then ask Claude Code to set it up for you, or do it manually:

```bash
# 1. Install dependencies
npm install

# 2. Add your API key
cp .env.example .env
# edit .env and paste your key from https://console.anthropic.com

# 3. Run both backend and frontend together
npm start
```

Open <http://localhost:5173>.

The `npm start` script runs the Express backend (port 3001) and the Vite dev server (port 5173) concurrently. You can also run them separately in two terminals with `npm run server` and `npm run dev`.

## How it works

```
┌──────────────┐  speech    ┌─────────────┐   HTTP    ┌──────────────┐
│  Your mic    │ ─────────► │  Browser    │ ────────► │  Express     │
│              │            │  (React)    │           │  backend     │
└──────────────┘            │             │           │              │
                            │  Whiteboard │ ◄──────── │  Anthropic   │
┌──────────────┐  speech    │   Canvas    │  draw +   │  Claude API  │
│  Speakers    │ ◄───────── │             │  speech   │              │
└──────────────┘            └─────────────┘           └──────────────┘
```

1. Your voice is converted to text via the browser's Web Speech API.
2. Text is sent to the Express backend, which calls Claude with a tutor system prompt.
3. Claude replies with natural speech **plus** an optional `<draw>...</draw>` JSON block.
4. The frontend speaks the reply aloud and renders the drawing commands on the canvas.

### The whiteboard language

The AI outputs structured draw commands the frontend interprets:

```json
{
  "clear": true,
  "commands": [
    { "type": "text", "x": 50, "y": 80, "text": "2x + 3 = 11", "size": 32 },
    { "type": "line", "x1": 40, "y1": 100, "x2": 300, "y2": 100, "color": "#e09c1f" },
    { "type": "arrow", "x1": 100, "y1": 150, "x2": 200, "y2": 200 },
    { "type": "circle", "cx": 150, "cy": 250, "r": 40 },
    { "type": "rect", "x": 50, "y": 300, "w": 100, "h": 60 },
    { "type": "path", "points": [[10,10],[50,40],[90,10]] }
  ]
}
```

Logical canvas size is 900 × 600 and scales to fit.

## Try saying…

- *"Teach me how to solve quadratic equations"*
- *"Can you quiz me on the French Revolution?"*
- *"I don't understand derivatives, can you explain?"*
- *"Show me how to do long division with 452 divided by 8"*
- *"Draw a diagram of the water cycle"*

## Project structure

```
tutorly/
├── server.js              # Express backend → Anthropic API
├── index.html
├── vite.config.js
├── package.json
├── .env.example
└── src/
    ├── main.jsx
    ├── App.jsx            # Main UI
    ├── styles.css         # Brand palette (navy / teal / amber)
    ├── components/
    │   └── Whiteboard.jsx # Canvas + AI command renderer
    └── hooks/
        ├── useSpeechRecognition.js
        └── useSpeechSynthesis.js
```

## Customising

- **System prompt** — edit `SYSTEM_PROMPT` in `server.js` to change tutor personality, style, or subject focus.
- **Model** — the backend uses `claude-sonnet-4-5`. Swap for a different model in `server.js`.
- **Colours** — the brand palette lives in `:root` in `src/styles.css`.
- **Voice** — the `useSpeechSynthesis` hook prefers natural/neural voices. Tweak `pickVoice` to lock to a specific one.

## Troubleshooting

- **"Speech recognition not supported"** — use Chrome or Edge. Safari and Firefox have spotty `webkitSpeechRecognition` support.
- **Mic doesn't work** — browsers require HTTPS *or* localhost, and an explicit permission prompt. Click the mic icon in the address bar and allow access.
- **`ANTHROPIC_API_KEY not set`** — you haven't copied `.env.example` to `.env` and pasted a real key.
- **The tutor never draws** — that's usually a model-output-parsing issue; open devtools console and check the raw response. The prompt heavily encourages drawing for visual subjects.

## License

MIT. Built with Claude, Vite, React, and the Web Speech API.
