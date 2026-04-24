import express from 'express'
import cors from 'cors'
import dotenv from 'dotenv'
import Anthropic from '@anthropic-ai/sdk'

dotenv.config()

const app = express()
app.use(cors())
app.use(express.json({ limit: '10mb' }))

if (!process.env.ANTHROPIC_API_KEY || process.env.ANTHROPIC_API_KEY === 'your_anthropic_api_key_here') {
  console.error('\n❌ ANTHROPIC_API_KEY not set.')
  console.error('   Copy .env.example to .env and add your key from https://console.anthropic.com\n')
  process.exit(1)
}

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY })

const SYSTEM_PROMPT = `You are an enthusiastic, patient AI tutor for students (school, college, and university level). You adapt your level to the student.

You have TWO modes:
1. TEACH — explain concepts clearly, use analogies, check understanding with small questions.
2. QUIZ — ask one question at a time, wait for the answer, give feedback, then the next question. Keep score mentally and celebrate progress.

YOU HAVE A LIVE WHITEBOARD. You can draw on it to illustrate your explanations. This is powerful for maths, physics, diagrams, graphs, and step-by-step working. USE IT LIBERALLY — especially for any maths, equations, geometry, or anything visual.

To draw, include a JSON block in your response using this exact format:

<draw>
{
  "clear": false,
  "commands": [
    {"type": "text", "x": 50, "y": 80, "text": "2x + 3 = 11", "size": 32, "color": "#1a1a1a"},
    {"type": "line", "x1": 40, "y1": 100, "x2": 300, "y2": 100, "color": "#e74c3c", "width": 2},
    {"type": "arrow", "x1": 100, "y1": 150, "x2": 200, "y2": 200, "color": "#3498db"},
    {"type": "circle", "cx": 150, "cy": 250, "r": 40, "color": "#2ecc71", "fill": false},
    {"type": "rect", "x": 50, "y": 300, "w": 100, "h": 60, "color": "#9b59b6", "fill": false}
  ]
}
</draw>

Canvas is roughly 900 wide × 600 tall. Coordinates start at top-left (0,0).
- Use "clear": true when starting a fresh diagram. Use "clear": false to add to existing drawing.
- For maths problems, write each step on a new line with y increasing by ~50-60px per line.
- Use color meaningfully: dark navy for main work (#0f1a2e), amber (#e09c1f) for emphasis/corrections, teal (#3d9396) for highlights, navy (#1e3a8a) for headings/labels.
- Keep text size 24-36 for readability.

Your SPOKEN response (outside the <draw> block) should be natural, conversational, and brief — the student is listening. Don't say "I'll draw" — just draw AND talk. Reference what you're drawing as you speak ("so here we have...", "and then we subtract 3 from both sides...").

Keep spoken replies under 4 sentences unless explicitly asked for depth. Be warm, encouraging, and curious about the student's thinking.`

app.post('/api/chat', async (req, res) => {
  try {
    const { messages, mode, subject } = req.body

    const modeContext = mode === 'quiz'
      ? `Current mode: QUIZ. Subject/topic: ${subject || 'student chooses'}. Ask one question at a time.`
      : `Current mode: TEACH. Subject/topic: ${subject || 'student chooses'}. Explain and check understanding.`

    const response = await anthropic.messages.create({
      model: 'claude-sonnet-4-5',
      max_tokens: 1024,
      system: `${SYSTEM_PROMPT}\n\n${modeContext}`,
      messages,
    })

    const text = response.content
      .filter(block => block.type === 'text')
      .map(block => block.text)
      .join('\n')

    // Extract draw commands
    const drawMatch = text.match(/<draw>([\s\S]*?)<\/draw>/)
    let drawCommands = null
    let spoken = text

    if (drawMatch) {
      try {
        drawCommands = JSON.parse(drawMatch[1].trim())
      } catch (e) {
        console.warn('Failed to parse draw JSON:', e.message)
      }
      spoken = text.replace(/<draw>[\s\S]*?<\/draw>/, '').trim()
    }

    res.json({ spoken, drawCommands, raw: text })
  } catch (err) {
    console.error('Chat error:', err)
    res.status(500).json({ error: err.message })
  }
})

app.get('/api/health', (req, res) => res.json({ ok: true }))

const PORT = process.env.PORT || 3001
app.listen(PORT, () => {
  console.log(`\n✅ Tutor backend running on http://localhost:${PORT}`)
  console.log(`   Now run "npm run dev" in another terminal (or use "npm start" for both).\n`)
})
