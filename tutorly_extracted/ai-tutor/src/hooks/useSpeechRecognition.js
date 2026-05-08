import { useEffect, useRef, useState, useCallback } from 'react'

export function useSpeechRecognition() {
  const [supported, setSupported] = useState(false)
  const [listening, setListening] = useState(false)
  const [interim, setInterim] = useState('')
  const recognitionRef = useRef(null)
  const onFinalRef = useRef(null)

  useEffect(() => {
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition
    if (!SR) return
    setSupported(true)

    const rec = new SR()
    rec.continuous = false
    rec.interimResults = true
    rec.lang = 'en-US'
    rec.maxAlternatives = 1

    rec.onresult = (ev) => {
      let interimT = ''
      let finalT = ''
      for (let i = ev.resultIndex; i < ev.results.length; i++) {
        const r = ev.results[i]
        if (r.isFinal) finalT += r[0].transcript
        else interimT += r[0].transcript
      }
      if (interimT) setInterim(interimT)
      if (finalT) {
        setInterim('')
        if (onFinalRef.current) onFinalRef.current(finalT.trim())
      }
    }

    rec.onend = () => setListening(false)
    rec.onerror = (e) => {
      console.warn('Speech recognition error:', e.error)
      setListening(false)
    }

    recognitionRef.current = rec
    return () => { try { rec.abort() } catch {} }
  }, [])

  const start = useCallback((onFinal) => {
    if (!recognitionRef.current) return
    onFinalRef.current = onFinal
    setInterim('')
    try {
      recognitionRef.current.start()
      setListening(true)
    } catch {
      // already started
    }
  }, [])

  const stop = useCallback(() => {
    if (!recognitionRef.current) return
    try { recognitionRef.current.stop() } catch {}
    setListening(false)
  }, [])

  return { supported, listening, interim, start, stop }
}
