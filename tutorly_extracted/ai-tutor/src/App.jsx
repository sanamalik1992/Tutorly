import { useEffect, useRef, useState, useCallback } from 'react'
import { Whiteboard } from './components/Whiteboard.jsx'
import { useSpeechRecognition } from './hooks/useSpeechRecognition.js'
import { useSpeechSynthesis } from './hooks/useSpeechSynthesis.js'

const COLORS = [
  { name: 'ink', value: '#0f1a2e' },
  { name: 'navy', value: '#1e3a8a' },
  { name: 'teal', value: '#3d9396' },
  { name: 'amber', value: '#e09c1f' },
  { name: 'rose', value: '#c73e5f' },
]

const QUICK_SUBJECTS = [
  'Algebra', 'Calculus', 'Physics', 'Chemistry',
  'Biology', 'History', 'Essay writing', 'Python',
]

// Keep at most this many prior turns in context
const MAX_HISTORY = 20

export default function App() {
  const [mode, setMode] = useState('teach')
  const [subject, setSubject] = useState('')
  const [messages, setMessages] = useState([])
  const [thinking, setThinking] = useState(false)
  const [tool, setTool] = useState('pen')
  const [color, setColor] = useState('#0f1a2e')
  const [size, setSize] = useState(3)
  const [textInput, setTextInput] = useState('')
  const [handsFree, setHandsFree] = useState(false)

  const boardRef = useRef(null)
  const transcriptRef = useRef(null)
  const messagesRef = useRef(messages)
  const handsFreeRef = useRef(handsFree)
  const thinkingRef = useRef(thinking)

  useEffect(() => { messagesRef.current = messages }, [messages])
  useEffect(() => { handsFreeRef.current = handsFree }, [handsFree])
  useEffect(() => { thinkingRef.current = thinking }, [thinking])

  const rec = useSpeechRecognition()
  const tts = useSpeechSynthesis()

  useEffect(() => {
    transcriptRef.current?.scrollTo({ top: transcriptRef.current.scrollHeight, behavior: 'smooth' })
  }, [messages, thinking])

  const sendMessage = useCallback(async (userText) => {
    if (!userText?.trim() || thinkingRef.current) return

    const current = messagesRef.current
    const newMessages = [...current, { role: 'user', content: userText }]
    setMessages(newMessages)
    setThinking(true)

    const trimmed = newMessages.slice(-MAX_HISTORY)

    try {
      const res = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          messages: trimmed.map(m => ({ role: m.role, content: m.content })),
          mode,
          subject,
        }),
      })
      if (!res.ok) {
        const body = await res.text()
        throw new Error(`HTTP ${res.status}: ${body.slice(0, 120)}`)
      }
      const data = await res.json()

      setMessages([...newMessages, { role: 'assistant', content: data.spoken || '(no reply)' }])

      if (data.drawCommands?.commands?.length && boardRef.current) {
        boardRef.current.runCommands(data.drawCommands.commands, !!data.drawCommands.clear)
      }

      if (data.spoken) {
        tts.speak(data.spoken, () => {
          if (handsFreeRef.current && rec.supported) {
            setTimeout(() => rec.start(sendMessage), 400)
          }
        })
      } else if (handsFreeRef.current && rec.supported) {
        setTimeout(() => rec.start(sendMessage), 400)
      }
    } catch (err) {
      console.error(err)
      setMessages(prev => [...prev, {
        role: 'assistant',
        content: `Sorry, I hit an error: ${err.message}. Is the backend running on http://localhost:3001?`
      }])
    } finally {
      setThinking(false)
    }
  }, [mode, subject, tts, rec])

  const handleMicClick = () => {
    if (tts.speaking) { tts.stop(); return }
    if (rec.listening) { rec.stop(); return }
    if (!rec.supported) {
      alert('Speech recognition isn\'t supported in this browser. Try Chrome or Edge — or just type below.')
      return
    }
    rec.start(sendMessage)
  }

  const handleTextSubmit = (e) => {
    e.preventDefault()
    if (!textInput.trim()) return
    sendMessage(textInput)
    setTextInput('')
  }

  const handleClearBoard = () => boardRef.current?.clearAll()

  const handleSaveBoard = () => {
    const dataUrl = boardRef.current?.exportImage()
    if (!dataUrl) return
    const a = document.createElement('a')
    a.href = dataUrl
    a.download = `tutorly-board-${Date.now()}.png`
    a.click()
  }

  const handleNewSession = () => {
    if (messages.length && !confirm('Start a new session? This clears the conversation and whiteboard.')) return
    tts.stop()
    rec.stop()
    setMessages([])
    boardRef.current?.clearAll()
  }

  const startSession = (preset) => {
    setSubject(preset)
    const msg = mode === 'quiz' ? `Quiz me on ${preset}.` : `Teach me about ${preset}.`
    sendMessage(msg)
  }

  const voiceStatus = () => {
    if (thinking) return <><span className="live">Thinking</span>working it out…</>
    if (rec.listening) return <><span className="live">Listening</span>{rec.interim || 'go ahead, I\'m listening…'}</>
    if (tts.speaking) return <><span className="live">Speaking</span>tap mic to interrupt</>
    if (!messages.length) return <>Tap the mic or pick a subject to begin.</>
    if (handsFree) return <>Hands-free on — I'll listen again when I finish speaking.</>
    return <>Tap the mic to reply.</>
  }

  return (
    <div className="app">
      <header className="header">
        <div className="brand-wrap">
          <div className="brand-mark">T</div>
          <div>
            <div className="brand">Tutor<em>ly</em><span className="dot">.</span></div>
            <div className="tagline">Your AI study buddy</div>
          </div>
        </div>
        <div className="header-right">
          <label className="hands-free-toggle" title="Auto-listen after tutor speaks">
            <input
              type="checkbox"
              checked={handsFree}
              onChange={e => setHandsFree(e.target.checked)}
            />
            <span>Hands-free</span>
          </label>
          <button className="icon-btn" onClick={handleNewSession} title="New session">↻</button>
        </div>
      </header>

      <aside className="sidebar">
        <div>
          <div className="section-label">Mode</div>
          <div className="mode-toggle">
            <button
              className={`mode-btn ${mode === 'teach' ? 'active' : ''}`}
              onClick={() => setMode('teach')}
            >Teach me</button>
            <button
              className={`mode-btn ${mode === 'quiz' ? 'active' : ''}`}
              onClick={() => setMode('quiz')}
            >Quiz me</button>
          </div>
        </div>

        <div>
          <div className="section-label">Subject</div>
          <input
            className="subject-input"
            placeholder="e.g. GCSE physics, Year 2 calc"
            value={subject}
            onChange={e => setSubject(e.target.value)}
          />
          <div className="quick-chips">
            {QUICK_SUBJECTS.map(s => (
              <button key={s} className="chip" onClick={() => startSession(s)}>{s}</button>
            ))}
          </div>
        </div>

        <div className="transcript-section">
          <div className="section-label">Conversation</div>
          <div className="transcript" ref={transcriptRef}>
            {messages.length === 0 && (
              <div className="empty">
                <h2>No conversation yet</h2>
                <p>Pick a subject chip, or tap the mic<br />and just start talking.</p>
              </div>
            )}
            {messages.map((m, i) => (
              <div key={i} className={`msg ${m.role === 'user' ? 'user' : 'tutor'}`}>
                <div className="who">{m.role === 'user' ? 'You' : 'Tutorly'}</div>
                <div className="msg-body">{m.content}</div>
              </div>
            ))}
            {thinking && (
              <div className="msg tutor">
                <div className="who">Tutorly</div>
                <div className="thinking-dots"><span></span><span></span><span></span></div>
              </div>
            )}
          </div>
        </div>
      </aside>

      <main className="main">
        <div className="board-bar">
          <div className="tool-group">
            <button
              className={`tool-btn ${tool === 'pen' ? 'active' : ''}`}
              onClick={() => setTool('pen')}
              title="Pen"
            >✎</button>
            <button
              className={`tool-btn ${tool === 'eraser' ? 'active' : ''}`}
              onClick={() => setTool('eraser')}
              title="Eraser"
            >⌫</button>
            <div className="divider" />
            {COLORS.map(c => (
              <button
                key={c.value}
                className={`color-swatch ${color === c.value ? 'active' : ''}`}
                style={{ background: c.value }}
                onClick={() => { setColor(c.value); setTool('pen') }}
                title={c.name}
              />
            ))}
            <div className="divider" />
            <input
              type="range"
              min="1" max="12" value={size}
              onChange={e => setSize(Number(e.target.value))}
              className="size-slider"
              title="Brush size"
            />
          </div>
          <div className="board-bar-right">
            <button className="clear-btn" onClick={handleSaveBoard}>Save ↓</button>
            <button className="clear-btn" onClick={handleClearBoard}>Clear</button>
          </div>
        </div>

        <Whiteboard ref={boardRef} tool={tool} color={color} size={size} />

        <div className="voice-bar">
          <button
            className={`mic-btn ${rec.listening ? 'listening' : ''} ${tts.speaking ? 'speaking' : ''}`}
            onClick={handleMicClick}
            disabled={thinking}
            title={rec.listening ? 'Stop listening' : tts.speaking ? 'Stop speaking' : 'Tap to speak'}
          >
            {rec.listening ? '■' : tts.speaking ? '♪' : '🎙'}
          </button>
          <div className="voice-status">{voiceStatus()}</div>
          <form onSubmit={handleTextSubmit} className="text-form">
            <input
              className="text-input"
              placeholder="…or type your question"
              value={textInput}
              onChange={e => setTextInput(e.target.value)}
            />
            <button type="submit" className="send-btn" disabled={!textInput.trim() || thinking}>Send</button>
          </form>
        </div>
      </main>
    </div>
  )
}
