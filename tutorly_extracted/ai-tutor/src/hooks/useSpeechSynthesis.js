import { useCallback, useEffect, useRef, useState } from 'react'

export function useSpeechSynthesis() {
  const [speaking, setSpeaking] = useState(false)
  const [voices, setVoices] = useState([])
  const utterRef = useRef(null)

  useEffect(() => {
    const load = () => {
      const v = window.speechSynthesis?.getVoices() || []
      setVoices(v)
    }
    load()
    if (window.speechSynthesis) {
      window.speechSynthesis.onvoiceschanged = load
    }
    return () => {
      if (window.speechSynthesis) window.speechSynthesis.onvoiceschanged = null
    }
  }, [])

  const pickVoice = useCallback(() => {
    if (!voices.length) return null
    // Prefer high-quality English voices
    const prefs = [
      v => v.lang?.startsWith('en') && /natural|neural|premium|enhanced/i.test(v.name),
      v => v.lang?.startsWith('en-GB') && /female|samantha|karen|fiona/i.test(v.name),
      v => v.lang?.startsWith('en-US') && /female|samantha|karen/i.test(v.name),
      v => v.lang?.startsWith('en-GB'),
      v => v.lang?.startsWith('en'),
    ]
    for (const pred of prefs) {
      const found = voices.find(pred)
      if (found) return found
    }
    return voices[0]
  }, [voices])

  const speak = useCallback((text, onEnd) => {
    if (!window.speechSynthesis || !text) { onEnd?.(); return }
    window.speechSynthesis.cancel()
    const u = new SpeechSynthesisUtterance(text)
    const v = pickVoice()
    if (v) u.voice = v
    u.rate = 1.02
    u.pitch = 1.0
    u.volume = 1.0
    u.onstart = () => setSpeaking(true)
    u.onend = () => { setSpeaking(false); onEnd?.() }
    u.onerror = () => { setSpeaking(false); onEnd?.() }
    utterRef.current = u
    window.speechSynthesis.speak(u)
  }, [pickVoice])

  const stop = useCallback(() => {
    if (window.speechSynthesis) window.speechSynthesis.cancel()
    setSpeaking(false)
  }, [])

  return { speaking, speak, stop, supported: !!window.speechSynthesis }
}
